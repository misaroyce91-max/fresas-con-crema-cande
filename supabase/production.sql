create extension if not exists pgcrypto;
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.customer_levels (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  min_lifetime_points integer not null default 0 check (min_lifetime_points >= 0),
  sort_order integer not null default 0
);

create table public.customers (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 2 and 80),
  phone text unique not null,
  points_balance integer not null default 0 check (points_balance >= 0),
  lifetime_points integer not null default 0 check (lifetime_points >= 0),
  level_id uuid references public.customer_levels(id),
  addresses jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.products (
  id text primary key,
  name text unique not null,
  description text not null default '',
  image_url text,
  active boolean not null default true,
  specialty boolean not null default false,
  featured boolean not null default false,
  favorite boolean not null default false,
  sort_order integer not null default 0
);

create table public.product_sizes (
  id uuid primary key default gen_random_uuid(),
  product_id text not null references public.products(id) on delete cascade,
  name text not null,
  ounces integer not null check (ounces > 0),
  price numeric(10,2) not null check (price >= 0),
  active boolean not null default true,
  unique (product_id, name)
);

create table public.toppings (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  price numeric(10,2) not null default 0 check (price >= 0),
  active boolean not null default true
);

create table public.point_rules (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  points_per_peso numeric(10,4) not null default 0.1 check (points_per_peso >= 0),
  multiplier numeric(6,2) not null default 1 check (multiplier > 0),
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true
);

create table public.rewards (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  points_cost integer not null check (points_cost > 0),
  reward_type text not null,
  reward_value numeric(10,2),
  active boolean not null default true,
  sort_order integer not null default 0
);

create table public.store_settings (
  id text primary key default 'main',
  shipping_fee numeric(10,2) not null default 35 check (shipping_fee >= 0),
  updated_at timestamptz not null default now()
);

create type public.order_status as enum ('pending','confirmed','preparing','ready','delivered','cancelled');

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number bigint generated always as identity unique,
  client_request_id uuid not null unique,
  customer_id uuid not null references public.customers(id),
  status public.order_status not null default 'pending',
  delivery_type text not null check (delivery_type in ('delivery','pickup')),
  address jsonb,
  references_text text,
  notes text,
  payment_method text not null check (payment_method in ('Efectivo','Transferencia / SPEI')),
  payment_status text not null default 'pending',
  subtotal numeric(10,2) not null check (subtotal >= 0),
  delivery_fee numeric(10,2) not null default 0 check (delivery_fee >= 0),
  discount numeric(10,2) not null default 0 check (discount >= 0),
  total numeric(10,2) not null check (total >= 0),
  points_earned integer not null default 0 check (points_earned >= 0),
  created_at timestamptz not null default now(),
  delivered_at timestamptz
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id text not null references public.products(id),
  product_name text not null,
  size_name text not null,
  unit_price numeric(10,2) not null check (unit_price >= 0),
  quantity integer not null check (quantity between 1 and 50),
  toppings jsonb not null default '[]'::jsonb,
  line_total numeric(10,2) not null check (line_total >= 0)
);

create table public.points_transactions (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  order_id uuid references public.orders(id),
  type text not null check (type in ('earn','redeem','adjustment','expiration')),
  points integer not null,
  balance_after integer not null check (balance_after >= 0),
  description text,
  created_at timestamptz not null default now(),
  unique (order_id, type)
);

create table public.reward_redemptions (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  reward_id uuid not null references public.rewards(id),
  points_spent integer not null check (points_spent > 0),
  status text not null default 'available' check (status in ('available','used','cancelled')),
  redeemed_at timestamptz not null default now(),
  used_at timestamptz
);

create table public.couriers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete cascade,
  name text not null,
  phone text unique not null,
  status text not null default 'unavailable' check (status in ('available','busy','unavailable')),
  fee_per_delivery numeric(10,2) not null default 0,
  active boolean not null default true,
  last_activity_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.delivery_assignments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid unique not null references public.orders(id),
  courier_id uuid not null references public.couriers(id),
  status text not null default 'accepted' check (status in ('accepted','picked_up','delivering','delivered','cancelled')),
  delivery_fee numeric(10,2) not null default 0,
  accepted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index orders_customer_created_idx on public.orders(customer_id, created_at desc);
create index orders_status_created_idx on public.orders(status, created_at desc);
create index order_items_order_idx on public.order_items(order_id);
create index points_customer_created_idx on public.points_transactions(customer_id, created_at desc);
create index redemptions_customer_created_idx on public.reward_redemptions(customer_id, redeemed_at desc);
create index assignments_courier_status_idx on public.delivery_assignments(courier_id, status);

create or replace function private.is_admin()
returns boolean language sql stable security invoker set search_path = ''
as $$ select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'ADMIN', false) $$;

create or replace function private.is_driver()
returns boolean language sql stable security invoker set search_path = ''
as $$ select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'DRIVER', false) $$;

create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_level uuid;
begin
  select id into v_level from public.customer_levels order by min_lifetime_points limit 1;
  if coalesce(new.raw_app_meta_data ->> 'role', 'CUSTOMER') = 'CUSTOMER' then
    insert into public.customers(id, name, phone, level_id)
    values (
      new.id,
      trim(coalesce(new.raw_user_meta_data ->> 'name', 'Cliente Cande')),
      regexp_replace(coalesce(new.phone, new.raw_user_meta_data ->> 'phone', ''), '[^0-9+]', '', 'g'),
      v_level
    );
  end if;
  return new;
end $$;

create trigger on_auth_user_created
after insert on auth.users for each row execute function private.handle_new_user();

create or replace function private.place_order_impl(
  p_client_request_id uuid,
  p_items jsonb,
  p_delivery_type text,
  p_address jsonb,
  p_references text,
  p_notes text,
  p_payment_method text
) returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_customer public.customers;
  v_existing public.orders;
  v_order public.orders;
  v_item jsonb;
  v_product public.products;
  v_size public.product_sizes;
  v_topping jsonb;
  v_toppings jsonb;
  v_topping_total numeric(10,2);
  v_subtotal numeric(10,2) := 0;
  v_shipping numeric(10,2) := 0;
  v_line numeric(10,2);
  v_quantity integer;
  v_rate numeric(10,4) := 0;
  v_multiplier numeric(6,2) := 1;
  v_points integer := 0;
  v_balance integer;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_client_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if p_delivery_type not in ('delivery','pickup') then raise exception 'INVALID_DELIVERY_TYPE'; end if;
  if p_payment_method not in ('Efectivo','Transferencia / SPEI') then raise exception 'INVALID_PAYMENT_METHOD'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'EMPTY_ORDER'; end if;

  select * into v_customer from public.customers where id = v_user for update;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;

  select * into v_existing from public.orders where client_request_id = p_client_request_id;
  if found then
    if v_existing.customer_id <> v_user then raise exception 'REQUEST_ID_CONFLICT'; end if;
    return jsonb_build_object('id',v_existing.id,'orderNumber',v_existing.order_number,'total',v_existing.total,'pointsEarned',v_existing.points_earned,'duplicate',true);
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_quantity := greatest(1, least(50, coalesce((v_item ->> 'quantity')::integer, 1)));
    select * into v_product from public.products where id = v_item ->> 'productId' and active;
    if not found then raise exception 'PRODUCT_NOT_AVAILABLE'; end if;
    select * into v_size from public.product_sizes where product_id = v_product.id and name = v_item ->> 'size' and active;
    if not found then raise exception 'SIZE_NOT_AVAILABLE'; end if;
    select coalesce(jsonb_agg(jsonb_build_object('name',t.name,'price',t.price) order by t.name),'[]'::jsonb), coalesce(sum(t.price),0)
      into v_toppings, v_topping_total
      from public.toppings t
      where t.active and t.name in (select jsonb_array_elements_text(coalesce(v_item -> 'toppingNames','[]'::jsonb)));
    v_line := (v_size.price + v_topping_total) * v_quantity;
    v_subtotal := v_subtotal + v_line;
  end loop;

  if p_delivery_type = 'delivery' then
    select shipping_fee into v_shipping from public.store_settings where id = 'main';
  end if;
  select points_per_peso, multiplier into v_rate, v_multiplier
    from public.point_rules
    where active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at >= now())
    order by multiplier desc, points_per_peso desc limit 1;
  v_points := floor(v_subtotal * coalesce(v_rate,0) * coalesce(v_multiplier,1));

  insert into public.orders(client_request_id,customer_id,delivery_type,address,references_text,notes,payment_method,subtotal,delivery_fee,total,points_earned)
  values(p_client_request_id,v_user,p_delivery_type,p_address,nullif(trim(p_references),''),nullif(trim(p_notes),''),p_payment_method,v_subtotal,v_shipping,v_subtotal+v_shipping,v_points)
  returning * into v_order;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_quantity := greatest(1, least(50, coalesce((v_item ->> 'quantity')::integer, 1)));
    select * into v_product from public.products where id = v_item ->> 'productId' and active;
    select * into v_size from public.product_sizes where product_id = v_product.id and name = v_item ->> 'size' and active;
    select coalesce(jsonb_agg(jsonb_build_object('name',t.name,'price',t.price) order by t.name),'[]'::jsonb), coalesce(sum(t.price),0)
      into v_toppings, v_topping_total from public.toppings t
      where t.active and t.name in (select jsonb_array_elements_text(coalesce(v_item -> 'toppingNames','[]'::jsonb)));
    v_line := (v_size.price + v_topping_total) * v_quantity;
    insert into public.order_items(order_id,product_id,product_name,size_name,unit_price,quantity,toppings,line_total)
    values(v_order.id,v_product.id,v_product.name,v_size.name,v_size.price+v_topping_total,v_quantity,v_toppings,v_line);
  end loop;

  update public.customers set points_balance=points_balance+v_points,lifetime_points=lifetime_points+v_points,updated_at=now()
    where id=v_user returning points_balance into v_balance;
  insert into public.points_transactions(customer_id,order_id,type,points,balance_after,description)
    values(v_user,v_order.id,'earn',v_points,v_balance,'Puntos por pedido CAN-'||lpad(v_order.order_number::text,6,'0'));

  return jsonb_build_object('id',v_order.id,'orderNumber',v_order.order_number,'subtotal',v_order.subtotal,'deliveryFee',v_order.delivery_fee,'total',v_order.total,'pointsEarned',v_points,'balance',v_balance,'duplicate',false);
end $$;

create or replace function public.place_order(
  p_client_request_id uuid,
  p_items jsonb,
  p_delivery_type text,
  p_address jsonb,
  p_references text,
  p_notes text,
  p_payment_method text
) returns jsonb language sql security invoker set search_path = ''
as $$ select private.place_order_impl(p_client_request_id,p_items,p_delivery_type,p_address,p_references,p_notes,p_payment_method) $$;

create or replace function private.redeem_reward_impl(p_reward_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_customer public.customers; v_reward public.rewards; v_redemption public.reward_redemptions;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_customer from public.customers where id=v_user for update;
  select * into v_reward from public.rewards where id=p_reward_id and active;
  if not found then raise exception 'REWARD_NOT_AVAILABLE'; end if;
  if v_customer.points_balance < v_reward.points_cost then raise exception 'INSUFFICIENT_POINTS'; end if;
  update public.customers set points_balance=points_balance-v_reward.points_cost,updated_at=now() where id=v_user;
  insert into public.reward_redemptions(customer_id,reward_id,points_spent) values(v_user,v_reward.id,v_reward.points_cost) returning * into v_redemption;
  insert into public.points_transactions(customer_id,type,points,balance_after,description)
    values(v_user,'redeem',-v_reward.points_cost,v_customer.points_balance-v_reward.points_cost,'Canje: '||v_reward.name);
  return jsonb_build_object('id',v_redemption.id,'reward',v_reward.name,'balance',v_customer.points_balance-v_reward.points_cost);
end $$;

create or replace function public.redeem_reward(p_reward_id uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.redeem_reward_impl(p_reward_id) $$;

alter table public.customer_levels enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.product_sizes enable row level security;
alter table public.toppings enable row level security;
alter table public.point_rules enable row level security;
alter table public.rewards enable row level security;
alter table public.store_settings enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.points_transactions enable row level security;
alter table public.reward_redemptions enable row level security;
alter table public.couriers enable row level security;
alter table public.delivery_assignments enable row level security;

create policy catalog_levels_read on public.customer_levels for select to anon,authenticated using (true);
create policy catalog_products_read on public.products for select to anon,authenticated using (active);
create policy catalog_sizes_read on public.product_sizes for select to anon,authenticated using (active);
create policy catalog_toppings_read on public.toppings for select to anon,authenticated using (active);
create policy catalog_rewards_read on public.rewards for select to anon,authenticated using (active);
create policy settings_read on public.store_settings for select to anon,authenticated using (true);
create policy customers_read_own on public.customers for select to authenticated using ((select auth.uid())=id);
create policy orders_read_own on public.orders for select to authenticated using ((select auth.uid())=customer_id);
create policy order_items_read_own on public.order_items for select to authenticated using (exists(select 1 from public.orders o where o.id=order_id and o.customer_id=(select auth.uid())));
create policy points_read_own on public.points_transactions for select to authenticated using ((select auth.uid())=customer_id);
create policy redemptions_read_own on public.reward_redemptions for select to authenticated using ((select auth.uid())=customer_id);
create policy couriers_read_own on public.couriers for select to authenticated using ((select auth.uid())=user_id or private.is_admin());
create policy assignments_driver_read on public.delivery_assignments for select to authenticated using (courier_id=(select id from public.couriers where user_id=(select auth.uid())) or private.is_admin());
create policy admin_customers_all on public.customers for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy admin_orders_all on public.orders for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy admin_items_all on public.order_items for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy admin_points_all on public.points_transactions for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy admin_products_all on public.products for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy admin_sizes_all on public.product_sizes for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy admin_toppings_all on public.toppings for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy admin_rewards_all on public.rewards for all to authenticated using (private.is_admin()) with check (private.is_admin());
create policy admin_settings_all on public.store_settings for all to authenticated using (private.is_admin()) with check (private.is_admin());

revoke all on all tables in schema public from anon, authenticated;
grant select on public.customer_levels,public.products,public.product_sizes,public.toppings,public.rewards,public.store_settings to anon,authenticated;
grant select on public.customers,public.orders,public.order_items,public.points_transactions,public.reward_redemptions,public.couriers,public.delivery_assignments to authenticated;
grant select,insert,update,delete on public.products,public.product_sizes,public.toppings,public.rewards,public.store_settings to authenticated;
grant insert,update,delete on public.customers,public.orders,public.order_items,public.points_transactions,public.reward_redemptions,public.couriers,public.delivery_assignments to authenticated;
revoke all on function public.place_order(uuid,jsonb,text,jsonb,text,text,text) from public,anon;
revoke all on function public.redeem_reward(uuid) from public,anon;
revoke all on function private.place_order_impl(uuid,jsonb,text,jsonb,text,text,text) from public,anon;
revoke all on function private.redeem_reward_impl(uuid) from public,anon;
grant execute on function public.place_order(uuid,jsonb,text,jsonb,text,text,text) to authenticated;
grant execute on function public.redeem_reward(uuid) to authenticated;
grant execute on function private.place_order_impl(uuid,jsonb,text,jsonb,text,text,text) to authenticated;
grant execute on function private.redeem_reward_impl(uuid) to authenticated;
revoke execute on function public.rls_auto_enable() from public,anon,authenticated;

insert into public.customer_levels(name,min_lifetime_points,sort_order) values ('Fresa',0,1),('Gold',500,2),('VIP',1500,3);
insert into public.store_settings(id,shipping_fee) values ('main',35);
insert into public.point_rules(name,points_per_peso,multiplier,active) values ('Regla base',0.1,1,true);
insert into public.products(id,name,description,image_url,active,specialty,featured,favorite,sort_order) values
('classic','Clásicas','Fresas frescas, crema de la casa y un toque de amor Cande.','/images/cande-classic.png',true,true,true,true,1),
('oreo','Oreo','Crema suave, fresas y abundante galleta de chocolate.','/images/cande-oreo.png',true,true,true,true,2),
('kinder-bueno','Kinder Bueno','Fresas, crema, avellana y crujientes trozos de wafer.','/images/cande-special.png',true,true,true,true,3),
('kinder-delice','Kinder Delice','Chocolate, pastelito suave y nuestra crema artesanal.','/images/cande-special.png',true,false,true,false,4),
('nutella','Nutella','La combinación intensa de avellana, crema y fresa.','/images/cande-classic.png',true,false,false,false,5),
('ferrero','Ferrero','Un antojo premium con avellana, chocolate y textura crujiente.','/images/cande-special.png',true,false,false,false,6),
('carlos-v','Carlos V','Chocolate con leche en trocitos sobre fresas muy frescas.','/images/cande-oreo.png',true,false,false,false,7);
insert into public.product_sizes(product_id,name,ounces,price)
select p.id,s.name,s.oz,s.price from (values
('classic','10 oz',10,65),('classic','12 oz',12,75),('classic','14 oz',14,88),('classic','16 oz',16,99),
('oreo','10 oz',10,75),('oreo','12 oz',12,85),('oreo','14 oz',14,98),('oreo','16 oz',16,112),
('kinder-bueno','10 oz',10,82),('kinder-bueno','12 oz',12,94),('kinder-bueno','14 oz',14,108),('kinder-bueno','16 oz',16,122),
('kinder-delice','10 oz',10,82),('kinder-delice','12 oz',12,94),('kinder-delice','14 oz',14,108),('kinder-delice','16 oz',16,122),
('nutella','10 oz',10,80),('nutella','12 oz',12,92),('nutella','14 oz',14,105),('nutella','16 oz',16,119),
('ferrero','10 oz',10,88),('ferrero','12 oz',12,102),('ferrero','14 oz',14,116),('ferrero','16 oz',16,132),
('carlos-v','10 oz',10,78),('carlos-v','12 oz',12,89),('carlos-v','14 oz',14,102),('carlos-v','16 oz',16,116)
) as s(product_id,name,oz,price) join public.products p on p.id=s.product_id;
insert into public.toppings(name,price) values ('Chocoretas',12),('Chispas de chocolate',10),('Kranky',12),('Extra Kinder Bueno',18),('Nutella extra',15);
insert into public.rewards(name,description,points_cost,reward_type,reward_value,sort_order) values
('Topping gratis','Agrega un topping participante sin costo.',120,'free_topping',null,1),
('$20 de descuento','Descuento de $20 en una compra participante.',180,'fixed_discount',20,2),
('Fresa clásica 10 oz gratis','Una clásica de 10 oz sin costo.',300,'free_product',null,3),
('Fresa especial gratis','Una especial participante sin costo.',450,'free_product',null,4);
