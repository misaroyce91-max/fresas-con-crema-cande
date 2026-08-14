create table if not exists public.delivery_rate_settings (
 id text primary key default 'main', enabled boolean not null default false,
 store_latitude numeric(10,7), store_longitude numeric(10,7), route_factor numeric(6,3) not null default 1.20,
 max_distance_km numeric(8,2) not null default 6, additional_fee_per_km numeric(10,2) not null default 12,
 driver_min_pay numeric(10,2) not null default 25, driver_base_pay numeric(10,2) not null default 20,
 driver_additional_per_km numeric(10,2) not null default 3,
 free_shipping_enabled boolean not null default false, free_shipping_min_order numeric(10,2) not null default 0,
 free_shipping_max_km numeric(8,2) not null default 0, updated_at timestamptz not null default now(),
 check(store_latitude between -90 and 90),check(store_longitude between -180 and 180),check(route_factor>=1),check(max_distance_km>0)
);
create table if not exists public.delivery_rate_tiers (
 id uuid primary key default gen_random_uuid(),max_km numeric(8,2) not null unique check(max_km>0),fee numeric(10,2) not null check(fee>=0),sort_order integer not null default 0
);
insert into public.delivery_rate_settings(id) values('main') on conflict(id) do nothing;
insert into public.delivery_rate_tiers(max_km,fee,sort_order) values(2,30,1),(3,35,2),(4,40,3),(5,50,4),(6,60,5) on conflict(max_km) do nothing;
alter table public.delivery_rate_settings enable row level security;
alter table public.delivery_rate_tiers enable row level security;
create policy delivery_settings_read on public.delivery_rate_settings for select to anon,authenticated using(true);
create policy delivery_tiers_read on public.delivery_rate_tiers for select to anon,authenticated using(true);
create policy delivery_settings_admin on public.delivery_rate_settings for all to authenticated using(private.is_admin()) with check(private.is_admin());
create policy delivery_tiers_admin on public.delivery_rate_tiers for all to authenticated using(private.is_admin()) with check(private.is_admin());
grant select on public.delivery_rate_settings,public.delivery_rate_tiers to anon,authenticated;
grant insert,update,delete on public.delivery_rate_settings,public.delivery_rate_tiers to authenticated;

alter table public.orders add column if not exists delivery_distance_km numeric(8,2);
alter table public.orders add column if not exists driver_pay numeric(10,2) not null default 0;
alter table public.orders add column if not exists delivery_business_share numeric(10,2) not null default 0;
alter table public.orders add column if not exists delivery_rate_snapshot jsonb;

create or replace function private.calculate_delivery_quote(p_lat numeric,p_lng numeric,p_subtotal numeric)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s public.delivery_rate_settings;t public.delivery_rate_tiers;v_straight numeric;v_distance numeric;v_fee numeric;v_pay numeric;v_free boolean:=false;
begin
 select * into s from public.delivery_rate_settings where id='main';
 if not s.enabled then return jsonb_build_object('configured',false,'serviceable',true,'fee',(select shipping_fee from public.store_settings where id='main'),'driverPay',0,'businessShare',(select shipping_fee from public.store_settings where id='main'),'method','fixed_fallback'); end if;
 if s.store_latitude is null or s.store_longitude is null then return jsonb_build_object('configured',false,'serviceable',false,'reason','STORE_LOCATION_REQUIRED'); end if;
 if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then return jsonb_build_object('configured',true,'serviceable',false,'reason','DELIVERY_COORDINATES_REQUIRED'); end if;
 v_straight:=6371*2*asin(sqrt(power(sin(radians((p_lat-s.store_latitude)/2)),2)+cos(radians(s.store_latitude))*cos(radians(p_lat))*power(sin(radians((p_lng-s.store_longitude)/2)),2)));
 v_distance:=round(v_straight*s.route_factor,2);
 if v_distance>s.max_distance_km then return jsonb_build_object('configured',true,'serviceable',false,'reason','OUTSIDE_DELIVERY_AREA','distanceKm',v_distance,'maxDistanceKm',s.max_distance_km); end if;
 select * into t from public.delivery_rate_tiers where max_km>=v_distance order by max_km limit 1;
 if found then v_fee:=t.fee; else select * into t from public.delivery_rate_tiers order by max_km desc limit 1;v_fee:=t.fee+greatest(0,v_distance-t.max_km)*s.additional_fee_per_km;end if;
 v_free:=s.free_shipping_enabled and p_subtotal>=s.free_shipping_min_order and v_distance<=s.free_shipping_max_km;
 if v_free then v_fee:=0; end if;
 v_pay:=round(greatest(s.driver_min_pay,s.driver_base_pay+v_distance*s.driver_additional_per_km),2);
 return jsonb_build_object('configured',true,'serviceable',true,'distanceKm',v_distance,'straightLineKm',round(v_straight,2),'fee',round(v_fee,2),'driverPay',v_pay,'businessShare',round(v_fee-v_pay,2),'freeShipping',v_free,'method','haversine_route_factor','routeFactor',s.route_factor,'maxDistanceKm',s.max_distance_km);
end $$;
create or replace function public.quote_delivery(p_lat numeric,p_lng numeric,p_subtotal numeric default 0)
returns jsonb language sql stable security definer set search_path='' as $$select private.calculate_delivery_quote(p_lat,p_lng,greatest(coalesce(p_subtotal,0),0))$$;
revoke all on function public.quote_delivery(numeric,numeric,numeric) from public;
grant execute on function public.quote_delivery(numeric,numeric,numeric) to anon,authenticated;

create or replace function private.admin_save_delivery_rates_impl(p_settings jsonb,p_tiers jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 if jsonb_typeof(p_tiers)<>'array' or jsonb_array_length(p_tiers)=0 then raise exception 'DELIVERY_TIERS_REQUIRED'; end if;
 insert into public.delivery_rate_settings(id,enabled,store_latitude,store_longitude,route_factor,max_distance_km,additional_fee_per_km,driver_min_pay,driver_base_pay,driver_additional_per_km,free_shipping_enabled,free_shipping_min_order,free_shipping_max_km,updated_at)
 values('main',coalesce((p_settings->>'enabled')::boolean,false),nullif(p_settings->>'storeLatitude','')::numeric,nullif(p_settings->>'storeLongitude','')::numeric,greatest(1,(p_settings->>'routeFactor')::numeric),greatest(.1,(p_settings->>'maxDistanceKm')::numeric),greatest(0,(p_settings->>'additionalFeePerKm')::numeric),greatest(0,(p_settings->>'driverMinPay')::numeric),greatest(0,(p_settings->>'driverBasePay')::numeric),greatest(0,(p_settings->>'driverAdditionalPerKm')::numeric),coalesce((p_settings->>'freeShippingEnabled')::boolean,false),greatest(0,(p_settings->>'freeShippingMinOrder')::numeric),greatest(0,(p_settings->>'freeShippingMaxKm')::numeric),now())
 on conflict(id) do update set enabled=excluded.enabled,store_latitude=excluded.store_latitude,store_longitude=excluded.store_longitude,route_factor=excluded.route_factor,max_distance_km=excluded.max_distance_km,additional_fee_per_km=excluded.additional_fee_per_km,driver_min_pay=excluded.driver_min_pay,driver_base_pay=excluded.driver_base_pay,driver_additional_per_km=excluded.driver_additional_per_km,free_shipping_enabled=excluded.free_shipping_enabled,free_shipping_min_order=excluded.free_shipping_min_order,free_shipping_max_km=excluded.free_shipping_max_km,updated_at=now();
 delete from public.delivery_rate_tiers;
 insert into public.delivery_rate_tiers(max_km,fee,sort_order) select (x->>'maxKm')::numeric,(x->>'fee')::numeric,ordinality from jsonb_array_elements(p_tiers) with ordinality q(x,ordinality);
 return jsonb_build_object('saved',true);
end $$;
create or replace function public.admin_save_delivery_rates(p_settings jsonb,p_tiers jsonb) returns jsonb language sql security definer set search_path='' as $$select private.admin_save_delivery_rates_impl(p_settings,p_tiers)$$;
revoke all on function public.admin_save_delivery_rates(jsonb,jsonb) from public,anon;grant execute on function public.admin_save_delivery_rates(jsonb,jsonb) to authenticated;

do $migration$
declare d text;
begin
 select pg_get_functiondef('private.place_order_impl(uuid,jsonb,text,jsonb,text,text,text,uuid[])'::regprocedure) into d;
 if position('v_delivery_quote jsonb' in d)=0 then
  d:=replace(d,' v_rate numeric(10,4):=0;',' v_delivery_quote jsonb;v_rate numeric(10,4):=0;');
  d:=replace(d,' if p_delivery_type=''delivery'' then select shipping_fee into v_shipping from public.store_settings where id=''main''; end if;',
  ' if p_delivery_type=''delivery'' then v_delivery_quote:=private.calculate_delivery_quote((p_address#>>''{coordinates,latitude}'')::numeric,(p_address#>>''{coordinates,longitude}'')::numeric,v_subtotal); if not coalesce((v_delivery_quote->>''serviceable'')::boolean,false) then raise exception ''%'' ,coalesce(v_delivery_quote->>''reason'',''DELIVERY_NOT_AVAILABLE''); end if; v_shipping:=coalesce((v_delivery_quote->>''fee'')::numeric,0); else v_delivery_quote:=jsonb_build_object(''distanceKm'',null,''driverPay'',0,''businessShare'',0,''method'',''pickup''); end if;');
  d:=replace(d,'delivery_fee,discount,total,points_earned)','delivery_fee,discount,total,points_earned,delivery_distance_km,driver_pay,delivery_business_share,delivery_rate_snapshot)');
  d:=replace(d,'v_shipping,v_discount,greatest(0,v_subtotal+v_shipping-v_discount),0) returning','v_shipping,v_discount,greatest(0,v_subtotal+v_shipping-v_discount),0,nullif(v_delivery_quote->>''distanceKm'','''')::numeric,coalesce((v_delivery_quote->>''driverPay'')::numeric,0),coalesce((v_delivery_quote->>''businessShare'')::numeric,0),v_delivery_quote) returning');
  execute d;
 end if;
end $migration$;

create or replace function private.request_driver_impl(p_order_id uuid,p_pay numeric,p_pickup_address text)
returns public.delivery_requests language plpgsql security definer set search_path='' as $$declare v_order public.orders;v_request public.delivery_requests;begin
 if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found or v_order.delivery_type<>'delivery' or v_order.status<>'ready' then raise exception 'ORDER_NOT_READY_FOR_DELIVERY'; end if;
 insert into public.delivery_requests(order_id,pay,pickup_address) values(p_order_id,greatest(v_order.driver_pay,0),trim(p_pickup_address))
 on conflict(order_id) do update set status='requested',pay=excluded.pay,pickup_address=excluded.pickup_address,assigned_at=null,updated_at=now() where public.delivery_requests.status='cancelled' returning * into v_request;
 if v_request.id is null then select * into v_request from public.delivery_requests where order_id=p_order_id; end if;return v_request;
end $$;

drop function if exists public.driver_available_requests();
drop function if exists private.driver_available_requests_impl();
create function private.driver_available_requests_impl()
returns table(id uuid,order_id uuid,pay numeric,pickup_address text,status text,order_number bigint,delivery_address text,maps_url text,distance_km numeric,order_items jsonb)
language sql security definer set search_path='' as $$select r.id,r.order_id,r.pay,r.pickup_address,r.status,o.order_number,coalesce(o.address->>'address','Zona por confirmar'),o.address->>'mapsUrl',o.delivery_distance_km,coalesce((select jsonb_agg(jsonb_build_object('product_name',i.product_name,'size_name',i.size_name,'quantity',i.quantity) order by i.id) from public.order_items i where i.order_id=o.id),'[]'::jsonb) from public.delivery_requests r join public.orders o on o.id=r.order_id join public.couriers c on c.user_id=auth.uid() and c.active and c.status='available' where private.is_driver() and r.status='requested' and (select count(*) from public.delivery_assignments a where a.courier_id=c.id and a.status not in('delivered','cancelled'))<3 and not exists(select 1 from public.delivery_request_rejections x where x.request_id=r.id and x.courier_id=c.id) order by r.requested_at$$;
create function public.driver_available_requests() returns table(id uuid,order_id uuid,pay numeric,pickup_address text,status text,order_number bigint,delivery_address text,maps_url text,distance_km numeric,order_items jsonb) language sql security definer set search_path='' as $$select * from private.driver_available_requests_impl()$$;
revoke all on function public.driver_available_requests() from public,anon;grant execute on function public.driver_available_requests() to authenticated;
