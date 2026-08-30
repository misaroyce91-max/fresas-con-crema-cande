-- Referral program and administrable mixed-media Home carousel.
-- Additive and idempotent: it preserves all existing customers, orders and rewards.

alter table public.customers add column if not exists referral_code text;
alter table public.customers add column if not exists referred_by uuid references public.customers(id) on delete set null;
alter table public.rewards add column if not exists claim_only boolean not null default false;
alter table public.reward_redemptions drop constraint if exists reward_redemptions_points_spent_check;
alter table public.reward_redemptions add constraint reward_redemptions_points_spent_check check (points_spent >= 0);

update public.customers
set referral_code = 'CAN' || upper(substr(replace(id::text, '-', ''), 1, 12))
where referral_code is null;

alter table public.customers alter column referral_code set not null;
alter table public.customers alter column referral_code set default ('CAN' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)));
create unique index if not exists customers_referral_code_uidx on public.customers(upper(referral_code));
create index if not exists customers_referred_by_idx on public.customers(referred_by) where referred_by is not null;

create table if not exists public.referral_settings (
  id text primary key default 'main',
  active boolean not null default true,
  reward_size_name text not null default '10 oz',
  eligible_product_ids text[] not null default array['classic','oreo','kinder-bueno','kinder-delice','nutella','ferrero','carlos-v'],
  updated_at timestamptz not null default now(),
  constraint referral_settings_singleton check (id = 'main')
);

insert into public.referral_settings(id) values ('main') on conflict (id) do nothing;

create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references public.customers(id) on delete restrict,
  referred_customer_id uuid not null references public.customers(id) on delete restrict,
  referral_code text not null,
  status text not null default 'REGISTERED' check (status in ('REGISTERED','FIRST_ORDER_PENDING','QUALIFIED','REWARD_CREATED','REDEEMED','INVALID')),
  registered_at timestamptz not null default now(),
  qualified_order_id uuid unique references public.orders(id) on delete set null,
  qualified_at timestamptz,
  reward_redemption_id uuid unique references public.reward_redemptions(id) on delete set null,
  reward_created_at timestamptz,
  redeemed_at timestamptz,
  invalid_reason text,
  updated_at timestamptz not null default now(),
  unique(referred_customer_id),
  check (referrer_id <> referred_customer_id)
);

create index if not exists referrals_referrer_idx on public.referrals(referrer_id, registered_at desc);
create index if not exists referrals_status_idx on public.referrals(status);

create table if not exists public.homepage_promotions (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subtitle text not null default '',
  media_type text not null check (media_type in ('IMAGE','VIDEO')),
  media_url text not null,
  poster_url text,
  cta_label text,
  cta_href text,
  sort_order integer not null default 0,
  active boolean not null default false,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null default (now() + interval '30 days'),
  audience text not null default 'ALL' check (audience in ('ALL','NEW','RETURNING','HAS_REWARD')),
  loop_video boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (cta_href is null or cta_href ~ '^/')
);

create index if not exists homepage_promotions_schedule_idx
  on public.homepage_promotions(active, starts_at, ends_at, sort_order);

create table if not exists public.homepage_promotion_events (
  id bigint generated always as identity primary key,
  promotion_id uuid not null references public.homepage_promotions(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  session_id uuid not null,
  event_type text not null check (event_type in ('IMPRESSION','VIDEO_PLAY','CTA_CLICK')),
  created_at timestamptz not null default now()
);

create index if not exists homepage_promotion_events_reporting_idx
  on public.homepage_promotion_events(promotion_id, event_type, created_at desc);
create index if not exists homepage_promotion_events_customer_idx
  on public.homepage_promotion_events(customer_id) where customer_id is not null;
create index if not exists homepage_promotions_created_by_idx
  on public.homepage_promotions(created_by) where created_by is not null;

alter table public.referral_settings enable row level security;
alter table public.referrals enable row level security;
alter table public.homepage_promotions enable row level security;
alter table public.homepage_promotion_events enable row level security;

drop policy if exists referral_settings_read on public.referral_settings;
create policy referral_settings_read on public.referral_settings for select to authenticated using (true);
drop policy if exists referral_settings_admin on public.referral_settings;
create policy referral_settings_admin on public.referral_settings for all to authenticated using (private.is_admin()) with check (private.is_admin());

drop policy if exists referrals_own_read on public.referrals;
create policy referrals_own_read on public.referrals for select to authenticated using (referrer_id = auth.uid() or referred_customer_id = auth.uid() or private.is_admin());

drop policy if exists homepage_promotions_public_read on public.homepage_promotions;
create policy homepage_promotions_public_read on public.homepage_promotions for select to anon,authenticated
using ((active and starts_at <= now() and ends_at > now()) or private.is_admin());
drop policy if exists homepage_promotions_admin_write on public.homepage_promotions;
create policy homepage_promotions_admin_write on public.homepage_promotions for all to authenticated using (private.is_admin()) with check (private.is_admin());

drop policy if exists homepage_events_insert on public.homepage_promotion_events;
create policy homepage_events_insert on public.homepage_promotion_events for insert to anon,authenticated
with check (customer_id is null or customer_id = auth.uid());
drop policy if exists homepage_events_admin_read on public.homepage_promotion_events;
create policy homepage_events_admin_read on public.homepage_promotion_events for select to authenticated using (private.is_admin());

grant select on public.referral_settings, public.referrals, public.homepage_promotions to authenticated;
grant select on public.homepage_promotions to anon;
grant insert,update,delete on public.homepage_promotions to authenticated;
grant insert on public.homepage_promotion_events to anon,authenticated;
grant select on public.homepage_promotion_events to authenticated;
grant usage,select on sequence public.homepage_promotion_events_id_seq to anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('homepage-media','homepage-media',true,26214400,array['image/jpeg','image/png','image/webp','image/avif','video/mp4','video/webm'])
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists homepage_media_admin_insert on storage.objects;
create policy homepage_media_admin_insert on storage.objects for insert to authenticated
with check (bucket_id='homepage-media' and private.is_admin());
drop policy if exists homepage_media_admin_update on storage.objects;
create policy homepage_media_admin_update on storage.objects for update to authenticated
using (bucket_id='homepage-media' and private.is_admin()) with check (bucket_id='homepage-media' and private.is_admin());
drop policy if exists homepage_media_admin_delete on storage.objects;
create policy homepage_media_admin_delete on storage.objects for delete to authenticated
using (bucket_id='homepage-media' and private.is_admin());

create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  v_level uuid;
  v_referrer uuid;
  v_invite_code text := upper(trim(coalesce(new.raw_user_meta_data ->> 'referral_code','')));
  v_personal_code text := 'CAN' || upper(substr(replace(new.id::text,'-',''),1,12));
begin
  select id into v_level from public.customer_levels order by min_lifetime_points,sort_order limit 1;
  if coalesce(new.raw_app_meta_data ->> 'role','CLIENT') in ('CLIENT','CUSTOMER') then
    if v_invite_code <> '' then
      select id into v_referrer from public.customers where upper(referral_code)=v_invite_code and id<>new.id;
    end if;
    insert into public.customers(id,name,phone,level_id,referral_code,referred_by)
    values(new.id,trim(coalesce(nullif(new.raw_user_meta_data ->> 'name',''),'Cliente Cande')),
      regexp_replace(coalesce(new.phone,new.raw_user_meta_data ->> 'phone',''),'[^0-9+]','','g'),v_level,v_personal_code,v_referrer)
    on conflict(id) do nothing;
    if v_referrer is not null then
      insert into public.referrals(referrer_id,referred_customer_id,referral_code)
      values(v_referrer,new.id,v_invite_code) on conflict(referred_customer_id) do nothing;
    end if;
  end if;
  return new;
end
$$;

create or replace function private.track_referral_first_order()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.customer_id is not null then
    update public.referrals set status='FIRST_ORDER_PENDING',updated_at=now()
    where referred_customer_id=new.customer_id and status='REGISTERED';
  end if;
  return new;
end
$$;

drop trigger if exists track_referral_first_order_on_insert on public.orders;
create trigger track_referral_first_order_on_insert after insert on public.orders
for each row execute function private.track_referral_first_order();

create or replace function private.qualify_referral_on_order()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_referral public.referrals;
begin
  if new.customer_id is null or new.status <> 'delivered' then return new; end if;
  if not (new.payment_status='paid' or new.payment_method='Efectivo') then return new; end if;
  select * into v_referral from public.referrals
  where referred_customer_id=new.customer_id and status in ('REGISTERED','FIRST_ORDER_PENDING') for update;
  if found then
    update public.referrals set status='QUALIFIED',qualified_order_id=new.id,qualified_at=now(),updated_at=now()
    where id=v_referral.id;
  end if;
  return new;
end
$$;

drop trigger if exists qualify_referral_on_order_update on public.orders;
create trigger qualify_referral_on_order_update after update of status,payment_status on public.orders
for each row execute function private.qualify_referral_on_order();

create or replace function private.sync_referral_redemption()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.status='used' and old.status is distinct from new.status then
    update public.referrals set status='REDEEMED',redeemed_at=coalesce(new.used_at,now()),updated_at=now()
    where reward_redemption_id=new.id and status='REWARD_CREATED';
  end if;
  return new;
end
$$;

drop trigger if exists sync_referral_redemption_on_update on public.reward_redemptions;
create trigger sync_referral_redemption_on_update after update of status on public.reward_redemptions
for each row execute function private.sync_referral_redemption();

create or replace function private.referral_dashboard_impl()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare u uuid:=auth.uid(); c public.customers; result jsonb;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into c from public.customers where id=u;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  select jsonb_build_object(
    'code',c.referral_code,
    'registered',count(*),
    'qualified',count(*) filter(where r.status in('QUALIFIED','REWARD_CREATED','REDEEMED')),
    'rewardsEarned',count(*) filter(where r.status in('QUALIFIED','REWARD_CREATED','REDEEMED')),
    'rewardsAvailable',count(*) filter(where r.status in('QUALIFIED','REWARD_CREATED')),
    'eligibleProducts',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'image',p.image_url) order by p.sort_order),'[]') from public.referral_settings s join public.products p on p.id=any(s.eligible_product_ids) join public.product_sizes ps on ps.product_id=p.id and ps.name=s.reward_size_name and ps.active where s.id='main' and s.active and p.active and p.availability_status='active'),
    'rewardSize',(select reward_size_name from public.referral_settings where id='main'),
    'referrals',coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',split_part(rc.name,' ',1),'status',r.status,'registeredAt',r.registered_at,'qualifiedAt',r.qualified_at,'rewardRedemptionId',r.reward_redemption_id) order by r.registered_at desc),'[]')
  ) into result
  from public.referrals r join public.customers rc on rc.id=r.referred_customer_id
  where r.referrer_id=u;
  return result;
end
$$;

create or replace function public.referral_dashboard()
returns jsonb language sql security invoker set search_path=''
as $$ select private.referral_dashboard_impl() $$;

create or replace function private.claim_referral_reward_impl(p_referral_id uuid,p_product_id text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare u uuid:=auth.uid(); r public.referrals; s public.referral_settings; p public.products; rw public.rewards; rd public.reward_redemptions;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into r from public.referrals where id=p_referral_id and referrer_id=u for update;
  if not found then raise exception 'REFERRAL_NOT_FOUND'; end if;
  if r.reward_redemption_id is not null then
    select * into rd from public.reward_redemptions where id=r.reward_redemption_id;
    return jsonb_build_object('id',rd.id,'duplicate',true);
  end if;
  if r.status<>'QUALIFIED' then raise exception 'REWARD_NOT_AVAILABLE'; end if;
  select * into s from public.referral_settings where id='main' and active;
  if not found or not(p_product_id=any(s.eligible_product_ids)) then raise exception 'PRODUCT_NOT_ELIGIBLE'; end if;
  select p0.* into p from public.products p0 join public.product_sizes ps on ps.product_id=p0.id and ps.name=s.reward_size_name and ps.active where p0.id=p_product_id and p0.active and p0.availability_status='active';
  if not found then raise exception 'PRODUCT_NOT_AVAILABLE'; end if;
  select * into rw from public.rewards where code='REFERRAL_'||upper(replace(p.id,'-','_')) limit 1;
  if not found then
    insert into public.rewards(name,description,points_cost,reward_type,active,sort_order,code,product_id,size_name,claim_only)
    values('Referido: '||p.name||' '||s.reward_size_name,'Premio por invitar a un amigo',1,'free_product',true,-10,'REFERRAL_'||upper(replace(p.id,'-','_')),p.id,s.reward_size_name,true)
    returning * into rw;
  end if;
  insert into public.reward_redemptions(customer_id,reward_id,points_spent,status,client_request_id)
  values(u,rw.id,0,'available',gen_random_uuid()) returning * into rd;
  update public.referrals set status='REWARD_CREATED',reward_redemption_id=rd.id,reward_created_at=now(),updated_at=now() where id=r.id;
  return jsonb_build_object('id',rd.id,'rewardId',rw.id,'productId',p.id,'productName',p.name,'sizeName',s.reward_size_name,'duplicate',false);
end
$$;

create or replace function public.claim_referral_reward(p_referral_id uuid,p_product_id text)
returns jsonb language sql security invoker set search_path=''
as $$ select private.claim_referral_reward_impl(p_referral_id,p_product_id) $$;

create or replace function private.admin_referral_dashboard_impl()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare result jsonb;
begin
  if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
  select jsonb_build_object(
    'total',count(*),
    'qualified',count(*) filter(where r.status in('QUALIFIED','REWARD_CREATED','REDEEMED')),
    'rewardsCreated',count(*) filter(where r.status in('REWARD_CREATED','REDEEMED')),
    'rewardsRedeemed',count(*) filter(where r.status='REDEEMED'),
    'sales',coalesce(sum(o.total) filter(where r.qualified_order_id is not null),0),
    'items',coalesce(jsonb_agg(jsonb_build_object('id',r.id,'code',r.referral_code,'referrer',a.name,'referred',b.name,'registeredAt',r.registered_at,'status',r.status,'orderNumber',o.order_number,'orderTotal',o.total,'orderStatus',o.status,'rewardCreatedAt',r.reward_created_at,'redeemedAt',r.redeemed_at) order by r.registered_at desc),'[]')
  ) into result from public.referrals r join public.customers a on a.id=r.referrer_id join public.customers b on b.id=r.referred_customer_id left join public.orders o on o.id=r.qualified_order_id;
  return result;
end
$$;

create or replace function public.admin_referral_dashboard()
returns jsonb language sql security invoker set search_path=''
as $$ select private.admin_referral_dashboard_impl() $$;

revoke all on function private.referral_dashboard_impl() from public,anon;
revoke all on function private.claim_referral_reward_impl(uuid,text) from public,anon;
revoke all on function private.admin_referral_dashboard_impl() from public,anon;
revoke all on function public.referral_dashboard() from public,anon;
revoke all on function public.claim_referral_reward(uuid,text) from public,anon;
revoke all on function public.admin_referral_dashboard() from public,anon;
grant execute on function public.referral_dashboard() to authenticated;
grant execute on function public.claim_referral_reward(uuid,text) to authenticated;
grant execute on function public.admin_referral_dashboard() to authenticated;
grant execute on function private.referral_dashboard_impl() to authenticated;
grant execute on function private.claim_referral_reward_impl(uuid,text) to authenticated;
grant execute on function private.admin_referral_dashboard_impl() to authenticated;

create or replace function private.redeem_reward_impl(p_reward_id uuid,p_client_request_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid();v_customer public.customers;v_reward public.rewards;v_redemption public.reward_redemptions;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_client_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
 select rr.* into v_redemption from public.reward_redemptions rr where rr.customer_id=v_user and rr.client_request_id=p_client_request_id;
 if found then select * into v_reward from public.rewards where id=v_redemption.reward_id;return jsonb_build_object('id',v_redemption.id,'reward',v_reward.name,'balance',(select points_balance from public.customers where id=v_user),'duplicate',true,'rewardType',v_reward.reward_type,'discountValue',v_reward.reward_value,'productId',v_reward.product_id,'sizeName',v_reward.size_name);end if;
 select * into v_customer from public.customers where id=v_user for update;if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 select * into v_reward from public.rewards where id=p_reward_id and active and not claim_only for share;if not found then raise exception 'REWARD_NOT_AVAILABLE';end if;
 if v_customer.points_balance<v_reward.points_cost then raise exception 'INSUFFICIENT_POINTS';end if;
 if v_reward.reward_type='free_product' and(v_reward.product_id is null or v_reward.size_name is null)then raise exception 'REWARD_PRODUCT_NOT_CONFIGURED';end if;
 update public.customers set points_balance=points_balance-v_reward.points_cost,updated_at=now()where id=v_user;
 insert into public.reward_redemptions(customer_id,reward_id,points_spent,client_request_id)values(v_user,v_reward.id,v_reward.points_cost,p_client_request_id)returning * into v_redemption;
 insert into public.points_transactions(customer_id,type,points,balance_after,description)values(v_user,'redeem',-v_reward.points_cost,v_customer.points_balance-v_reward.points_cost,'Canje: '||v_reward.name);
 return jsonb_build_object('id',v_redemption.id,'reward',v_reward.name,'balance',v_customer.points_balance-v_reward.points_cost,'duplicate',false,'rewardType',v_reward.reward_type,'discountValue',v_reward.reward_value,'productId',v_reward.product_id,'sizeName',v_reward.size_name);
end
$$;

do $$ begin alter publication supabase_realtime add table public.homepage_promotions; exception when duplicate_object then null; end $$;
