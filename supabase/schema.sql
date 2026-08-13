-- Fresas con Crema Cande: esquema inicial para Supabase/Postgres
create extension if not exists "pgcrypto";

create table customer_levels (
  id uuid primary key default gen_random_uuid(), name text unique not null,
  min_lifetime_points integer not null default 0, benefits jsonb not null default '{}', sort_order integer not null default 0
);
create table customers (
  id uuid primary key references auth.users(id) on delete cascade, name text not null, phone text unique not null,
  points_balance integer not null default 0 check(points_balance >= 0), lifetime_points integer not null default 0,
  level_id uuid references customer_levels(id), addresses jsonb not null default '[]', home_branch_id uuid,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table products (
  id uuid primary key default gen_random_uuid(), name text not null, slug text unique not null, description text,
  image_url text, active boolean not null default true, sort_order integer not null default 0, created_at timestamptz default now()
);
create table product_sizes (
  id uuid primary key default gen_random_uuid(), product_id uuid not null references products(id), name text not null,
  ounces integer not null, price numeric(10,2) not null check(price >= 0), active boolean default true, unique(product_id,name)
);
create table toppings (
  id uuid primary key default gen_random_uuid(), name text unique not null, price numeric(10,2) not null default 0,
  active boolean default true, inventory_tracking boolean default false
);
create table promotions (
  id uuid primary key default gen_random_uuid(), name text not null, description text, type text not null,
  multiplier numeric(6,2), discount_value numeric(10,2), starts_at timestamptz, ends_at timestamptz,
  weekdays integer[], rules jsonb default '{}', active boolean default true
);
create table point_rules (
  id uuid primary key default gen_random_uuid(), name text not null, points_per_peso numeric(10,4) not null default 0.1,
  minimum_purchase numeric(10,2) default 0, multiplier numeric(6,2) default 1, starts_at timestamptz,
  ends_at timestamptz, conditions jsonb default '{}', active boolean default true, created_at timestamptz default now()
);
create table rewards (
  id uuid primary key default gen_random_uuid(), name text not null, description text, points_cost integer not null check(points_cost > 0),
  reward_type text not null, reward_value numeric(10,2), product_id uuid references products(id), active boolean default true,
  stock integer, rules jsonb default '{}', created_at timestamptz default now()
);
create type order_status as enum ('pending','confirmed','preparing','ready','delivered','cancelled');
create table orders (
  id uuid primary key default gen_random_uuid(), order_number bigint generated always as identity unique,
  customer_id uuid references customers(id), branch_id uuid, status order_status not null default 'pending', delivery_type text not null,
  address jsonb, references_text text, notes text, payment_method text not null, payment_status text default 'pending',
  subtotal numeric(10,2) not null, delivery_fee numeric(10,2) default 0, discount numeric(10,2) default 0,
  points_used integer default 0, total numeric(10,2) not null, points_earned integer default 0,
  promotion_id uuid references promotions(id), created_at timestamptz not null default now(), delivered_at timestamptz
);
create table order_items (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references orders(id), product_id uuid references products(id),
  product_name text not null, size_id uuid references product_sizes(id), size_name text not null,
  unit_price numeric(10,2) not null, quantity integer not null check(quantity > 0), toppings jsonb not null default '[]', line_total numeric(10,2) not null
);
create table points_transactions (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references customers(id), order_id uuid references orders(id),
  type text not null check(type in ('earn','redeem','adjustment','expiration')), points integer not null,
  balance_after integer not null, description text, rule_id uuid references point_rules(id), created_at timestamptz default now()
);
create table reward_redemptions (
  id uuid primary key default gen_random_uuid(), customer_id uuid not null references customers(id), reward_id uuid not null references rewards(id),
  order_id uuid references orders(id), points_spent integer not null, status text default 'available', redeemed_at timestamptz default now(), used_at timestamptz
);

create index orders_customer_date_idx on orders(customer_id, created_at desc);
create index orders_created_at_idx on orders(created_at desc);
create index points_customer_date_idx on points_transactions(customer_id, created_at desc);

alter table customers enable row level security; alter table orders enable row level security;
alter table order_items enable row level security; alter table points_transactions enable row level security;
alter table reward_redemptions enable row level security;
create policy "customers read own" on customers for select using(auth.uid()=id);
create policy "customers update own" on customers for update using(auth.uid()=id);
create policy "orders read own" on orders for select using(auth.uid()=customer_id);
create policy "order items read own" on order_items for select using(exists(select 1 from orders o where o.id=order_id and o.customer_id=auth.uid()));
create policy "points read own" on points_transactions for select using(auth.uid()=customer_id);
create policy "redemptions read own" on reward_redemptions for select using(auth.uid()=customer_id);

-- Las escrituras de pedidos y puntos deben pasar por una Edge Function/RPC con service role.
create or replace view weekly_business_stats as
select date_trunc('week', created_at) week_start, count(*) filter(where status <> 'cancelled') orders,
  coalesce(sum(total) filter(where status <> 'cancelled'),0) sales,
  coalesce(avg(total) filter(where status <> 'cancelled'),0) avg_ticket,
  count(distinct customer_id) filter(where status <> 'cancelled') unique_customers,
  coalesce(sum(points_earned),0) points_issued
from orders group by 1 order by 1 desc;

insert into customer_levels(name,min_lifetime_points,sort_order) values ('Fresa',0,1),('Gold',500,2),('VIP',1500,3);
insert into point_rules(name,points_per_peso,minimum_purchase,multiplier) values ('Regla base',0.1,0,1);
insert into rewards(name,points_cost,reward_type,reward_value) values
 ('Topping gratis',120,'free_topping',null),('$20 de descuento',180,'fixed_discount',20),
 ('Fresa clásica 10 oz gratis',300,'free_product',null),('Fresa especial gratis',450,'free_product',null);

-- Operación de reparto. Cada asignación conserva su historial aunque cambie el repartidor.
create table couriers (
  id uuid primary key default gen_random_uuid(), branch_id uuid, name text not null, phone text unique not null,
  status text not null default 'unavailable' check(status in ('available','busy','unavailable')),
  fee_per_delivery numeric(10,2) not null default 0, active boolean not null default true,
  last_activity_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table delivery_assignments (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references orders(id),
  courier_id uuid not null references couriers(id), status text not null default 'assigned'
    check(status in ('assigned','accepted','picked_up','delivering','delivered','cancelled')),
  delivery_fee numeric(10,2) not null default 0, assigned_at timestamptz not null default now(),
  accepted_at timestamptz, picked_up_at timestamptz, delivered_at timestamptz, cancelled_at timestamptz,
  notes text, unique(order_id)
);
create index delivery_assignments_courier_status_idx on delivery_assignments(courier_id,status);
create index delivery_assignments_assigned_at_idx on delivery_assignments(assigned_at desc);
create table delivery_requests (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references orders(id), branch_id uuid,
  pickup_address text not null, pickup_zone text not null, delivery_zone text not null,
  offered_fee numeric(10,2) not null, status text not null default 'open'
    check(status in ('open','accepted','cancelled','expired')),
  accepted_by uuid references couriers(id), requested_at timestamptz not null default now(),
  accepted_at timestamptz, expires_at timestamptz, unique(order_id)
);
create index delivery_requests_open_idx on delivery_requests(status,requested_at desc);

-- En producción, aceptar debe ejecutarse en una función transaccional con SELECT FOR UPDATE.
-- Solo la primera aceptación cambia open -> accepted y crea delivery_assignments.

-- Administración de tienda sin cambios de código.
alter table products add column if not exists specialty boolean not null default false;
alter table products add column if not exists featured boolean not null default false;
alter table products add column if not exists favorite boolean not null default false;
alter table promotions add column if not exists image_url text;
alter table promotions add column if not exists active boolean not null default true;
alter table promotions add column if not exists discount_percent numeric(6,2) default 0;
alter table promotions add column if not exists extra_points integer default 0;
alter table promotions add column if not exists double_points boolean default false;
alter table promotions add column if not exists free_shipping boolean default false;
alter table promotions add column if not exists combo_price numeric(10,2);
create table topping_products (
  topping_id uuid not null references toppings(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  primary key(topping_id,product_id)
);
create table store_settings (
  id text primary key default 'main', shipping_fee numeric(10,2) not null default 35,
  shipping_rules jsonb not null default '{"mode":"fixed"}', points_per_peso numeric(10,4) not null default .1,
  hero_title text, hero_description text, hero_image_url text, hero_button_text text,
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id)
);

alter table couriers add column if not exists user_id uuid unique references auth.users(id) on delete cascade;
create table push_subscriptions (
  id uuid primary key default gen_random_uuid(), courier_id uuid not null references couriers(id) on delete cascade,
  endpoint text not null unique, subscription jsonb not null, active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

alter table couriers enable row level security;
alter table delivery_requests enable row level security;
alter table delivery_assignments enable row level security;
alter table push_subscriptions enable row level security;
create policy "driver reads own courier" on couriers for select using(user_id=auth.uid());
create policy "driver updates own presence" on couriers for update using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "available driver reads open requests" on delivery_requests for select using(
  status='open' and exists(select 1 from couriers c where c.user_id=auth.uid() and c.status='available' and c.active)
  or accepted_by=(select id from couriers where user_id=auth.uid())
);
create policy "driver reads own assignments" on delivery_assignments for select using(
  courier_id=(select id from couriers where user_id=auth.uid())
);
create policy "driver updates own assignments" on delivery_assignments for update using(
  courier_id=(select id from couriers where user_id=auth.uid())
);
create policy "driver manages own push" on push_subscriptions for all using(
  courier_id=(select id from couriers where user_id=auth.uid())
) with check(courier_id=(select id from couriers where user_id=auth.uid()));

create or replace function accept_delivery_request(p_request_id uuid)
returns delivery_assignments
language plpgsql security definer set search_path=public
as $$
declare v_courier couriers; v_request delivery_requests; v_assignment delivery_assignments;
begin
  select * into v_courier from couriers where user_id=auth.uid() and status='available' and active for update;
  if not found then raise exception 'DRIVER_NOT_AVAILABLE'; end if;
  update delivery_requests set status='accepted',accepted_by=v_courier.id,accepted_at=now()
    where id=p_request_id and status='open' returning * into v_request;
  if not found then raise exception 'DELIVERY_ALREADY_TAKEN'; end if;
  insert into delivery_assignments(order_id,courier_id,status,delivery_fee,assigned_at,accepted_at)
    values(v_request.order_id,v_courier.id,'accepted',v_request.offered_fee,now(),now()) returning * into v_assignment;
  update couriers set status='busy',last_activity_at=now(),updated_at=now() where id=v_courier.id;
  return v_assignment;
end $$;
revoke all on function accept_delivery_request(uuid) from public;
grant execute on function accept_delivery_request(uuid) to authenticated;

-- El rol se asigna en auth.users.raw_app_meta_data: {"role":"DRIVER"}.
-- Las políticas de Admin deben comprobar role=ADMIN desde app_metadata, nunca desde datos editables por el usuario.
