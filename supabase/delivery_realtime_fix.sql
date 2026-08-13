create table if not exists public.delivery_request_rejections (
  request_id uuid not null references public.delivery_requests(id) on delete cascade,
  courier_id uuid not null references public.couriers(id) on delete cascade,
  rejected_at timestamptz not null default now(),
  primary key(request_id,courier_id)
);
alter table public.delivery_request_rejections enable row level security;
create policy customer_reads_delivery_request on public.delivery_requests for select to authenticated using (exists(select 1 from public.orders o where o.id=delivery_requests.order_id and o.customer_id=(select auth.uid())));
create policy customer_reads_delivery_assignment on public.delivery_assignments for select to authenticated using (exists(select 1 from public.orders o where o.id=delivery_assignments.order_id and o.customer_id=(select auth.uid())));
create policy driver_reads_own_rejections on public.delivery_request_rejections for select to authenticated using (courier_id=(select c.id from public.couriers c where c.user_id=(select auth.uid())));
create policy admin_rejections_all on public.delivery_request_rejections for all to authenticated using(private.is_admin()) with check(private.is_admin());
grant select on public.delivery_request_rejections to authenticated;

create or replace function private.reject_delivery_impl(p_request_id uuid)
returns void language plpgsql security definer set search_path=''
as $$ declare v_courier uuid; begin
 if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
 select id into v_courier from public.couriers where user_id=auth.uid() and active and status='available';
 if v_courier is null then raise exception 'DRIVER_NOT_AVAILABLE'; end if;
 if not exists(select 1 from public.delivery_requests where id=p_request_id and status='requested') then raise exception 'DELIVERY_ALREADY_TAKEN'; end if;
 insert into public.delivery_request_rejections(request_id,courier_id) values(p_request_id,v_courier) on conflict do nothing;
end $$;
create or replace function public.reject_delivery(p_request_id uuid) returns void language sql security invoker set search_path='' as $$select private.reject_delivery_impl(p_request_id)$$;
revoke all on function public.reject_delivery(uuid),private.reject_delivery_impl(uuid) from public,anon;
grant execute on function public.reject_delivery(uuid) to authenticated;
do $$ begin alter publication supabase_realtime add table public.delivery_request_rejections; exception when duplicate_object then null; end $$;
