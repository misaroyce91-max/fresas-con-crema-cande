create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_level uuid;
begin
  select id into v_level from public.customer_levels order by min_lifetime_points, sort_order limit 1;
  if coalesce(new.raw_app_meta_data ->> 'role', 'CLIENT') in ('CLIENT', 'CUSTOMER') then
    insert into public.customers(id,name,phone,level_id)
    values(
      new.id,
      trim(coalesce(nullif(new.raw_user_meta_data ->> 'name',''),'Cliente Cande')),
      regexp_replace(coalesce(new.phone,new.raw_user_meta_data ->> 'phone',''),'[^0-9+]','','g'),
      v_level
    ) on conflict (id) do nothing;
  end if;
  return new;
end $$;

create or replace function private.ensure_customer_profile(p_user uuid)
returns public.customers language plpgsql security definer set search_path = ''
as $$
declare
  v_auth auth.users;
  v_customer public.customers;
  v_level uuid;
  v_role text;
begin
  if p_user is null or p_user <> auth.uid() then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_customer from public.customers where id=p_user;
  if found then return v_customer; end if;
  select * into v_auth from auth.users where id=p_user;
  if not found then raise exception 'SESSION_INVALID'; end if;
  v_role := coalesce(v_auth.raw_app_meta_data ->> 'role','CLIENT');
  if v_role not in ('CLIENT','CUSTOMER') then raise exception 'CUSTOMER_ROLE_REQUIRED'; end if;
  select id into v_level from public.customer_levels order by min_lifetime_points, sort_order limit 1;
  insert into public.customers(id,name,phone,level_id)
  values(v_auth.id,trim(coalesce(nullif(v_auth.raw_user_meta_data ->> 'name',''),'Cliente Cande')),regexp_replace(coalesce(v_auth.phone,v_auth.raw_user_meta_data ->> 'phone',''),'[^0-9+]','','g'),v_level)
  on conflict (id) do nothing;
  select * into v_customer from public.customers where id=p_user;
  if not found then raise exception 'CUSTOMER_PROFILE_CREATE_FAILED'; end if;
  return v_customer;
end $$;

insert into public.customers(id,name,phone,level_id)
select u.id,
       trim(coalesce(nullif(u.raw_user_meta_data ->> 'name',''),'Cliente Cande')),
       regexp_replace(coalesce(u.phone,u.raw_user_meta_data ->> 'phone',''),'[^0-9+]','','g'),
       (select id from public.customer_levels order by min_lifetime_points, sort_order limit 1)
from auth.users u
left join public.customers c on c.id=u.id
where c.id is null
  and coalesce(u.raw_app_meta_data ->> 'role','CLIENT') in ('CLIENT','CUSTOMER')
on conflict (id) do nothing;

revoke all on function private.ensure_customer_profile(uuid) from public,anon,authenticated;

do $$
declare v_definition text;
begin
  select pg_get_functiondef('private.place_order_impl(uuid,jsonb,text,jsonb,text,text,text)'::regprocedure) into v_definition;
  v_definition := replace(
    v_definition,
    'select * into v_customer from public.customers where id = v_user for update;' || chr(10) || '  if not found then raise exception ''CUSTOMER_NOT_FOUND''; end if;',
    'v_customer := private.ensure_customer_profile(v_user);' || chr(10) || '  select * into v_customer from public.customers where id = v_user for update;'
  );
  if position('CUSTOMER_NOT_FOUND' in v_definition) > 0 then raise exception 'PLACE_ORDER_PATCH_FAILED'; end if;
  execute v_definition;
end $$;
