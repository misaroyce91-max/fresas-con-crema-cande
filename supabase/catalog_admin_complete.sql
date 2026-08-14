alter table public.products
  add column if not exists category text not null default 'Fresas con crema',
  add column if not exists availability_status text not null default 'active',
  add column if not exists included_ingredients jsonb not null default '[]'::jsonb;
alter table public.products drop constraint if exists products_availability_status_check;
alter table public.products add constraint products_availability_status_check
  check (availability_status in ('active','sold_out','hidden'));

create table if not exists public.topping_products (
  topping_id uuid not null references public.toppings(id) on delete cascade,
  product_id text not null references public.products(id) on delete cascade,
  primary key(topping_id,product_id)
);
alter table public.topping_products enable row level security;
drop policy if exists catalog_topping_products_read on public.topping_products;
create policy catalog_topping_products_read on public.topping_products for select to anon,authenticated using (true);
drop policy if exists admin_topping_products_all on public.topping_products;
create policy admin_topping_products_all on public.topping_products for all to authenticated using (private.is_admin()) with check (private.is_admin());
grant select on public.topping_products to anon,authenticated;
grant insert,update,delete on public.topping_products to authenticated;

create table if not exists public.product_recipes (
  id uuid primary key default gen_random_uuid(),
  product_id text not null references public.products(id) on delete cascade,
  size_name text not null,
  components jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  unique(product_id,size_name)
);
alter table public.product_recipes enable row level security;
drop policy if exists admin_product_recipes_all on public.product_recipes;
create policy admin_product_recipes_all on public.product_recipes for all to authenticated using (private.is_admin()) with check (private.is_admin());
grant select,insert,update,delete on public.product_recipes to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('product-images','product-images',true,5242880,array['image/jpeg','image/png','image/webp','image/avif'])
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists product_images_public_read on storage.objects;
create policy product_images_public_read on storage.objects for select to public using (bucket_id='product-images');
drop policy if exists product_images_admin_insert on storage.objects;
create policy product_images_admin_insert on storage.objects for insert to authenticated with check (bucket_id='product-images' and private.is_admin());
drop policy if exists product_images_admin_update on storage.objects;
create policy product_images_admin_update on storage.objects for update to authenticated using (bucket_id='product-images' and private.is_admin()) with check (bucket_id='product-images' and private.is_admin());
drop policy if exists product_images_admin_delete on storage.objects;
create policy product_images_admin_delete on storage.objects for delete to authenticated using (bucket_id='product-images' and private.is_admin());

create or replace function private.admin_save_product_impl(p_product jsonb,p_sizes jsonb,p_topping_ids uuid[],p_recipe jsonb)
returns public.products language plpgsql security definer set search_path=''
as $$
declare v public.products;v_size jsonb;
begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if nullif(trim(p_product->>'id'),'') is null or nullif(trim(p_product->>'name'),'') is null then raise exception 'PRODUCT_FIELDS_REQUIRED'; end if;
  if coalesce(p_product->>'availability_status','active') not in ('active','sold_out','hidden') then raise exception 'INVALID_AVAILABILITY'; end if;
  insert into public.products(id,name,description,image_url,active,specialty,featured,favorite,sort_order,category,availability_status,included_ingredients)
  values(
    trim(p_product->>'id'),trim(p_product->>'name'),coalesce(p_product->>'description',''),nullif(p_product->>'image_url',''),
    coalesce(p_product->>'availability_status','active')='active',coalesce((p_product->>'specialty')::boolean,false),
    coalesce((p_product->>'featured')::boolean,false),coalesce((p_product->>'favorite')::boolean,false),
    coalesce((p_product->>'sort_order')::integer,0),coalesce(nullif(trim(p_product->>'category'),''),'Fresas con crema'),
    coalesce(p_product->>'availability_status','active'),coalesce(p_product->'included_ingredients','[]'::jsonb)
  ) on conflict(id) do update set name=excluded.name,description=excluded.description,image_url=excluded.image_url,
    active=excluded.active,specialty=excluded.specialty,featured=excluded.featured,favorite=excluded.favorite,
    sort_order=excluded.sort_order,category=excluded.category,availability_status=excluded.availability_status,
    included_ingredients=excluded.included_ingredients
  returning * into v;

  update public.product_sizes set active=false where product_id=v.id;
  for v_size in select value from jsonb_array_elements(coalesce(p_sizes,'[]'::jsonb)) loop
    if (v_size->>'name') in ('10 oz','12 oz','14 oz','16 oz') then
      insert into public.product_sizes(product_id,name,ounces,price,active)
      values(v.id,v_size->>'name',split_part(v_size->>'name',' ',1)::integer,greatest(coalesce((v_size->>'price')::numeric,0),0),coalesce((v_size->>'active')::boolean,false))
      on conflict(product_id,name) do update set price=excluded.price,active=excluded.active;
    end if;
  end loop;
  if not exists(select 1 from public.product_sizes where product_id=v.id and active) and v.active then raise exception 'ACTIVE_PRODUCT_REQUIRES_SIZE'; end if;

  delete from public.topping_products where product_id=v.id;
  insert into public.topping_products(topping_id,product_id)
  select id,v.id from public.toppings where id=any(coalesce(p_topping_ids,array[]::uuid[]));

  for v_size in select value from jsonb_array_elements(coalesce(p_sizes,'[]'::jsonb)) loop
    insert into public.product_recipes(product_id,size_name,components)
    values(v.id,v_size->>'name',coalesce(p_recipe,'[]'::jsonb))
    on conflict(product_id,size_name) do update set components=excluded.components,updated_at=now();
  end loop;
  return v;
end $$;
create or replace function public.admin_save_product(p_product jsonb,p_sizes jsonb,p_topping_ids uuid[],p_recipe jsonb)
returns public.products language sql security definer set search_path=''
as $$select private.admin_save_product_impl(p_product,p_sizes,p_topping_ids,p_recipe)$$;
revoke all on function public.admin_save_product(jsonb,jsonb,uuid[],jsonb) from public,anon;
grant execute on function public.admin_save_product(jsonb,jsonb,uuid[],jsonb) to authenticated;

create or replace function private.admin_save_topping_impl(p_id uuid,p_name text,p_price numeric,p_active boolean,p_product_ids text[])
returns public.toppings language plpgsql security definer set search_path=''
as $$declare v public.toppings;begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'TOPPING_NAME_REQUIRED'; end if;
  insert into public.toppings(id,name,price,active) values(coalesce(p_id,gen_random_uuid()),trim(p_name),greatest(p_price,0),p_active)
  on conflict(id) do update set name=excluded.name,price=excluded.price,active=excluded.active returning * into v;
  delete from public.topping_products where topping_id=v.id;
  insert into public.topping_products(topping_id,product_id) select v.id,id from public.products where id=any(coalesce(p_product_ids,array[]::text[]));
  return v;
end $$;
create or replace function public.admin_save_topping(p_id uuid,p_name text,p_price numeric,p_active boolean,p_product_ids text[])
returns public.toppings language sql security definer set search_path=''
as $$select private.admin_save_topping_impl(p_id,p_name,p_price,p_active,p_product_ids)$$;
revoke all on function public.admin_save_topping(uuid,text,numeric,boolean,text[]) from public,anon;
grant execute on function public.admin_save_topping(uuid,text,numeric,boolean,text[]) to authenticated;

do $$begin alter publication supabase_realtime add table public.products;exception when duplicate_object then null;end$$;
do $$begin alter publication supabase_realtime add table public.product_sizes;exception when duplicate_object then null;end$$;
do $$begin alter publication supabase_realtime add table public.toppings;exception when duplicate_object then null;end$$;
do $$begin alter publication supabase_realtime add table public.topping_products;exception when duplicate_object then null;end$$;
