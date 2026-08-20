begin;

create or replace function private.normalize_mx_phone(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when length(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')) = 12
      and regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g') like '52%'
      then right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 10)
    else regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g')
  end
$$;

create or replace function private.admin_lookup_customer_by_phone_impl(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text := private.normalize_mx_phone(p_phone);
  v_customer public.customers;
  v_external public.external_contacts;
  v_orders integer := 0;
  v_delivered integer := 0;
  v_promo_used boolean := false;
begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if length(v_phone) < 10 then return jsonb_build_object('found', false); end if;

  select * into v_customer
  from public.customers
  where private.normalize_mx_phone(phone) = v_phone
  order by created_at
  limit 1;

  if found then
    select count(*), count(*) filter (where status = 'delivered')
      into v_orders, v_delivered
    from public.orders where customer_id = v_customer.id;
    select exists(
      select 1 from public.promotion_redemptions
      where customer_id = v_customer.id and status = 'used'
    ) into v_promo_used;
    return jsonb_build_object(
      'found', true, 'kind', 'customer', 'id', v_customer.id,
      'name', v_customer.name, 'phone', v_customer.phone,
      'orders', v_orders, 'delivered', v_delivered,
      'firstPurchasePromotionUsed', v_promo_used
    );
  end if;

  select * into v_external
  from public.external_contacts
  where private.normalize_mx_phone(phone) = v_phone
  order by created_at
  limit 1;
  if found then
    select count(*), count(*) filter (where status = 'delivered')
      into v_orders, v_delivered
    from public.orders where external_contact_id = v_external.id;
    return jsonb_build_object(
      'found', true, 'kind', 'external', 'id', v_external.id,
      'name', v_external.name, 'phone', v_external.phone,
      'orders', v_orders, 'delivered', v_delivered,
      'firstPurchasePromotionUsed', false
    );
  end if;

  return jsonb_build_object('found', false);
end
$$;

create or replace function public.admin_lookup_customer_by_phone(p_phone text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.admin_lookup_customer_by_phone_impl(p_phone) $$;

create or replace function private.driver_release_delivery_impl(
  p_assignment_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assignment public.delivery_assignments;
  v_request public.delivery_requests;
begin
  if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;

  select a.* into v_assignment
  from public.delivery_assignments a
  join public.couriers c on c.id = a.courier_id
  where a.id = p_assignment_id and c.user_id = auth.uid()
  for update of a;
  if not found then raise exception 'ASSIGNMENT_NOT_FOUND'; end if;
  if v_assignment.status not in ('accepted', 'heading_to_pickup') then
    raise exception 'DELIVERY_CAN_NO_LONGER_BE_RELEASED';
  end if;

  select * into v_request from public.delivery_requests
  where order_id = v_assignment.order_id for update;
  if not found then raise exception 'DELIVERY_REQUEST_NOT_FOUND'; end if;

  update public.delivery_assignments
  set status = 'cancelled', updated_at = now()
  where id = v_assignment.id;
  update public.delivery_requests
  set status = 'cancelled', assigned_at = null, updated_at = now()
  where id = v_request.id;
  update public.driver_offers
  set status = 'expired', responded_at = coalesce(responded_at, now())
  where request_id = v_request.id and status = 'offered';
  update public.orders set published_at = null where id = v_assignment.order_id;
  update public.couriers set status = 'available', last_activity_at = now()
  where id = v_assignment.courier_id and active;

  insert into public.audit_events(actor_id, event_type, entity_type, entity_id, reason, old_value, new_value)
  values (
    auth.uid(), 'driver_delivery_released', 'delivery_assignment', v_assignment.id::text,
    nullif(trim(p_reason), ''),
    jsonb_build_object('status', v_assignment.status, 'requestStatus', v_request.status),
    jsonb_build_object('status', 'cancelled', 'requestStatus', 'cancelled')
  );
  perform private.refresh_driver_metrics(v_assignment.courier_id);
  return jsonb_build_object('released', true, 'orderId', v_assignment.order_id);
end
$$;

create or replace function public.driver_release_delivery(
  p_assignment_id uuid,
  p_reason text default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select private.driver_release_delivery_impl(p_assignment_id, p_reason) $$;

revoke all on function private.normalize_mx_phone(text),
  private.admin_lookup_customer_by_phone_impl(text),
  private.driver_release_delivery_impl(uuid, text),
  public.admin_lookup_customer_by_phone(text),
  public.driver_release_delivery(uuid, text)
from public, anon;
grant execute on function public.admin_lookup_customer_by_phone(text),
  public.driver_release_delivery(uuid, text)
to authenticated;

create index if not exists orders_customer_status_idx
  on public.orders(customer_id, status) where customer_id is not null;
create index if not exists orders_external_contact_idx
  on public.orders(external_contact_id) where external_contact_id is not null;

commit;
