create index if not exists homepage_promotion_events_customer_idx
  on public.homepage_promotion_events(customer_id) where customer_id is not null;
create index if not exists homepage_promotions_created_by_idx
  on public.homepage_promotions(created_by) where created_by is not null;
