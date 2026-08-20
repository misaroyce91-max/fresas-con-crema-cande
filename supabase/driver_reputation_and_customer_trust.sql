-- MVP: reputacion de repartidores, ofertas escalonadas y confianza operativa.
-- Los scores usan solo comportamiento verificable dentro de la plataforma.

begin;

create table if not exists public.driver_reputation_config (
  id text primary key default 'main',
  completion_weight numeric(5,2) not null default 35,
  acceptance_weight numeric(5,2) not null default 20,
  punctuality_weight numeric(5,2) not null default 20,
  consistency_weight numeric(5,2) not null default 15,
  quality_weight numeric(5,2) not null default 10,
  punctual_delivery_minutes integer not null default 60 check (punctual_delivery_minutes between 10 and 240),
  first_round_size integer not null default 1 check (first_round_size between 1 and 20),
  second_round_size integer not null default 2 check (second_round_size between 1 and 20),
  first_round_seconds integer not null default 20 check (first_round_seconds between 10 and 120),
  second_round_seconds integer not null default 20 check (second_round_seconds between 10 and 120),
  night_start_hour integer not null default 22 check (night_start_hour between 0 and 23),
  high_value_threshold numeric(10,2) not null default 500 check (high_value_threshold >= 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

insert into public.driver_reputation_config(id) values('main') on conflict(id) do nothing;

create table if not exists public.driver_rank_configs (
  id text primary key,
  name text unique not null,
  icon text not null,
  min_completed integer not null check(min_completed >= 0),
  min_score numeric(5,2) not null check(min_score between 0 and 100),
  priority_bonus numeric(8,2) not null default 0,
  benefits jsonb not null default '[]'::jsonb,
  active boolean not null default true,
  sort_order integer not null unique
);

insert into public.driver_rank_configs(id,name,icon,min_completed,min_score,priority_bonus,benefits,sort_order) values
 ('bronze','BRONCE','🥉',0,0,0,'["Acceso normal a viajes"]',1),
 ('silver','PLATA','🥈',15,70,5,'["Mayor prioridad","Acceso anticipado"]',2),
 ('gold','ORO','🥇',50,82,10,'["Prioridad preferente","Acceso a alta demanda"]',3),
 ('diamond','DIAMANTE','💎',100,92,16,'["Máxima prioridad","Incentivos especiales"]',4)
on conflict(id) do nothing;

create table if not exists public.driver_metrics (
  courier_id uuid primary key references public.couriers(id) on delete cascade,
  trips_offered integer not null default 0,
  trips_accepted integer not null default 0,
  trips_completed integer not null default 0,
  trips_cancelled integer not null default 0,
  completed_correctly integer not null default 0,
  incident_count integer not null default 0,
  acceptance_rate numeric(5,2) not null default 100,
  completion_rate numeric(5,2) not null default 100,
  punctuality_rate numeric(5,2) not null default 100,
  average_delivery_minutes numeric(10,2),
  active_days_30 integer not null default 0,
  trips_7_days integer not null default 0,
  trips_30_days integer not null default 0,
  last_delivery_at timestamptz,
  driver_score numeric(5,2) not null default 50 check(driver_score between 0 and 100),
  rank_id text not null default 'bronze' references public.driver_rank_configs(id),
  explanation jsonb not null default '[]'::jsonb,
  calculated_at timestamptz not null default now()
);

create table if not exists public.driver_offers (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.delivery_requests(id) on delete cascade,
  courier_id uuid not null references public.couriers(id) on delete cascade,
  round integer not null check(round between 1 and 3),
  dispatch_priority_score numeric(10,2) not null,
  status text not null default 'offered' check(status in ('offered','accepted','rejected','expired','cancelled')),
  offered_at timestamptz not null,
  push_sent_at timestamptz,
  responded_at timestamptz,
  expires_at timestamptz,
  excluded_from_acceptance_rate boolean not null default false,
  created_at timestamptz not null default now(),
  unique(request_id,courier_id)
);

create index if not exists driver_offers_courier_open_idx on public.driver_offers(courier_id,offered_at) where status='offered';
create index if not exists driver_offers_request_idx on public.driver_offers(request_id,round,status);

create table if not exists public.customer_trust_profiles (
  customer_id uuid primary key references public.customers(id) on delete cascade,
  orders_total integer not null default 0,
  orders_completed integer not null default 0,
  orders_cancelled integer not null default 0,
  successful_payments integer not null default 0,
  incident_count integer not null default 0,
  addresses_used integer not null default 0,
  trust_score numeric(5,2) not null default 50 check(trust_score between 0 and 100),
  trust_level text not null default 'new' check(trust_level in ('new','regular','trusted','vip')),
  last_completed_at timestamptz,
  explanation jsonb not null default '[]'::jsonb,
  calculated_at timestamptz not null default now()
);

create table if not exists public.delivery_incidents (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  assignment_id uuid references public.delivery_assignments(id),
  courier_id uuid not null references public.couriers(id),
  customer_id uuid references public.customers(id),
  category text not null check(category in ('customer_unresponsive','wrong_address','no_access','customer_rejected','payment_problem','feeling_unsafe','other')),
  details text,
  review_status text not null default 'pending' check(review_status in ('pending','reviewed','valid','dismissed')),
  affects_scores boolean not null default false,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_notes text
);

create index if not exists delivery_incidents_review_idx on public.delivery_incidents(review_status,created_at desc);
create index if not exists delivery_incidents_courier_idx on public.delivery_incidents(courier_id,created_at desc);
create index if not exists delivery_incidents_customer_idx on public.delivery_incidents(customer_id,created_at desc);

create table if not exists public.audit_events (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id),
  event_type text not null,
  entity_type text not null,
  entity_id text not null,
  reason text,
  old_value jsonb,
  new_value jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.delivery_requests
  add column if not exists safety_level text not null default 'standard' check(safety_level in ('standard','additional_precautions')),
  add column if not exists safety_signals jsonb not null default '[]'::jsonb,
  add column if not exists requires_confirmation boolean not null default false;

alter table public.driver_reputation_config enable row level security;
alter table public.driver_rank_configs enable row level security;
alter table public.driver_metrics enable row level security;
alter table public.driver_offers enable row level security;
alter table public.customer_trust_profiles enable row level security;
alter table public.delivery_incidents enable row level security;
alter table public.audit_events enable row level security;

create policy admin_reputation_config_all on public.driver_reputation_config for all to authenticated using(private.is_admin()) with check(private.is_admin());
create policy authenticated_reads_driver_ranks on public.driver_rank_configs for select to authenticated using(true);
create policy admin_driver_ranks_all on public.driver_rank_configs for all to authenticated using(private.is_admin()) with check(private.is_admin());
create policy driver_reads_own_metrics on public.driver_metrics for select to authenticated using(courier_id=(select id from public.couriers where user_id=(select auth.uid())) or private.is_admin());
create policy driver_reads_own_offers on public.driver_offers for select to authenticated using(courier_id=(select id from public.couriers where user_id=(select auth.uid())) or private.is_admin());
create policy customer_reads_own_trust on public.customer_trust_profiles for select to authenticated using(customer_id=(select auth.uid()) or private.is_admin());
create policy driver_reads_own_incidents on public.delivery_incidents for select to authenticated using(courier_id=(select id from public.couriers where user_id=(select auth.uid())) or private.is_admin());
create policy admin_incidents_all on public.delivery_incidents for all to authenticated using(private.is_admin()) with check(private.is_admin());
create policy admin_reads_audit on public.audit_events for select to authenticated using(private.is_admin());

grant select on public.driver_reputation_config,public.driver_rank_configs,public.driver_metrics,public.driver_offers,public.customer_trust_profiles,public.delivery_incidents,public.audit_events to authenticated;
revoke insert,update,delete on public.driver_metrics,public.driver_offers,public.customer_trust_profiles,public.audit_events from authenticated;

create or replace function private.write_audit(
  p_event_type text,p_entity_type text,p_entity_id text,p_reason text,p_old jsonb,p_new jsonb,p_metadata jsonb default '{}'::jsonb
) returns void language sql security definer set search_path=''
as $$insert into public.audit_events(actor_id,event_type,entity_type,entity_id,reason,old_value,new_value,metadata) values(auth.uid(),p_event_type,p_entity_type,p_entity_id,p_reason,p_old,p_new,coalesce(p_metadata,'{}'::jsonb))$$;

create or replace function private.refresh_driver_metrics(p_courier_id uuid)
returns public.driver_metrics language plpgsql security definer set search_path=''
as $$
declare
  v_config public.driver_reputation_config;
  v_old public.driver_metrics;
  v_result public.driver_metrics;
  v_offered integer;v_accepted integer;v_completed integer;v_cancelled integer;v_incidents integer;
  v_punctual integer;v_days integer;v_7 integer;v_30 integer;v_avg numeric;v_last timestamptz;
  v_accept_rate numeric;v_completion_rate numeric;v_punctual_rate numeric;v_consistency numeric;v_quality numeric;v_score numeric;v_rank text;
  v_explanation jsonb;
begin
  select * into v_config from public.driver_reputation_config where id='main';
  select * into v_old from public.driver_metrics where courier_id=p_courier_id;
  select count(*) filter(where o.offered_at<=now() and not o.excluded_from_acceptance_rate),
         count(*) filter(where o.status='accepted')
    into v_offered,v_accepted from public.driver_offers o where o.courier_id=p_courier_id;
  select count(*) filter(where a.status='delivered'),count(*) filter(where a.status='cancelled'),
         count(*) filter(where a.status='delivered' and a.delivered_at<=a.accepted_at+make_interval(mins=>v_config.punctual_delivery_minutes)),
         count(distinct (a.delivered_at at time zone 'America/Mexico_City')::date) filter(where a.status='delivered' and a.delivered_at>=now()-interval '30 days'),
         count(*) filter(where a.status='delivered' and a.delivered_at>=now()-interval '7 days'),
         count(*) filter(where a.status='delivered' and a.delivered_at>=now()-interval '30 days'),
         avg(extract(epoch from(a.delivered_at-a.accepted_at))/60) filter(where a.status='delivered'),
         max(a.delivered_at) filter(where a.status='delivered')
    into v_completed,v_cancelled,v_punctual,v_days,v_7,v_30,v_avg,v_last
  from public.delivery_assignments a where a.courier_id=p_courier_id;
  select count(*) into v_incidents from public.delivery_incidents where courier_id=p_courier_id and review_status='valid' and affects_scores;
  v_accept_rate:=case when v_offered=0 then 100 else least(100,100.0*v_accepted/v_offered) end;
  v_completion_rate:=case when v_accepted=0 then 100 else greatest(0,100.0*v_completed/v_accepted) end;
  v_punctual_rate:=case when v_completed=0 then 100 else 100.0*v_punctual/v_completed end;
  v_consistency:=least(100,100.0*v_days/12);
  v_quality:=case when v_accepted=0 then 100 else greatest(0,100.0*(v_accepted-v_cancelled-v_incidents)/v_accepted) end;
  v_score:=round(greatest(0,least(100,(
    v_completion_rate*v_config.completion_weight+v_accept_rate*v_config.acceptance_weight+
    v_punctual_rate*v_config.punctuality_weight+v_consistency*v_config.consistency_weight+
    v_quality*v_config.quality_weight
  )/nullif(v_config.completion_weight+v_config.acceptance_weight+v_config.punctuality_weight+v_config.consistency_weight+v_config.quality_weight,0))),2);
  select id into v_rank from public.driver_rank_configs where active and min_completed<=v_completed and min_score<=v_score order by sort_order desc limit 1;
  v_rank:=coalesce(v_rank,'bronze');
  v_explanation:=jsonb_build_array(
    format('%s%% de cumplimiento',round(v_completion_rate)),
    format('%s entregas en los últimos 30 días',v_30),
    format('%s%% de puntualidad',round(v_punctual_rate)),
    case when v_cancelled+v_incidents=0 then 'Sin cancelaciones ni incidencias válidas' else format('%s cancelaciones o incidencias válidas',v_cancelled+v_incidents) end
  );
  insert into public.driver_metrics(courier_id,trips_offered,trips_accepted,trips_completed,trips_cancelled,completed_correctly,incident_count,acceptance_rate,completion_rate,punctuality_rate,average_delivery_minutes,active_days_30,trips_7_days,trips_30_days,last_delivery_at,driver_score,rank_id,explanation,calculated_at)
  values(p_courier_id,v_offered,v_accepted,v_completed,v_cancelled,greatest(0,v_completed-v_incidents),v_incidents,round(v_accept_rate,2),round(v_completion_rate,2),round(v_punctual_rate,2),round(v_avg,2),v_days,v_7,v_30,v_last,v_score,v_rank,v_explanation,now())
  on conflict(courier_id) do update set trips_offered=excluded.trips_offered,trips_accepted=excluded.trips_accepted,trips_completed=excluded.trips_completed,trips_cancelled=excluded.trips_cancelled,completed_correctly=excluded.completed_correctly,incident_count=excluded.incident_count,acceptance_rate=excluded.acceptance_rate,completion_rate=excluded.completion_rate,punctuality_rate=excluded.punctuality_rate,average_delivery_minutes=excluded.average_delivery_minutes,active_days_30=excluded.active_days_30,trips_7_days=excluded.trips_7_days,trips_30_days=excluded.trips_30_days,last_delivery_at=excluded.last_delivery_at,driver_score=excluded.driver_score,rank_id=excluded.rank_id,explanation=excluded.explanation,calculated_at=now()
  returning * into v_result;
  if v_old.courier_id is not null and (v_old.driver_score<>v_result.driver_score or v_old.rank_id<>v_result.rank_id) then
    perform private.write_audit('driver_score_changed','courier',p_courier_id::text,'Recalculo por actividad operativa',jsonb_build_object('score',v_old.driver_score,'rank',v_old.rank_id),jsonb_build_object('score',v_result.driver_score,'rank',v_result.rank_id));
  end if;
  return v_result;
end $$;

create or replace function private.refresh_customer_trust(p_customer_id uuid)
returns public.customer_trust_profiles language plpgsql security definer set search_path=''
as $$
declare v_old public.customer_trust_profiles;v_result public.customer_trust_profiles;v_total integer;v_completed integer;v_cancelled integer;v_paid integer;v_incidents integer;v_addresses integer;v_last timestamptz;v_age_days integer;v_score numeric;v_level text;v_explanation jsonb;
begin
  select * into v_old from public.customer_trust_profiles where customer_id=p_customer_id;
  select count(*),count(*) filter(where status='delivered'),count(*) filter(where status='cancelled'),count(*) filter(where payment_status='paid' or status='delivered'),count(distinct nullif(lower(trim(address->>'address')),'')),max(delivered_at) filter(where status='delivered')
  into v_total,v_completed,v_cancelled,v_paid,v_addresses,v_last from public.orders where customer_id=p_customer_id;
  select count(*) into v_incidents from public.delivery_incidents where customer_id=p_customer_id and review_status='valid' and affects_scores;
  select greatest(0,extract(day from now()-created_at)::integer) into v_age_days from public.customers where id=p_customer_id;
  if v_total=0 then v_score:=50; else
    v_score:=round(greatest(0,least(100,45.0*v_completed/v_total+least(25,v_completed*5)+least(10,v_age_days/9.0)+20.0*v_paid/v_total-v_cancelled*8-v_incidents*12)),2);
  end if;
  v_level:=case when v_completed>=15 and v_score>=90 then 'vip' when v_completed>=5 and v_score>=80 then 'trusted' when v_completed>=3 and v_score>=65 then 'regular' else 'new' end;
  v_explanation:=jsonb_build_array(
    format('%s pedidos completados',v_completed),
    case when v_addresses>0 then format('%s direcciones utilizadas anteriormente',v_addresses) else 'Sin dirección previamente entregada' end,
    case when v_incidents=0 then 'Sin incidencias válidas' else format('%s incidencias válidas',v_incidents) end,
    case when v_cancelled=0 then 'Sin cancelaciones' else format('%s cancelaciones',v_cancelled) end
  );
  insert into public.customer_trust_profiles(customer_id,orders_total,orders_completed,orders_cancelled,successful_payments,incident_count,addresses_used,trust_score,trust_level,last_completed_at,explanation,calculated_at)
  values(p_customer_id,v_total,v_completed,v_cancelled,v_paid,v_incidents,v_addresses,v_score,v_level,v_last,v_explanation,now())
  on conflict(customer_id) do update set orders_total=excluded.orders_total,orders_completed=excluded.orders_completed,orders_cancelled=excluded.orders_cancelled,successful_payments=excluded.successful_payments,incident_count=excluded.incident_count,addresses_used=excluded.addresses_used,trust_score=excluded.trust_score,trust_level=excluded.trust_level,last_completed_at=excluded.last_completed_at,explanation=excluded.explanation,calculated_at=now()
  returning * into v_result;
  if v_old.customer_id is not null and (v_old.trust_score<>v_result.trust_score or v_old.trust_level<>v_result.trust_level) then
    perform private.write_audit('customer_trust_changed','customer',p_customer_id::text,'Recalculo por historial de pedidos',jsonb_build_object('score',v_old.trust_score,'level',v_old.trust_level),jsonb_build_object('score',v_result.trust_score,'level',v_result.trust_level));
  end if;
  return v_result;
end $$;

create or replace function private.build_driver_offers(p_request_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare v_request public.delivery_requests;v_order public.orders;v_trust public.customer_trust_profiles;v_config public.driver_reputation_config;v_signals text[]:='{}';v_ranked record;
begin
  select * into v_request from public.delivery_requests where id=p_request_id for update;
  select * into v_order from public.orders where id=v_request.order_id;
  select * into v_trust from private.refresh_customer_trust(v_order.customer_id);
  select * into v_config from public.driver_reputation_config where id='main';
  if v_trust.orders_completed=0 then v_signals:=array_append(v_signals,'Cliente nuevo, sin historial de entregas'); end if;
  if extract(hour from v_order.created_at at time zone 'America/Mexico_City')>=v_config.night_start_hour then v_signals:=array_append(v_signals,'Entrega nocturna'); end if;
  if lower(v_order.payment_method) like '%efectivo%' then v_signals:=array_append(v_signals,'Pago en efectivo'); end if;
  if v_order.total>=v_config.high_value_threshold then v_signals:=array_append(v_signals,'Pedido de valor elevado'); end if;
  if not exists(select 1 from public.orders p where p.customer_id=v_order.customer_id and p.status='delivered' and p.id<>v_order.id and lower(trim(p.address->>'address'))=lower(trim(v_order.address->>'address'))) then v_signals:=array_append(v_signals,'Dirección sin entregas previas'); end if;
  update public.delivery_requests set safety_signals=to_jsonb(v_signals),safety_level=case when cardinality(v_signals)>=2 then 'additional_precautions' else 'standard' end,requires_confirmation=cardinality(v_signals)>=3 where id=p_request_id;
  delete from public.driver_offers where request_id=p_request_id;
  for v_ranked in
    with candidates as (
      select c.id,coalesce(m.driver_score,50) driver_score,coalesce(rc.priority_bonus,0) rank_bonus,coalesce(m.trips_7_days,0) recent,
        (select count(*) from public.delivery_assignments a where a.courier_id=c.id and a.status not in('delivered','cancelled')) active_count,
        least(20,greatest(0,extract(epoch from(now()-coalesce(m.last_delivery_at,c.created_at)))/3600)) fairness
      from public.couriers c left join public.driver_metrics m on m.courier_id=c.id left join public.driver_rank_configs rc on rc.id=m.rank_id
      where c.active
    ), ranked as (
      select *,round(driver_score*.45+rank_bonus+fairness+(3-active_count)*8-recent*1.5-active_count*12,2) priority,
        row_number() over(order by driver_score*.45+rank_bonus+fairness+(3-active_count)*8-recent*1.5-active_count*12 desc,id) position
      from candidates where active_count<3
    ) select * from ranked
  loop
    insert into public.driver_offers(request_id,courier_id,round,dispatch_priority_score,offered_at,expires_at,excluded_from_acceptance_rate)
    values(p_request_id,v_ranked.id,
      case when v_ranked.position<=v_config.first_round_size then 1 when v_ranked.position<=v_config.first_round_size+v_config.second_round_size then 2 else 3 end,
      v_ranked.priority,
      v_request.requested_at+case when v_ranked.position<=v_config.first_round_size then interval '0 seconds' when v_ranked.position<=v_config.first_round_size+v_config.second_round_size then make_interval(secs=>v_config.first_round_seconds) else make_interval(secs=>v_config.first_round_seconds+v_config.second_round_seconds) end,
      v_request.requested_at+interval '15 minutes',
      cardinality(v_signals)>=2
    );
  end loop;
end $$;

create or replace function private.request_driver_impl(p_order_id uuid,p_pay numeric,p_pickup_address text)
returns public.delivery_requests language plpgsql security definer set search_path=''
as $$declare v_order public.orders;v_request public.delivery_requests;begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found or v_order.delivery_type<>'delivery' or v_order.status<>'ready' then raise exception 'ORDER_NOT_READY_FOR_DELIVERY'; end if;
  perform private.refresh_driver_metrics(id) from public.couriers where active;
  insert into public.delivery_requests(order_id,pay,pickup_address) values(p_order_id,greatest(v_order.driver_pay,0),trim(p_pickup_address))
  on conflict(order_id) do update set status='requested',pay=excluded.pay,pickup_address=excluded.pickup_address,assigned_at=null,requested_at=now(),updated_at=now() where public.delivery_requests.status='cancelled'
  returning * into v_request;
  if v_request.id is null then select * into v_request from public.delivery_requests where order_id=p_order_id; end if;
  if v_request.status='requested' and not exists(select 1 from public.driver_offers where request_id=v_request.id) then perform private.build_driver_offers(v_request.id); end if;
  return v_request;
end $$;

drop function if exists public.driver_available_requests();
drop function if exists private.driver_available_requests_impl();
create function private.driver_available_requests_impl()
returns table(id uuid,order_id uuid,pay numeric,pickup_address text,status text,order_number bigint,delivery_address text,maps_url text,distance_km numeric,order_items jsonb,customer_name text,customer_trust_score numeric,customer_trust_level text,customer_completed_orders integer,customer_last_delivery timestamptz,safety_level text,safety_signals jsonb,offer_round integer,dispatch_priority_score numeric)
language sql security definer set search_path=''
as $$
  select r.id,r.order_id,r.pay,r.pickup_address,r.status,o.order_number,
    case when o.delivery_distance_km is null then 'Zona por confirmar' else format('A %s km de Cande',round(o.delivery_distance_km,1)) end,
    null::text,o.delivery_distance_km,
    coalesce((select jsonb_agg(jsonb_build_object('product_name',i.product_name,'size_name',i.size_name,'quantity',i.quantity) order by i.id) from public.order_items i where i.order_id=o.id),'[]'::jsonb),
    split_part(cu.name,' ',1),coalesce(tp.trust_score,50),coalesce(tp.trust_level,'new'),coalesce(tp.orders_completed,0),tp.last_completed_at,
    r.safety_level,r.safety_signals,offer.round,offer.dispatch_priority_score
  from public.driver_offers offer join public.delivery_requests r on r.id=offer.request_id join public.orders o on o.id=r.order_id join public.customers cu on cu.id=o.customer_id
  join public.couriers c on c.id=offer.courier_id and c.user_id=auth.uid() and c.active and c.status='available'
  left join public.customer_trust_profiles tp on tp.customer_id=o.customer_id
  where private.is_driver() and r.status='requested' and offer.status='offered' and offer.offered_at<=now() and coalesce(offer.expires_at,now()+interval '1 minute')>now()
    and (select count(*) from public.delivery_assignments a where a.courier_id=c.id and a.status not in('delivered','cancelled'))<3
    and not exists(select 1 from public.delivery_request_rejections x where x.request_id=r.id and x.courier_id=c.id)
  order by offer.dispatch_priority_score desc,r.requested_at;
$$;
create function public.driver_available_requests()
returns table(id uuid,order_id uuid,pay numeric,pickup_address text,status text,order_number bigint,delivery_address text,maps_url text,distance_km numeric,order_items jsonb,customer_name text,customer_trust_score numeric,customer_trust_level text,customer_completed_orders integer,customer_last_delivery timestamptz,safety_level text,safety_signals jsonb,offer_round integer,dispatch_priority_score numeric)
language sql security definer set search_path='' as $$select * from private.driver_available_requests_impl()$$;

create or replace function private.accept_delivery_impl(p_request_id uuid)
returns public.delivery_assignments language plpgsql security definer set search_path=''
as $$declare v_courier public.couriers;v_request public.delivery_requests;v_assignment public.delivery_assignments;v_active integer;begin
  if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
  select * into v_courier from public.couriers where user_id=auth.uid() and active and status<>'unavailable' for update;
  if not found then raise exception 'DRIVER_NOT_AVAILABLE'; end if;
  select count(*) into v_active from public.delivery_assignments where courier_id=v_courier.id and status not in('delivered','cancelled');
  if v_active>=3 then raise exception 'DRIVER_CAPACITY_FULL'; end if;
  if not exists(select 1 from public.driver_offers where request_id=p_request_id and courier_id=v_courier.id and status='offered' and offered_at<=now() and coalesce(expires_at,now()+interval '1 minute')>now()) then raise exception 'DELIVERY_NOT_OFFERED_TO_DRIVER'; end if;
  update public.delivery_requests set status='assigned',assigned_at=now(),updated_at=now() where id=p_request_id and status='requested' returning * into v_request;
  if v_request.id is null then raise exception 'DELIVERY_ALREADY_TAKEN'; end if;
  insert into public.delivery_assignments(order_id,courier_id,status,delivery_fee) values(v_request.order_id,v_courier.id,'accepted',v_request.pay) returning * into v_assignment;
  update public.driver_offers set status=case when courier_id=v_courier.id then 'accepted' else 'expired' end,responded_at=case when courier_id=v_courier.id then now() else responded_at end where request_id=p_request_id and status='offered';
  update public.couriers set status=case when v_active+1>=3 then 'busy' else 'available' end,last_activity_at=now() where id=v_courier.id;
  perform private.refresh_driver_metrics(v_courier.id);
  return v_assignment;
end $$;

create or replace function private.reject_delivery_impl(p_request_id uuid)
returns void language plpgsql security definer set search_path=''
as $$declare v_courier uuid;begin
  if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
  select id into v_courier from public.couriers where user_id=auth.uid() and active and status='available';
  if v_courier is null then raise exception 'DRIVER_NOT_AVAILABLE'; end if;
  if not exists(select 1 from public.delivery_requests where id=p_request_id and status='requested') then raise exception 'DELIVERY_ALREADY_TAKEN'; end if;
  update public.driver_offers set status='rejected',responded_at=now() where request_id=p_request_id and courier_id=v_courier and status='offered' and offered_at<=now();
  if not found then raise exception 'DELIVERY_NOT_OFFERED_TO_DRIVER'; end if;
  insert into public.delivery_request_rejections(request_id,courier_id) values(p_request_id,v_courier) on conflict do nothing;
  perform private.refresh_driver_metrics(v_courier);
end $$;

create or replace function private.driver_dashboard_impl()
returns jsonb language plpgsql security definer set search_path=''
as $$declare v_courier public.couriers;v_assignments jsonb;v_metrics public.driver_metrics;v_rank public.driver_rank_configs;v_next public.driver_rank_configs;begin
  if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
  select * into v_courier from public.couriers where user_id=auth.uid() and active;
  if not found then raise exception 'COURIER_NOT_FOUND'; end if;
  select * into v_metrics from private.refresh_driver_metrics(v_courier.id);
  select * into v_rank from public.driver_rank_configs where id=v_metrics.rank_id;
  select * into v_next from public.driver_rank_configs where active and sort_order>v_rank.sort_order order by sort_order limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'status',a.status,'delivery_fee',a.delivery_fee,'accepted_at',a.accepted_at,'updated_at',a.updated_at,
    'orders',jsonb_build_object('id',o.id,'order_number',o.order_number,'total',o.total,'address',o.address,'references_text',o.references_text,'notes',o.notes,'payment_method',o.payment_method,
      'customers',jsonb_build_object('name',cu.name,'phone',cu.phone,'trust_level',coalesce(tp.trust_level,'new'),'trust_score',coalesce(tp.trust_score,50),'completed_orders',coalesce(tp.orders_completed,0),'last_completed_at',tp.last_completed_at),
      'order_items',coalesce((select jsonb_agg(jsonb_build_object('product_name',i.product_name,'size_name',i.size_name,'quantity',i.quantity) order by i.id) from public.order_items i where i.order_id=o.id),'[]'::jsonb))
  ) order by a.accepted_at desc),'[]'::jsonb) into v_assignments from public.delivery_assignments a join public.orders o on o.id=a.order_id join public.customers cu on cu.id=o.customer_id left join public.customer_trust_profiles tp on tp.customer_id=cu.id where a.courier_id=v_courier.id;
  return to_jsonb(v_courier)||jsonb_build_object('delivery_assignments',v_assignments,'reputation',to_jsonb(v_metrics)||jsonb_build_object('rank',to_jsonb(v_rank),'next_rank',to_jsonb(v_next)));
end $$;

create or replace function private.driver_update_delivery_impl(p_assignment_id uuid,p_status text)
returns public.delivery_assignments language plpgsql security definer set search_path=''
as $$declare v public.delivery_assignments;v_active integer;v_customer uuid;begin
  if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
  select a.* into v from public.delivery_assignments a join public.couriers c on c.id=a.courier_id where a.id=p_assignment_id and c.user_id=auth.uid() for update of a;
  if not found then raise exception 'ASSIGNMENT_NOT_FOUND'; end if;
  if not ((v.status='accepted' and p_status='heading_to_pickup') or(v.status='heading_to_pickup' and p_status='picked_up') or(v.status='picked_up' and p_status='delivering') or(v.status='delivering' and p_status='delivered')) then raise exception 'INVALID_DELIVERY_TRANSITION'; end if;
  update public.delivery_assignments set status=p_status,updated_at=now(),heading_to_pickup_at=case when p_status='heading_to_pickup' then now() else heading_to_pickup_at end,picked_up_at=case when p_status='picked_up' then now() else picked_up_at end,delivering_at=case when p_status='delivering' then now() else delivering_at end,delivered_at=case when p_status='delivered' then now() else delivered_at end where id=v.id returning * into v;
  if p_status='delivered' then
    update public.orders set status='delivered',delivered_at=now() where id=v.order_id returning customer_id into v_customer;
    select count(*) into v_active from public.delivery_assignments where courier_id=v.courier_id and status not in('delivered','cancelled');
    update public.couriers set status=case when v_active>=3 then 'busy' else 'available' end,last_activity_at=now() where id=v.courier_id;
    perform private.refresh_driver_metrics(v.courier_id);perform private.refresh_customer_trust(v_customer);
  end if;
  return v;
end $$;

create or replace function private.driver_report_incident_impl(p_assignment_id uuid,p_category text,p_details text)
returns public.delivery_incidents language plpgsql security definer set search_path=''
as $$declare v_assignment public.delivery_assignments;v_order public.orders;v_incident public.delivery_incidents;begin
  if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
  if p_category not in('customer_unresponsive','wrong_address','no_access','customer_rejected','payment_problem','feeling_unsafe','other') then raise exception 'INVALID_INCIDENT_CATEGORY'; end if;
  select a.* into v_assignment from public.delivery_assignments a join public.couriers c on c.id=a.courier_id where a.id=p_assignment_id and c.user_id=auth.uid();
  if not found then raise exception 'ASSIGNMENT_NOT_FOUND'; end if;
  select * into v_order from public.orders where id=v_assignment.order_id;
  insert into public.delivery_incidents(order_id,assignment_id,courier_id,customer_id,category,details,created_by,affects_scores) values(v_order.id,v_assignment.id,v_assignment.courier_id,v_order.customer_id,p_category,nullif(trim(p_details),''),auth.uid(),false) returning * into v_incident;
  perform private.write_audit('incident_reported','delivery_incident',v_incident.id::text,'Reporte del repartidor',null,to_jsonb(v_incident));
  return v_incident;
end $$;

create or replace function private.admin_review_incident_impl(p_incident_id uuid,p_status text,p_affects_scores boolean,p_notes text)
returns public.delivery_incidents language plpgsql security definer set search_path=''
as $$declare v_old public.delivery_incidents;v_new public.delivery_incidents;begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  if p_status not in('reviewed','valid','dismissed') then raise exception 'INVALID_REVIEW_STATUS'; end if;
  select * into v_old from public.delivery_incidents where id=p_incident_id for update;if not found then raise exception 'INCIDENT_NOT_FOUND'; end if;
  update public.delivery_incidents set review_status=p_status,affects_scores=case when p_status='valid' then p_affects_scores else false end,reviewed_by=auth.uid(),reviewed_at=now(),review_notes=nullif(trim(p_notes),'') where id=p_incident_id returning * into v_new;
  perform private.write_audit('incident_reviewed','delivery_incident',v_new.id::text,'Revisión administrativa',to_jsonb(v_old),to_jsonb(v_new));
  perform private.refresh_driver_metrics(v_new.courier_id);if v_new.customer_id is not null then perform private.refresh_customer_trust(v_new.customer_id);end if;return v_new;
end $$;

create or replace function public.driver_report_incident(p_assignment_id uuid,p_category text,p_details text default null) returns public.delivery_incidents language sql security definer set search_path='' as $$select private.driver_report_incident_impl(p_assignment_id,p_category,p_details)$$;
create or replace function public.admin_review_incident(p_incident_id uuid,p_status text,p_affects_scores boolean default false,p_notes text default null) returns public.delivery_incidents language sql security definer set search_path='' as $$select private.admin_review_incident_impl(p_incident_id,p_status,p_affects_scores,p_notes)$$;

create or replace function public.admin_reputation_dashboard()
returns jsonb language plpgsql security definer set search_path=''
as $$declare v_drivers jsonb;v_incidents jsonb;begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  perform private.refresh_driver_metrics(id) from public.couriers where active;
  select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('metrics',to_jsonb(m),'rank',to_jsonb(r),'active_deliveries',(select count(*) from public.delivery_assignments a where a.courier_id=c.id and a.status not in('delivered','cancelled'))) order by m.driver_score desc),'[]'::jsonb) into v_drivers from public.couriers c left join public.driver_metrics m on m.courier_id=c.id left join public.driver_rank_configs r on r.id=m.rank_id where c.active;
  select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('courier_name',c.name,'customer_name',cu.name,'order_number',o.order_number) order by i.created_at desc),'[]'::jsonb) into v_incidents from public.delivery_incidents i join public.couriers c on c.id=i.courier_id join public.orders o on o.id=i.order_id left join public.customers cu on cu.id=i.customer_id where i.review_status='pending';
  return jsonb_build_object('drivers',v_drivers,'incidents',v_incidents,'config',(select to_jsonb(x) from public.driver_reputation_config x where id='main'),'ranks',(select jsonb_agg(to_jsonb(x) order by sort_order) from public.driver_rank_configs x));
end $$;

create or replace function public.admin_save_reputation_config(p_config jsonb,p_ranks jsonb)
returns void language plpgsql security definer set search_path=''
as $$declare v_old jsonb;v_rank jsonb;begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  select to_jsonb(x) into v_old from public.driver_reputation_config x where id='main';
  update public.driver_reputation_config set completion_weight=greatest(0,(p_config->>'completion_weight')::numeric),acceptance_weight=greatest(0,(p_config->>'acceptance_weight')::numeric),punctuality_weight=greatest(0,(p_config->>'punctuality_weight')::numeric),consistency_weight=greatest(0,(p_config->>'consistency_weight')::numeric),quality_weight=greatest(0,(p_config->>'quality_weight')::numeric),punctual_delivery_minutes=(p_config->>'punctual_delivery_minutes')::integer,first_round_size=(p_config->>'first_round_size')::integer,second_round_size=(p_config->>'second_round_size')::integer,first_round_seconds=(p_config->>'first_round_seconds')::integer,second_round_seconds=(p_config->>'second_round_seconds')::integer,night_start_hour=(p_config->>'night_start_hour')::integer,high_value_threshold=(p_config->>'high_value_threshold')::numeric,updated_at=now(),updated_by=auth.uid() where id='main';
  for v_rank in select * from jsonb_array_elements(p_ranks) loop update public.driver_rank_configs set min_completed=(v_rank->>'min_completed')::integer,min_score=(v_rank->>'min_score')::numeric,priority_bonus=(v_rank->>'priority_bonus')::numeric,benefits=coalesce(v_rank->'benefits',benefits),active=coalesce((v_rank->>'active')::boolean,active) where id=v_rank->>'id';end loop;
  perform private.write_audit('reputation_config_changed','driver_reputation_config','main','Cambio administrativo',v_old,(select to_jsonb(x) from public.driver_reputation_config x where id='main'));
  perform private.refresh_driver_metrics(id) from public.couriers where active;
end $$;

revoke all on function public.driver_available_requests(),public.driver_report_incident(uuid,text,text),public.admin_review_incident(uuid,text,boolean,text),public.admin_reputation_dashboard(),public.admin_save_reputation_config(jsonb,jsonb) from public,anon;
grant execute on function public.driver_available_requests(),public.driver_report_incident(uuid,text,text) to authenticated;
grant execute on function public.admin_review_incident(uuid,text,boolean,text),public.admin_reputation_dashboard(),public.admin_save_reputation_config(jsonb,jsonb) to authenticated;
revoke all on function private.write_audit(text,text,text,text,jsonb,jsonb,jsonb),private.refresh_driver_metrics(uuid),private.refresh_customer_trust(uuid),private.build_driver_offers(uuid),private.driver_report_incident_impl(uuid,text,text),private.admin_review_incident_impl(uuid,text,boolean,text) from public,anon,authenticated;

insert into public.customer_trust_profiles(customer_id) select id from public.customers on conflict do nothing;
select private.refresh_customer_trust(id) from public.customers;
insert into public.driver_metrics(courier_id) select id from public.couriers on conflict do nothing;
select private.refresh_driver_metrics(id) from public.couriers;
select private.build_driver_offers(id) from public.delivery_requests where status='requested' and not exists(select 1 from public.driver_offers o where o.request_id=delivery_requests.id);

do $$begin alter publication supabase_realtime add table public.driver_offers;exception when duplicate_object then null;end$$;
do $$begin alter publication supabase_realtime add table public.delivery_incidents;exception when duplicate_object then null;end$$;

commit;
