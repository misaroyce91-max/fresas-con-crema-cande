-- Preserve an auditable timestamp for each delivery stage.
alter table public.delivery_assignments
  add column if not exists heading_to_pickup_at timestamptz,
  add column if not exists picked_up_at timestamptz,
  add column if not exists delivering_at timestamptz,
  add column if not exists delivered_at timestamptz;

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

  update public.delivery_assignments
  set status=p_status,
      updated_at=now(),
      heading_to_pickup_at=case when p_status='heading_to_pickup' then now() else heading_to_pickup_at end,
      picked_up_at=case when p_status='picked_up' then now() else picked_up_at end,
      delivering_at=case when p_status='delivering' then now() else delivering_at end,
      delivered_at=case when p_status='delivered' then now() else delivered_at end
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

revoke all on function private.driver_update_delivery_impl(uuid,text) from public,anon;
