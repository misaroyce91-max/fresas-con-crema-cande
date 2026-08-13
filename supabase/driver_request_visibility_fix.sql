create policy assigned_driver_reads_order on public.orders for select to authenticated using (
  private.is_driver() and exists(
    select 1 from public.delivery_assignments a
    join public.couriers c on c.id=a.courier_id
    where a.order_id=orders.id and c.user_id=(select auth.uid())
  )
);

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
   and not exists(select 1 from public.delivery_request_rejections x where x.request_id=r.id and x.courier_id=c.id)
 order by r.requested_at;
$$;
create or replace function public.driver_available_requests()
returns table(id uuid,order_id uuid,pay numeric,pickup_address text,status text,order_number bigint,delivery_address text,maps_url text)
language sql security invoker set search_path=''
as $$select * from private.driver_available_requests_impl()$$;
revoke all on function public.driver_available_requests(),private.driver_available_requests_impl() from public,anon;
grant execute on function public.driver_available_requests() to authenticated;
grant execute on function private.driver_available_requests_impl() to authenticated;
