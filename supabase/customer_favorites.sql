-- Persistent customer favorites. This migration is additive and does not alter
-- existing customers, products, or order data.
create table if not exists public.customer_favorites (
  customer_id uuid not null references public.customers(id) on delete cascade,
  product_id text not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (customer_id, product_id)
);

create index if not exists customer_favorites_customer_created_idx
  on public.customer_favorites (customer_id, created_at desc);

alter table public.customer_favorites enable row level security;

drop policy if exists customer_favorites_select_own on public.customer_favorites;
create policy customer_favorites_select_own
  on public.customer_favorites
  for select
  to authenticated
  using ((select auth.uid()) = customer_id);

drop policy if exists customer_favorites_insert_own on public.customer_favorites;
create policy customer_favorites_insert_own
  on public.customer_favorites
  for insert
  to authenticated
  with check ((select auth.uid()) = customer_id);

drop policy if exists customer_favorites_delete_own on public.customer_favorites;
create policy customer_favorites_delete_own
  on public.customer_favorites
  for delete
  to authenticated
  using ((select auth.uid()) = customer_id);

revoke all on table public.customer_favorites from anon;
revoke all on table public.customer_favorites from authenticated;
grant select, insert, delete on table public.customer_favorites to authenticated;
