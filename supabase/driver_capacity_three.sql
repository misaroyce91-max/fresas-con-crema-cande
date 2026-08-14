-- Allow each connected driver to carry at most three active deliveries.
create or replace function private.driver_available_requests_impl()
returns table(id uuid,order_id uuid,pay numeric,pickup_address text,status text,order_number bigint,delivery_address text,maps_url text)
language sql security definer set search_path=''
as $$
 select r.id,r.order_id,r.pay,r.pickup_address,r.status,o.order_number,
        coalesce(o.address->>'address','Zona por confirmar'),o.address->>'mapsUrl'
 from public.delivery_requests r
 join public.orders o on o.id=r.order_id
 join public.couriers c on c.user_id=auth.uid() and c.active and c.status='available'
 where private.is_driver() and r.status='requested'
   and (
     select count(*)
     from public.delivery_assignments a
     where a.courier_id=c.id and a.status not in ('delivered','cancelled')
   ) < 3
   and not exists(select 1 from public.delivery_request_rejections x where x.request_id=r.id and x.courier_id=c.id)
 order by r.requested_at;
$$;

create or replace function private.accept_delivery_impl(p_request_id uuid)
returns public.delivery_assignments language plpgsql security definer set search_path=''
as $$
declare
  v_courier public.couriers;
  v_request public.delivery_requests;
  v_assignment public.delivery_assignments;
  v_active_count integer;
begin
  if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;

  -- Serializes all accept attempts by this driver, including different requests.
  select * into v_courier
  from public.couriers
  where user_id=auth.uid() and active and status<>'unavailable'
  for update;
  if not found then raise exception 'DRIVER_NOT_AVAILABLE'; end if;

  select count(*) into v_active_count
  from public.delivery_assignments
  where courier_id=v_courier.id and status not in ('delivered','cancelled');
  if v_active_count >= 3 then raise exception 'DRIVER_CAPACITY_FULL'; end if;

  -- Only one driver can change a requested delivery to assigned.
  update public.delivery_requests
  set status='assigned',assigned_at=now(),updated_at=now()
  where id=p_request_id and status='requested'
  returning * into v_request;
  if v_request.id is null then raise exception 'DELIVERY_ALREADY_TAKEN'; end if;

  insert into public.delivery_assignments(order_id,courier_id,status,delivery_fee)
  values(v_request.order_id,v_courier.id,'accepted',v_request.pay)
  returning * into v_assignment;

  v_active_count := v_active_count + 1;
  update public.couriers
  set status=case when v_active_count >= 3 then 'busy' else 'available' end,
      last_activity_at=now()
  where id=v_courier.id;
  return v_assignment;
end $$;

create or replace function private.driver_update_delivery_impl(p_assignment_id uuid,p_status text)
returns public.delivery_assignments language plpgsql security definer set search_path=''
as $$
declare
  v public.delivery_assignments;
  v_active_count integer;
begin
  if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
  select a.* into v
  from public.delivery_assignments a
  join public.couriers c on c.id=a.courier_id
  where a.id=p_assignment_id and c.user_id=auth.uid()
  for update of a;
  if not found then raise exception 'ASSIGNMENT_NOT_FOUND'; end if;
  if not ((v.status='accepted' and p_status='heading_to_pickup') or
          (v.status='heading_to_pickup' and p_status='picked_up') or
          (v.status='picked_up' and p_status='delivering') or
          (v.status='delivering' and p_status='delivered')) then
    raise exception 'INVALID_DELIVERY_TRANSITION';
  end if;

  update public.delivery_assignments set status=p_status,updated_at=now()
  where id=v.id returning * into v;

  if p_status='delivered' then
    update public.orders set status='delivered',delivered_at=now() where id=v.order_id;
    select count(*) into v_active_count
    from public.delivery_assignments
    where courier_id=v.courier_id and status not in ('delivered','cancelled');
    update public.couriers
    set status=case when v_active_count >= 3 then 'busy' else 'available' end,
        last_activity_at=now()
    where id=v.courier_id;
  end if;
  return v;
end $$;

create or replace function private.driver_availability_impl(p_available boolean)
returns public.couriers language plpgsql security definer set search_path=''
as $$
declare
  v public.couriers;
  v_active_count integer;
begin
  if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
  select * into v from public.couriers
  where user_id=auth.uid() and active for update;
  if not found then raise exception 'COURIER_NOT_FOUND'; end if;

  select count(*) into v_active_count
  from public.delivery_assignments
  where courier_id=v.id and status not in ('delivered','cancelled');
  if not p_available and v_active_count > 0 then raise exception 'ACTIVE_DELIVERIES_EXIST'; end if;

  update public.couriers
  set status=case when not p_available then 'unavailable' when v_active_count >= 3 then 'busy' else 'available' end,
      last_activity_at=now()
  where id=v.id returning * into v;
  return v;
end $$;

revoke all on function private.driver_available_requests_impl(),private.accept_delivery_impl(uuid),private.driver_update_delivery_impl(uuid,text),private.driver_availability_impl(boolean) from public,anon;
