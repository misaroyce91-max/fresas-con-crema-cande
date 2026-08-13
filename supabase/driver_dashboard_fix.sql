drop policy if exists assigned_driver_reads_order on public.orders;

create or replace function private.driver_dashboard_impl()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_courier public.couriers;v_assignments jsonb;
begin
 if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
 select * into v_courier from public.couriers where user_id=auth.uid() and active;
 if not found then raise exception 'COURIER_NOT_FOUND'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',a.id,'status',a.status,'delivery_fee',a.delivery_fee,'accepted_at',a.accepted_at,'updated_at',a.updated_at,
   'orders',jsonb_build_object('id',o.id,'order_number',o.order_number,'total',o.total,'address',o.address,'references_text',o.references_text,'notes',o.notes,'payment_method',o.payment_method,'customers',jsonb_build_object('name',cu.name,'phone',cu.phone))
 ) order by a.accepted_at desc),'[]'::jsonb) into v_assignments
 from public.delivery_assignments a join public.orders o on o.id=a.order_id join public.customers cu on cu.id=o.customer_id
 where a.courier_id=v_courier.id;
 return jsonb_build_object('id',v_courier.id,'name',v_courier.name,'phone',v_courier.phone,'status',v_courier.status,'fee_per_delivery',v_courier.fee_per_delivery,'delivery_assignments',v_assignments);
end $$;
create or replace function public.driver_dashboard() returns jsonb language sql security invoker set search_path='' as $$select private.driver_dashboard_impl()$$;
revoke all on function public.driver_dashboard(),private.driver_dashboard_impl() from public,anon;
grant execute on function public.driver_dashboard(),private.driver_dashboard_impl() to authenticated;
