begin;

create or replace function private.admin_cancel_driver_search_impl(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.delivery_requests;
  v_changed boolean := false;
begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;

  select * into v_request
  from public.delivery_requests
  where order_id = p_order_id
  for update;
  if not found then raise exception 'DELIVERY_SEARCH_NOT_FOUND'; end if;

  if exists (
    select 1 from public.delivery_assignments
    where order_id = p_order_id and status not in ('cancelled', 'delivered')
  ) then
    raise exception 'DELIVERY_ALREADY_ASSIGNED';
  end if;

  if v_request.status = 'requested' then
    update public.delivery_requests
    set status = 'cancelled', assigned_at = null, updated_at = now()
    where id = v_request.id;
    v_changed := true;
  elsif v_request.status <> 'cancelled' then
    raise exception 'DELIVERY_SEARCH_NOT_ACTIVE';
  end if;

  update public.driver_offers
  set status = 'expired', responded_at = coalesce(responded_at, now())
  where request_id = v_request.id and status = 'offered';
  update public.orders set published_at = null where id = p_order_id;

  if v_changed then
    insert into public.audit_events(actor_id, event_type, entity_type, entity_id, reason, new_value)
    values (
      auth.uid(), 'driver_search_cancelled', 'order', p_order_id::text,
      'Cancelada por administrador',
      jsonb_build_object('requestId', v_request.id, 'status', 'cancelled')
    );
  end if;
end
$$;

create or replace function public.admin_cancel_driver_search(p_order_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$ select private.admin_cancel_driver_search_impl(p_order_id) $$;

create or replace function public.request_driver(
  p_order_id uuid,
  p_pay numeric,
  p_pickup_address text
)
returns public.delivery_requests
language sql
security definer
set search_path = ''
as $$ select private.request_driver_impl(p_order_id, p_pay, p_pickup_address) $$;

revoke all on function private.admin_cancel_driver_search_impl(uuid),
  private.request_driver_impl(uuid, numeric, text),
  private.build_driver_offers(uuid),
  public.admin_cancel_driver_search(uuid),
  public.request_driver(uuid, numeric, text)
from public, anon, authenticated;

grant execute on function public.admin_cancel_driver_search(uuid),
  public.request_driver(uuid, numeric, text)
to authenticated;

commit;
