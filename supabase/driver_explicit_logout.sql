-- Leaving/minimizing the PWA never changes availability. Explicit logout may
-- disconnect the driver even when assignments remain active.
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

  update public.couriers
  set status=case when not p_available then 'unavailable' when v_active_count >= 3 then 'busy' else 'available' end,
      last_activity_at=now()
  where id=v.id returning * into v;
  return v;
end $$;

revoke all on function private.driver_availability_impl(boolean) from public,anon,authenticated;
