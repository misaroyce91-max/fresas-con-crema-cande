begin;

create or replace function private.refresh_driver_metrics(p_courier_id uuid)
returns public.driver_metrics language plpgsql security definer set search_path=''
as $$
declare
  v_config public.driver_reputation_config; v_old public.driver_metrics; v_result public.driver_metrics;
  v_offered integer;v_accepted integer;v_completed integer;v_cancelled integer;v_incidents integer;
  v_punctual integer;v_days integer;v_7 integer;v_30 integer;v_avg numeric;v_last timestamptz;
  v_accept_rate numeric;v_completion_rate numeric;v_punctual_rate numeric;v_consistency numeric;v_quality numeric;v_score numeric;v_rank text;v_explanation jsonb;
begin
  select * into v_config from public.driver_reputation_config where id='main';
  select * into v_old from public.driver_metrics where courier_id=p_courier_id;
  select count(*) filter(where o.offered_at<=now() and not o.excluded_from_acceptance_rate) into v_offered from public.driver_offers o where o.courier_id=p_courier_id;
  select count(*),count(*) filter(where a.status='delivered'),count(*) filter(where a.status='cancelled'),
         count(*) filter(where a.status='delivered' and coalesce(a.delivered_at,a.updated_at)<=a.accepted_at+make_interval(mins=>v_config.punctual_delivery_minutes)),
         count(distinct (coalesce(a.delivered_at,a.updated_at) at time zone 'America/Mexico_City')::date) filter(where a.status='delivered' and coalesce(a.delivered_at,a.updated_at)>=now()-interval '30 days'),
         count(*) filter(where a.status='delivered' and coalesce(a.delivered_at,a.updated_at)>=now()-interval '7 days'),
         count(*) filter(where a.status='delivered' and coalesce(a.delivered_at,a.updated_at)>=now()-interval '30 days'),
         avg(extract(epoch from(coalesce(a.delivered_at,a.updated_at)-a.accepted_at))/60) filter(where a.status='delivered'),
         max(coalesce(a.delivered_at,a.updated_at)) filter(where a.status='delivered')
    into v_accepted,v_completed,v_cancelled,v_punctual,v_days,v_7,v_30,v_avg,v_last
  from public.delivery_assignments a where a.courier_id=p_courier_id;
  v_offered:=greatest(v_offered,v_accepted);
  select count(*) into v_incidents from public.delivery_incidents where courier_id=p_courier_id and review_status='valid' and affects_scores;
  v_accept_rate:=case when v_offered=0 then 100 else least(100,100.0*v_accepted/v_offered) end;
  v_completion_rate:=case when v_accepted=0 then 100 else greatest(0,100.0*v_completed/v_accepted) end;
  v_punctual_rate:=case when v_completed=0 then 100 else 100.0*v_punctual/v_completed end;
  v_consistency:=least(100,100.0*v_days/12);
  v_quality:=case when v_accepted=0 then 100 else greatest(0,100.0*(v_accepted-v_cancelled-v_incidents)/v_accepted) end;
  v_score:=round(greatest(0,least(100,(v_completion_rate*v_config.completion_weight+v_accept_rate*v_config.acceptance_weight+v_punctual_rate*v_config.punctuality_weight+v_consistency*v_config.consistency_weight+v_quality*v_config.quality_weight)/nullif(v_config.completion_weight+v_config.acceptance_weight+v_config.punctuality_weight+v_config.consistency_weight+v_config.quality_weight,0))),2);
  select id into v_rank from public.driver_rank_configs where active and min_completed<=v_completed and min_score<=v_score order by sort_order desc limit 1;
  v_rank:=coalesce(v_rank,'bronze');
  v_explanation:=jsonb_build_array(format('%s%% de cumplimiento',round(v_completion_rate)),format('%s entregas en los últimos 30 días',v_30),format('%s%% de puntualidad',round(v_punctual_rate)),case when v_cancelled+v_incidents=0 then 'Sin cancelaciones ni incidencias válidas' else format('%s cancelaciones o incidencias válidas',v_cancelled+v_incidents) end);
  insert into public.driver_metrics(courier_id,trips_offered,trips_accepted,trips_completed,trips_cancelled,completed_correctly,incident_count,acceptance_rate,completion_rate,punctuality_rate,average_delivery_minutes,active_days_30,trips_7_days,trips_30_days,last_delivery_at,driver_score,rank_id,explanation,calculated_at)
  values(p_courier_id,v_offered,v_accepted,v_completed,v_cancelled,greatest(0,v_completed-v_incidents),v_incidents,round(v_accept_rate,2),round(v_completion_rate,2),round(v_punctual_rate,2),round(v_avg,2),v_days,v_7,v_30,v_last,v_score,v_rank,v_explanation,now())
  on conflict(courier_id) do update set trips_offered=excluded.trips_offered,trips_accepted=excluded.trips_accepted,trips_completed=excluded.trips_completed,trips_cancelled=excluded.trips_cancelled,completed_correctly=excluded.completed_correctly,incident_count=excluded.incident_count,acceptance_rate=excluded.acceptance_rate,completion_rate=excluded.completion_rate,punctuality_rate=excluded.punctuality_rate,average_delivery_minutes=excluded.average_delivery_minutes,active_days_30=excluded.active_days_30,trips_7_days=excluded.trips_7_days,trips_30_days=excluded.trips_30_days,last_delivery_at=excluded.last_delivery_at,driver_score=excluded.driver_score,rank_id=excluded.rank_id,explanation=excluded.explanation,calculated_at=now() returning * into v_result;
  if v_old.courier_id is not null and (v_old.driver_score<>v_result.driver_score or v_old.rank_id<>v_result.rank_id) then perform private.write_audit('driver_score_changed','courier',p_courier_id::text,'Compatibilidad con historial operativo',jsonb_build_object('score',v_old.driver_score,'rank',v_old.rank_id),jsonb_build_object('score',v_result.driver_score,'rank',v_result.rank_id)); end if;
  return v_result;
end $$;

create or replace function public.service_due_driver_push_offers(p_request_id uuid)
returns table(offer_id uuid,courier_id uuid,request_id uuid,order_number bigint,round integer)
language plpgsql security definer set search_path=''
as $$begin
  if current_user not in ('service_role','postgres') then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  return query select x.id,x.courier_id,x.request_id,o.order_number,x.round from public.driver_offers x join public.delivery_requests r on r.id=x.request_id join public.orders o on o.id=r.order_id join public.couriers c on c.id=x.courier_id where x.request_id=p_request_id and x.status='offered' and x.offered_at<=now() and x.push_sent_at is null and r.status='requested' and c.active and c.status='available' and (select count(*) from public.delivery_assignments a where a.courier_id=c.id and a.status not in('delivered','cancelled'))<3;
end $$;
revoke all on function public.service_due_driver_push_offers(uuid) from public,anon,authenticated;
grant execute on function public.service_due_driver_push_offers(uuid) to service_role;

select private.refresh_driver_metrics(id) from public.couriers where active;
commit;
