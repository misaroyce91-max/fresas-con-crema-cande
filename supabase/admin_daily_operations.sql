-- Secure daily admin operations for customers and courier onboarding.
create or replace function private.admin_promote_driver_impl(p_email text,p_name text,p_phone text,p_fee numeric)
returns public.couriers language plpgsql security definer set search_path='' as $$
declare v_user auth.users;v_courier public.couriers;
begin
 if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 select * into v_user from auth.users where lower(email)=lower(trim(p_email)) for update;
 if not found then raise exception 'USER_NOT_FOUND'; end if;
 if v_user.id=auth.uid() then raise exception 'CANNOT_CHANGE_OWN_ADMIN_ROLE'; end if;
 update auth.users set raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)||jsonb_build_object('role','DRIVER') where id=v_user.id;
 insert into public.couriers(user_id,name,phone,status,active,fee_per_delivery,last_activity_at)
 values(v_user.id,trim(p_name),trim(p_phone),'unavailable',true,greatest(p_fee,0),now())
 on conflict(user_id) do update set name=excluded.name,phone=excluded.phone,fee_per_delivery=excluded.fee_per_delivery,active=true,last_activity_at=now()
 returning * into v_courier;
 return v_courier;
end $$;
create or replace function public.admin_promote_driver(p_email text,p_name text,p_phone text,p_fee numeric)
returns public.couriers language sql security definer set search_path='' as $$select private.admin_promote_driver_impl(p_email,p_name,p_phone,p_fee)$$;
revoke all on function public.admin_promote_driver(text,text,text,numeric) from public,anon;
grant execute on function public.admin_promote_driver(text,text,text,numeric) to authenticated;

create or replace function private.admin_adjust_customer_strawberries_impl(p_customer_id uuid,p_delta integer,p_reason text)
returns public.customers language plpgsql security definer set search_path='' as $$
declare v_customer public.customers;
begin
 if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 if p_delta=0 or length(trim(coalesce(p_reason,'')))<4 then raise exception 'INVALID_ADJUSTMENT'; end if;
 select * into v_customer from public.customers where id=p_customer_id for update;
 if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
 if v_customer.points_balance+p_delta<0 then raise exception 'INSUFFICIENT_BALANCE'; end if;
 update public.customers set points_balance=points_balance+p_delta,lifetime_points=lifetime_points+greatest(p_delta,0),updated_at=now() where id=p_customer_id returning * into v_customer;
 insert into public.points_transactions(customer_id,type,points,balance_after,description) values(p_customer_id,'adjustment',p_delta,v_customer.points_balance,'Ajuste ADMIN: '||trim(p_reason));
 return v_customer;
end $$;
create or replace function public.admin_adjust_customer_strawberries(p_customer_id uuid,p_delta integer,p_reason text)
returns public.customers language sql security definer set search_path='' as $$select private.admin_adjust_customer_strawberries_impl(p_customer_id,p_delta,p_reason)$$;
revoke all on function public.admin_adjust_customer_strawberries(uuid,integer,text) from public,anon;
grant execute on function public.admin_adjust_customer_strawberries(uuid,integer,text) to authenticated;
