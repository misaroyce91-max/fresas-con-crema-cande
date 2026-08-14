-- Catalog recipes, combinations and admin-approved smart promotions.
alter table public.products add column if not exists product_type text not null default 'product'
  check (product_type in ('product','combo'));

create table if not exists public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  unit text not null,
  unit_cost numeric(12,4) not null default 0 check (unit_cost >= 0),
  stock_quantity numeric(12,3) not null default 0 check (stock_quantity >= 0),
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.product_recipe_items (
  product_id text not null references public.products(id) on delete cascade,
  size_name text not null,
  inventory_item_id uuid not null references public.inventory_items(id),
  quantity numeric(12,3) not null check (quantity > 0),
  primary key(product_id,size_name,inventory_item_id)
);
create index if not exists product_recipe_items_inventory_idx on public.product_recipe_items(inventory_item_id);

create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  image_url text,
  promotion_type text not null default 'fixed_discount',
  status text not null default 'draft' check (status in ('suggested','draft','active','rejected','expired','paused')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  start_time time,
  end_time time,
  applicable_days integer[] not null default '{}',
  product_ids text[] not null default '{}',
  discount_amount numeric(10,2) not null default 0 check(discount_amount >= 0),
  discount_percent numeric(6,2) not null default 0 check(discount_percent between 0 and 100),
  combo_price numeric(10,2),
  free_shipping boolean not null default false,
  free_topping boolean not null default false,
  min_order_amount numeric(10,2) not null default 0,
  extra_points integer not null default 0,
  double_points boolean not null default false,
  usage_limit integer,
  usage_count integer not null default 0,
  normal_price numeric(10,2),
  estimated_cost numeric(10,2),
  normal_margin_percent numeric(7,2),
  promo_margin_percent numeric(7,2),
  estimated_profit numeric(10,2),
  additional_sales_needed numeric(10,2),
  rationale text,
  source text not null default 'manual',
  generated_at timestamptz,
  approved_at timestamptz,
  approved_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(ends_at > starts_at)
);
create index if not exists promotions_approved_by_idx on public.promotions(approved_by);
create index if not exists promotions_status_period_idx on public.promotions(status,starts_at,ends_at);

alter table public.inventory_items enable row level security;
alter table public.product_recipe_items enable row level security;
alter table public.promotions enable row level security;

drop policy if exists admin_inventory_all on public.inventory_items;
create policy admin_inventory_all on public.inventory_items for all to authenticated
  using (private.is_admin()) with check (private.is_admin());
drop policy if exists admin_recipe_items_all on public.product_recipe_items;
create policy admin_recipe_items_all on public.product_recipe_items for all to authenticated
  using (private.is_admin()) with check (private.is_admin());
drop policy if exists admin_promotions_all on public.promotions;
create policy admin_promotions_all on public.promotions for all to authenticated
  using (private.is_admin()) with check (private.is_admin());
drop policy if exists public_active_promotions_read on public.promotions;
create policy public_active_promotions_read on public.promotions for select to anon,authenticated
  using (status='active' and now() between starts_at and ends_at
    and (usage_limit is null or usage_count < usage_limit));

grant select,insert,update,delete on public.inventory_items,public.product_recipe_items,public.promotions to authenticated;
grant select on public.promotions to anon;

create or replace function public.admin_save_recipe(p_product_id text,p_size_name text,p_components jsonb)
returns void language plpgsql security invoker set search_path='public','private' as $$
begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  delete from public.product_recipe_items where product_id=p_product_id and size_name=p_size_name;
  insert into public.product_recipe_items(product_id,size_name,inventory_item_id,quantity)
  select p_product_id,p_size_name,(x->>'inventory_item_id')::uuid,(x->>'quantity')::numeric
  from jsonb_array_elements(coalesce(p_components,'[]'::jsonb)) x
  where nullif(x->>'inventory_item_id','') is not null and (x->>'quantity')::numeric > 0;
end $$;
revoke all on function public.admin_save_recipe(text,text,jsonb) from public,anon;
grant execute on function public.admin_save_recipe(text,text,jsonb) to authenticated;

create or replace function public.admin_upsert_inventory_item(p_name text,p_unit text,p_unit_cost numeric)
returns uuid language plpgsql security invoker set search_path='public','private' as $$
declare v_id uuid;
begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  insert into public.inventory_items(name,unit,unit_cost,updated_at)
  values(trim(p_name),trim(p_unit),greatest(p_unit_cost,0),now())
  on conflict(name) do update set unit=excluded.unit,unit_cost=excluded.unit_cost,updated_at=now()
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.admin_upsert_inventory_item(text,text,numeric) from public,anon;
grant execute on function public.admin_upsert_inventory_item(text,text,numeric) to authenticated;

create or replace function public.admin_save_promotion(p_data jsonb)
returns uuid language plpgsql security invoker set search_path='public','private' as $$
declare v_id uuid;
begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  v_id:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());
  insert into public.promotions(id,title,description,image_url,promotion_type,status,starts_at,ends_at,start_time,end_time,
    applicable_days,product_ids,discount_amount,discount_percent,combo_price,free_shipping,free_topping,min_order_amount,
    extra_points,double_points,usage_limit,normal_price,estimated_cost,normal_margin_percent,promo_margin_percent,
    estimated_profit,additional_sales_needed,rationale,source,generated_at,updated_at)
  values(v_id,p_data->>'title',coalesce(p_data->>'description',''),nullif(p_data->>'image_url',''),coalesce(p_data->>'promotion_type','fixed_discount'),
    coalesce(p_data->>'status','draft'),(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,
    nullif(p_data->>'start_time','')::time,nullif(p_data->>'end_time','')::time,
    coalesce(array(select jsonb_array_elements_text(coalesce(p_data->'applicable_days','[]'))::integer),'{}'),
    coalesce(array(select jsonb_array_elements_text(coalesce(p_data->'product_ids','[]'))),'{}'),
    coalesce((p_data->>'discount_amount')::numeric,0),coalesce((p_data->>'discount_percent')::numeric,0),nullif(p_data->>'combo_price','')::numeric,
    coalesce((p_data->>'free_shipping')::boolean,false),coalesce((p_data->>'free_topping')::boolean,false),coalesce((p_data->>'min_order_amount')::numeric,0),
    coalesce((p_data->>'extra_points')::integer,0),coalesce((p_data->>'double_points')::boolean,false),nullif(p_data->>'usage_limit','')::integer,
    nullif(p_data->>'normal_price','')::numeric,nullif(p_data->>'estimated_cost','')::numeric,nullif(p_data->>'normal_margin_percent','')::numeric,
    nullif(p_data->>'promo_margin_percent','')::numeric,nullif(p_data->>'estimated_profit','')::numeric,nullif(p_data->>'additional_sales_needed','')::numeric,
    nullif(p_data->>'rationale',''),coalesce(p_data->>'source','manual'),case when p_data->>'source'='smart' then now() else null end,now())
  on conflict(id) do update set title=excluded.title,description=excluded.description,image_url=excluded.image_url,
    promotion_type=excluded.promotion_type,status=excluded.status,starts_at=excluded.starts_at,ends_at=excluded.ends_at,
    start_time=excluded.start_time,end_time=excluded.end_time,applicable_days=excluded.applicable_days,product_ids=excluded.product_ids,
    discount_amount=excluded.discount_amount,discount_percent=excluded.discount_percent,combo_price=excluded.combo_price,
    free_shipping=excluded.free_shipping,free_topping=excluded.free_topping,min_order_amount=excluded.min_order_amount,
    extra_points=excluded.extra_points,double_points=excluded.double_points,usage_limit=excluded.usage_limit,
    normal_price=excluded.normal_price,estimated_cost=excluded.estimated_cost,normal_margin_percent=excluded.normal_margin_percent,
    promo_margin_percent=excluded.promo_margin_percent,estimated_profit=excluded.estimated_profit,
    additional_sales_needed=excluded.additional_sales_needed,rationale=excluded.rationale,updated_at=now();
  return v_id;
end $$;
revoke all on function public.admin_save_promotion(jsonb) from public,anon;
grant execute on function public.admin_save_promotion(jsonb) to authenticated;

create or replace function public.admin_set_promotion_status(p_id uuid,p_status text)
returns void language plpgsql security invoker set search_path='public','private' as $$
begin
 if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 if p_status not in ('active','rejected','paused','draft') then raise exception 'INVALID_STATUS'; end if;
 update public.promotions set status=p_status,approved_at=case when p_status='active' then now() else approved_at end,
  approved_by=case when p_status='active' then auth.uid() else approved_by end,updated_at=now() where id=p_id;
end $$;
revoke all on function public.admin_set_promotion_status(uuid,text) from public,anon;
grant execute on function public.admin_set_promotion_status(uuid,text) to authenticated;

create or replace function public.admin_smart_summary()
returns jsonb language plpgsql security invoker set search_path='public','private' as $$
declare result jsonb;
begin
 if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 with valid_orders as (select * from orders where status<>'cancelled'),
 day_sales as (select extract(isodow from created_at at time zone 'America/Mexico_City')::int day,sum(total) sales from valid_orders group by 1),
 hour_sales as (select extract(hour from created_at at time zone 'America/Mexico_City')::int hour,sum(total) sales from valid_orders group by 1),
 product_sales as (select oi.product_id,oi.product_name,sum(oi.quantity) qty,sum(oi.line_total) sales from order_items oi join valid_orders o on o.id=oi.order_id group by 1,2),
 costs as (select pri.product_id,pri.size_name,sum(pri.quantity*ii.unit_cost) cost from product_recipe_items pri join inventory_items ii on ii.id=pri.inventory_item_id group by 1,2)
 select jsonb_build_object(
  'sales_today',coalesce((select sum(total) from valid_orders where created_at>=date_trunc('day',now() at time zone 'America/Mexico_City') at time zone 'America/Mexico_City'),0),
  'sales_week',coalesce((select sum(total) from valid_orders where created_at>=date_trunc('week',now() at time zone 'America/Mexico_City') at time zone 'America/Mexico_City'),0),
  'strong_day',coalesce((select day from day_sales order by sales desc limit 1),0),'weak_day',coalesce((select day from day_sales order by sales limit 1),0),
  'strong_hour',coalesce((select hour from hour_sales order by sales desc limit 1),0),'weak_hour',coalesce((select hour from hour_sales order by sales limit 1),0),
  'top_product',coalesce((select product_name from product_sales order by qty desc limit 1),'Sin ventas'),
  'best_margin_product',coalesce((select p.name from products p join product_sizes ps on ps.product_id=p.id left join costs c on c.product_id=p.id and c.size_name=ps.name where ps.active order by (ps.price-coalesce(c.cost,0))/nullif(ps.price,0) desc limit 1),'Sin costos configurados'),
  'active_promotions',(select count(*) from promotions where status='active' and now() between starts_at and ends_at),
  'suggested_promotions',(select count(*) from promotions where status='suggested'),
  'recover_customers',(select count(*) from (select customer_id,max(created_at) last_order from valid_orders group by customer_id having now()-max(created_at)>interval '14 days') q)
 ) into result;
 return result;
end $$;
revoke all on function public.admin_smart_summary() from public,anon;
grant execute on function public.admin_smart_summary() to authenticated;

create or replace function public.admin_refresh_smart_promotions()
returns integer language plpgsql security invoker set search_path='public','private' as $$
declare v_count integer:=0; v_product record; v_hour integer; v_normal numeric; v_cost numeric; v_promo numeric;
begin
 if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 update promotions set status='expired',updated_at=now() where status='active' and ends_at<now();
 if exists(select 1 from promotions where source='smart' and generated_at>now()-interval '1 hour')
   or coalesce((select max(created_at) from orders),'-infinity'::timestamptz)
      <= coalesce((select max(generated_at) from promotions where source='smart'),'-infinity'::timestamptz) then
   return 0;
 end if;
 select oi.product_id,oi.product_name,sum(oi.quantity) qty into v_product from order_items oi join orders o on o.id=oi.order_id
  where o.status<>'cancelled' group by 1,2 order by qty asc limit 1;
 select extract(hour from o.created_at at time zone 'America/Mexico_City')::int into v_hour from orders o where o.status<>'cancelled'
  group by 1 order by sum(o.total) asc limit 1;
 if v_product.product_id is not null then
   select ps.price,coalesce(sum(pri.quantity*ii.unit_cost),0) into v_normal,v_cost from product_sizes ps
    left join product_recipe_items pri on pri.product_id=ps.product_id and pri.size_name=ps.name
    left join inventory_items ii on ii.id=pri.inventory_item_id
   where ps.product_id=v_product.product_id and ps.active group by ps.price,ps.name order by ps.price limit 1;
   if coalesce(v_cost,0)<=0 then return 0; end if;
   v_promo:=round(v_normal*.9,0);
   insert into promotions(title,description,promotion_type,status,starts_at,ends_at,start_time,end_time,product_ids,discount_percent,
    normal_price,estimated_cost,normal_margin_percent,promo_margin_percent,estimated_profit,additional_sales_needed,rationale,source,generated_at)
   values('Impulso para '||v_product.product_name,'10% de descuento en el horario con menor venta.','percent_discount','suggested',
    now(),now()+interval '7 days',make_time(coalesce(v_hour,18),0,0),make_time((coalesce(v_hour,18)+2)%24,0,0),array[v_product.product_id],10,
    v_normal,v_cost,round((v_normal-v_cost)*100/nullif(v_normal,0),1),round((v_promo-v_cost)*100/nullif(v_promo,0),1),v_promo-v_cost,
    ceil((v_normal-v_cost)/nullif(v_promo-v_cost,0)),format('Este producto tiene menor rotación; el horario %s:00 presenta ventas más bajas.',coalesce(v_hour,18)),'smart',now());
   v_count:=1;
 end if;
 return v_count;
end $$;
revoke all on function public.admin_refresh_smart_promotions() from public,anon;
grant execute on function public.admin_refresh_smart_promotions() to authenticated;

do $$ begin
 alter publication supabase_realtime add table public.promotions;
exception when duplicate_object then null; end $$;
