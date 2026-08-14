-- Expose only the product summary needed by the assigned/available driver UI.
drop function if exists public.driver_available_requests();
drop function if exists private.driver_available_requests_impl();

create function private.driver_available_requests_impl()
returns table(id uuid,order_id uuid,pay numeric,pickup_address text,status text,order_number bigint,delivery_address text,maps_url text,order_items jsonb)
language sql security definer set search_path=''
as $$
 select r.id,r.order_id,r.pay,r.pickup_address,r.status,o.order_number,
        coalesce(o.address->>'address','Zona por confirmar'),o.address->>'mapsUrl',
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'product_name',i.product_name,
            'size_name',i.size_name,
            'quantity',i.quantity
          ) order by i.id)
          from public.order_items i
          where i.order_id=o.id
        ),'[]'::jsonb)
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

create function public.driver_available_requests()
returns table(id uuid,order_id uuid,pay numeric,pickup_address text,status text,order_number bigint,delivery_address text,maps_url text,order_items jsonb)
language sql security definer set search_path=''
as $$select * from private.driver_available_requests_impl()$$;

revoke all on function public.driver_available_requests(),private.driver_available_requests_impl() from public,anon;
grant execute on function public.driver_available_requests() to authenticated;

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
   'orders',jsonb_build_object(
     'id',o.id,'order_number',o.order_number,'total',o.total,'address',o.address,
     'references_text',o.references_text,'notes',o.notes,'payment_method',o.payment_method,
     'customers',jsonb_build_object('name',cu.name,'phone',cu.phone),
     'order_items',coalesce((
       select jsonb_agg(jsonb_build_object(
         'product_name',i.product_name,
         'size_name',i.size_name,
         'quantity',i.quantity
       ) order by i.id)
       from public.order_items i
       where i.order_id=o.id
     ),'[]'::jsonb)
   )
 ) order by a.accepted_at desc),'[]'::jsonb) into v_assignments
 from public.delivery_assignments a
 join public.orders o on o.id=a.order_id
 join public.customers cu on cu.id=o.customer_id
 where a.courier_id=v_courier.id;
 return jsonb_build_object('id',v_courier.id,'name',v_courier.name,'phone',v_courier.phone,'status',v_courier.status,'fee_per_delivery',v_courier.fee_per_delivery,'delivery_assignments',v_assignments);
end $$;

revoke all on function private.driver_dashboard_impl() from public,anon;
grant execute on function private.driver_dashboard_impl() to authenticated;
