create table if not exists public.delivery_requests (
  id uuid primary key default gen_random_uuid(),
  order_id uuid unique not null references public.orders(id) on delete cascade,
  status text not null default 'requested' check (status in ('requested','assigned','cancelled')),
  pay numeric(10,2) not null check (pay >= 0),
  pickup_address text not null,
  requested_at timestamptz not null default now(),
  assigned_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.delivery_requests enable row level security;
alter table public.delivery_assignments drop constraint if exists delivery_assignments_status_check;
alter table public.delivery_assignments add constraint delivery_assignments_status_check check (status in ('accepted','heading_to_pickup','picked_up','delivering','delivered','cancelled'));

create policy admin_delivery_requests_all on public.delivery_requests for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy admin_couriers_all on public.couriers for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy drivers_read_open_requests on public.delivery_requests for select to authenticated using (
  private.is_driver() and (
    status='requested' and exists(select 1 from public.couriers c where c.user_id=(select auth.uid()) and c.active and c.status='available')
    or exists(select 1 from public.delivery_assignments a join public.couriers c on c.id=a.courier_id where a.order_id=delivery_requests.order_id and c.user_id=(select auth.uid()))
  )
);
grant select on public.delivery_requests to authenticated;
revoke insert,update,delete on public.delivery_requests from authenticated;

create or replace function private.admin_set_order_status_impl(p_order_id uuid,p_status public.order_status)
returns public.orders language plpgsql security definer set search_path=''
as $$ declare v public.orders; begin
 if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 select * into v from public.orders where id=p_order_id for update;
 if not found then raise exception 'ORDER_NOT_FOUND'; end if;
 if not ((v.status='pending' and p_status='confirmed') or (v.status='confirmed' and p_status='preparing') or (v.status='preparing' and p_status='ready')) then raise exception 'INVALID_STATUS_TRANSITION'; end if;
 update public.orders set status=p_status where id=p_order_id returning * into v; return v;
end $$;
create or replace function public.admin_set_order_status(p_order_id uuid,p_status public.order_status) returns public.orders language sql security invoker set search_path='' as $$select private.admin_set_order_status_impl(p_order_id,p_status)$$;

create or replace function private.request_driver_impl(p_order_id uuid,p_pay numeric,p_pickup_address text)
returns public.delivery_requests language plpgsql security definer set search_path=''
as $$ declare v_order public.orders; v_request public.delivery_requests; begin
 if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found or v_order.delivery_type<>'delivery' or v_order.status<>'ready' then raise exception 'ORDER_NOT_READY_FOR_DELIVERY'; end if;
 insert into public.delivery_requests(order_id,pay,pickup_address) values(p_order_id,greatest(p_pay,0),trim(p_pickup_address))
 on conflict(order_id) do update set status='requested',pay=excluded.pay,pickup_address=excluded.pickup_address,assigned_at=null,updated_at=now()
 where public.delivery_requests.status='cancelled' returning * into v_request;
 if v_request.id is null then select * into v_request from public.delivery_requests where order_id=p_order_id; end if;
 return v_request;
end $$;
create or replace function public.request_driver(p_order_id uuid,p_pay numeric,p_pickup_address text) returns public.delivery_requests language sql security invoker set search_path='' as $$select private.request_driver_impl(p_order_id,p_pay,p_pickup_address)$$;

create or replace function private.driver_availability_impl(p_available boolean)
returns public.couriers language plpgsql security definer set search_path=''
as $$ declare v public.couriers; begin
 if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
 update public.couriers set status=case when p_available then 'available' else 'unavailable' end,last_activity_at=now()
 where user_id=auth.uid() and active and status<>'busy' returning * into v;
 if v.id is null then raise exception 'COURIER_NOT_FOUND_OR_BUSY'; end if; return v;
end $$;
create or replace function public.driver_availability(p_available boolean) returns public.couriers language sql security invoker set search_path='' as $$select private.driver_availability_impl(p_available)$$;

create or replace function private.accept_delivery_impl(p_request_id uuid)
returns public.delivery_assignments language plpgsql security definer set search_path=''
as $$ declare v_courier public.couriers; v_request public.delivery_requests; v_assignment public.delivery_assignments; begin
 if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
 select * into v_courier from public.couriers where user_id=auth.uid() and active and status='available' for update;
 if not found then raise exception 'DRIVER_NOT_AVAILABLE'; end if;
 update public.delivery_requests set status='assigned',assigned_at=now(),updated_at=now() where id=p_request_id and status='requested' returning * into v_request;
 if v_request.id is null then raise exception 'DELIVERY_ALREADY_TAKEN'; end if;
 insert into public.delivery_assignments(order_id,courier_id,status,delivery_fee) values(v_request.order_id,v_courier.id,'accepted',v_request.pay) returning * into v_assignment;
 update public.couriers set status='busy',last_activity_at=now() where id=v_courier.id;
 return v_assignment;
end $$;
create or replace function public.accept_delivery(p_request_id uuid) returns public.delivery_assignments language sql security invoker set search_path='' as $$select private.accept_delivery_impl(p_request_id)$$;

create or replace function private.driver_update_delivery_impl(p_assignment_id uuid,p_status text)
returns public.delivery_assignments language plpgsql security definer set search_path=''
as $$ declare v public.delivery_assignments; v_courier public.couriers; begin
 if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
 select a.* into v from public.delivery_assignments a join public.couriers c on c.id=a.courier_id where a.id=p_assignment_id and c.user_id=auth.uid() for update;
 if not found then raise exception 'ASSIGNMENT_NOT_FOUND'; end if;
 if not ((v.status='accepted' and p_status='heading_to_pickup') or (v.status='heading_to_pickup' and p_status='picked_up') or (v.status='picked_up' and p_status='delivering') or (v.status='delivering' and p_status='delivered')) then raise exception 'INVALID_DELIVERY_TRANSITION'; end if;
 update public.delivery_assignments set status=p_status,updated_at=now() where id=v.id returning * into v;
 if p_status='delivered' then update public.orders set status='delivered',delivered_at=now() where id=v.order_id; update public.couriers set status='available',last_activity_at=now() where id=v.courier_id; end if;
 return v;
end $$;
create or replace function public.driver_update_delivery(p_assignment_id uuid,p_status text) returns public.delivery_assignments language sql security invoker set search_path='' as $$select private.driver_update_delivery_impl(p_assignment_id,p_status)$$;

revoke all on function public.admin_set_order_status(uuid,public.order_status),public.request_driver(uuid,numeric,text),public.driver_availability(boolean),public.accept_delivery(uuid),public.driver_update_delivery(uuid,text) from public,anon;
grant execute on function public.admin_set_order_status(uuid,public.order_status),public.request_driver(uuid,numeric,text),public.driver_availability(boolean),public.accept_delivery(uuid),public.driver_update_delivery(uuid,text) to authenticated;
alter publication supabase_realtime add table public.orders,public.delivery_requests,public.delivery_assignments,public.couriers;
