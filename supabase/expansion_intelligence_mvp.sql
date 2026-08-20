begin;

create table if not exists public.branches(
  id text primary key,
  name text not null,
  branch_type text not null default 'main' check(branch_type in('main','branch','pickup_point','dark_kitchen')),
  status text not null default 'active' check(status in('planned','testing','active','paused','closed')),
  latitude numeric not null check(latitude between -90 and 90),
  longitude numeric not null check(longitude between -180 and 180),
  service_radius_km numeric not null default 6 check(service_radius_km>0),
  opened_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create table if not exists public.expansion_config(
  id text primary key default 'main',
  analysis_days integer not null default 90 check(analysis_days between 30 and 730),
  cell_size_km numeric not null default 0.75 check(cell_size_km between .25 and 5),
  minimum_orders integer not null default 30 check(minimum_orders between 5 and 10000),
  demand_weight numeric not null default 25 check(demand_weight>=0),
  density_weight numeric not null default 15 check(density_weight>=0),
  repeat_weight numeric not null default 15 check(repeat_weight>=0),
  ticket_weight numeric not null default 10 check(ticket_weight>=0),
  delivery_saving_weight numeric not null default 20 check(delivery_saving_weight>=0),
  growth_weight numeric not null default 15 check(growth_weight>=0),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

insert into public.expansion_config(id) values('main') on conflict(id) do nothing;
insert into public.branches(id,name,branch_type,status,latitude,longitude,service_radius_km)
select 'main','Fresas con Crema Cande','main','active',store_latitude,store_longitude,max_distance_km
from public.delivery_rate_settings where id='main' and store_latitude is not null and store_longitude is not null
on conflict(id) do nothing;

alter table public.branches enable row level security;
alter table public.expansion_config enable row level security;
drop policy if exists admin_branches_all on public.branches;
create policy admin_branches_all on public.branches for all to authenticated using(private.is_admin()) with check(private.is_admin());
drop policy if exists admin_expansion_config_all on public.expansion_config;
create policy admin_expansion_config_all on public.expansion_config for all to authenticated using(private.is_admin()) with check(private.is_admin());
grant select,insert,update,delete on public.branches,public.expansion_config to authenticated;

create index if not exists branches_status_idx on public.branches(status);
create index if not exists branches_updated_by_idx on public.branches(updated_by);
create index if not exists expansion_config_updated_by_idx on public.expansion_config(updated_by);

create or replace function public.admin_expansion_dashboard(p_days integer default null,p_cell_km numeric default null)
returns jsonb language plpgsql security invoker set search_path=''
as $$
declare v_config public.expansion_config;v_days integer;v_cell numeric;v_total integer;v_coordinates integer;v_distance integer;v_costed integer;v_zones jsonb;
begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED';end if;
  select * into v_config from public.expansion_config where id='main';
  v_days:=greatest(30,least(730,coalesce(p_days,v_config.analysis_days)));
  v_cell:=greatest(.25,least(5,coalesce(p_cell_km,v_config.cell_size_km)));
  select count(*) filter(where delivery_type='delivery'),count(*) filter(where delivery_type='delivery' and nullif(address#>>'{coordinates,latitude}','') is not null and nullif(address#>>'{coordinates,longitude}','') is not null),count(*) filter(where delivery_type='delivery' and delivery_distance_km is not null),count(*) filter(where delivery_type='delivery' and driver_pay>0)
  into v_total,v_coordinates,v_distance,v_costed from public.orders where created_at>=now()-make_interval(days=>v_days);
  with raw as(
    select o.*, (o.address#>>'{coordinates,latitude}')::numeric lat,(o.address#>>'{coordinates,longitude}')::numeric lng
    from public.orders o where o.delivery_type='delivery' and o.created_at>=now()-make_interval(days=>v_days)
      and nullif(o.address#>>'{coordinates,latitude}','') is not null and nullif(o.address#>>'{coordinates,longitude}','') is not null
  ), bucketed as(
    select r.*,round(lat/(v_cell/111.0))*(v_cell/111.0) zone_lat,round(lng/(v_cell/105.0))*(v_cell/105.0) zone_lng from raw r
  ), customer_zone as(
    select zone_lat,zone_lng,customer_id,count(*) filter(where status='delivered') delivered_count from bucketed group by zone_lat,zone_lng,customer_id
  ), favorite as(
    select b.zone_lat,b.zone_lng,oi.product_name,sum(oi.quantity) quantity,row_number() over(partition by b.zone_lat,b.zone_lng order by sum(oi.quantity) desc,oi.product_name) position
    from bucketed b join public.order_items oi on oi.order_id=b.id group by b.zone_lat,b.zone_lng,oi.product_name
  ), aggregate as(
    select b.zone_lat,b.zone_lng,count(*) orders_total,count(*) filter(where b.status='delivered') orders_completed,count(*) filter(where b.status='cancelled') orders_cancelled,
      count(distinct b.customer_id) customers,count(distinct b.customer_id) filter(where cz.delivered_count>1) repeat_customers,
      coalesce(sum(b.total) filter(where b.status='delivered'),0) sales,coalesce(avg(b.total) filter(where b.status='delivered'),0) avg_ticket,
      coalesce(avg(b.delivery_fee) filter(where b.status='delivered'),0) avg_delivery_fee,avg(b.driver_pay) filter(where b.status='delivered' and b.driver_pay>0) avg_driver_pay,
      avg(b.delivery_distance_km) filter(where b.status='delivered') avg_distance,
      count(*) filter(where b.status='delivered' and b.created_at>=now()-make_interval(days=>v_days/2)) current_orders,
      count(*) filter(where b.status='delivered' and b.created_at<now()-make_interval(days=>v_days/2)) previous_orders
    from bucketed b join customer_zone cz on cz.zone_lat=b.zone_lat and cz.zone_lng=b.zone_lng and cz.customer_id=b.customer_id group by b.zone_lat,b.zone_lng
  ), scored as(
    select a.*,f.product_name favorite_product,
      case when previous_orders=0 then null else round(100.0*(current_orders-previous_orders)/previous_orders,1) end growth_percent,
      round(100.0*orders_completed/nullif(max(orders_completed) over(),0),1) demand_score,
      round(100.0*customers/nullif(max(customers) over(),0),1) density_score,
      round(100.0*repeat_customers/nullif(customers,0),1) repeat_score,
      round(100.0*avg_ticket/nullif(max(avg_ticket) over(),0),1) ticket_score,
      round(100.0*avg_delivery_fee/nullif(max(avg_delivery_fee) over(),0),1) delivery_saving_score,
      round(least(100,greatest(0,50+coalesce(case when previous_orders=0 then 0 else 100.0*(current_orders-previous_orders)/previous_orders end,0))),1) growth_score
    from aggregate a left join favorite f on f.zone_lat=a.zone_lat and f.zone_lng=a.zone_lng and f.position=1
  ), final as(
    select s.*,round((demand_score*v_config.demand_weight+density_score*v_config.density_weight+repeat_score*v_config.repeat_weight+ticket_score*v_config.ticket_weight+delivery_saving_score*v_config.delivery_saving_weight+growth_score*v_config.growth_weight)/nullif(v_config.demand_weight+v_config.density_weight+v_config.repeat_weight+v_config.ticket_weight+v_config.delivery_saving_weight+v_config.growth_weight,0),1) branch_score
    from scored s
  ) select coalesce(jsonb_agg(jsonb_build_object(
      'id',concat(round(zone_lat,4),',',round(zone_lng,4)),'latitude',round(zone_lat,6),'longitude',round(zone_lng,6),'orders',orders_total,'completedOrders',orders_completed,'cancelledOrders',orders_cancelled,'customers',customers,'repeatCustomers',repeat_customers,
      'sales',round(sales,2),'averageTicket',round(avg_ticket,2),'averageDeliveryFee',round(avg_delivery_fee,2),'averageDriverPay',round(avg_driver_pay,2),'averageDistanceKm',round(avg_distance,2),'favoriteProduct',favorite_product,'growthPercent',growth_percent,
      'branchScore',branch_score,'confidence',least(100,round(100.0*orders_completed/v_config.minimum_orders,0)),
      'classification',case when v_coordinates<v_config.minimum_orders or orders_completed<greatest(3,v_config.minimum_orders/4) then 'insufficient_data' when branch_score>=85 then 'priority' when branch_score>=70 then 'good' when branch_score>=50 then 'investigate' else 'not_recommended' end,
      'evidence',jsonb_build_array(format('%s pedidos completados',orders_completed),format('%s clientes únicos',customers),format('%s clientes recurrentes',repeat_customers),format('Ticket promedio $%s',round(avg_ticket,0))),
      'missingData',jsonb_build_array('Renta comercial','Competencia verificable','Accesibilidad del local','Costos completos por receta')
    ) order by branch_score desc),'[]'::jsonb) into v_zones from final;
  return jsonb_build_object(
    'readiness',jsonb_build_object('analysisDays',v_days,'deliveryOrders',v_total,'ordersWithCoordinates',v_coordinates,'ordersWithDistance',v_distance,'ordersWithDriverCost',v_costed,'minimumOrders',v_config.minimum_orders,'sufficientData',v_coordinates>=v_config.minimum_orders,'costDataComplete',false),
    'zones',v_zones,'branches',(select coalesce(jsonb_agg(to_jsonb(b) order by b.created_at),'[]'::jsonb) from public.branches b where b.status<>'closed'),'config',to_jsonb(v_config),
    'disclaimer','Estimaciones basadas en historial interno. No constituyen garantía de rentabilidad.'
  );
end $$;

create or replace function public.admin_save_expansion_config(p_config jsonb)
returns public.expansion_config language plpgsql security invoker set search_path=''
as $$declare v public.expansion_config;begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED';end if;
  update public.expansion_config set analysis_days=greatest(30,least(730,(p_config->>'analysis_days')::integer)),cell_size_km=greatest(.25,least(5,(p_config->>'cell_size_km')::numeric)),minimum_orders=greatest(5,(p_config->>'minimum_orders')::integer),demand_weight=greatest(0,(p_config->>'demand_weight')::numeric),density_weight=greatest(0,(p_config->>'density_weight')::numeric),repeat_weight=greatest(0,(p_config->>'repeat_weight')::numeric),ticket_weight=greatest(0,(p_config->>'ticket_weight')::numeric),delivery_saving_weight=greatest(0,(p_config->>'delivery_saving_weight')::numeric),growth_weight=greatest(0,(p_config->>'growth_weight')::numeric),updated_at=now(),updated_by=auth.uid() where id='main' returning * into v;return v;
end $$;

revoke all on function public.admin_expansion_dashboard(integer,numeric),public.admin_save_expansion_config(jsonb) from public,anon;
grant execute on function public.admin_expansion_dashboard(integer,numeric),public.admin_save_expansion_config(jsonb) to authenticated;

commit;
