-- Additive operational notifications for admins and configurable customer levels.
create table if not exists public.admin_notifications (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  type text not null,
  title text not null,
  description text not null,
  entity_type text,
  entity_id text,
  action_href text,
  created_at timestamptz not null default now()
);

create table if not exists public.admin_notification_receipts (
  notification_id uuid not null references public.admin_notifications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz,
  attended_at timestamptz,
  primary key(notification_id,user_id)
);

create index if not exists admin_notification_receipts_user_idx on public.admin_notification_receipts(user_id,read_at,attended_at);
alter table public.admin_notifications enable row level security;
alter table public.admin_notification_receipts enable row level security;
drop policy if exists admin_notifications_read on public.admin_notifications;
create policy admin_notifications_read on public.admin_notifications for select to authenticated using (private.is_admin());
drop policy if exists admin_notifications_write on public.admin_notifications;
create policy admin_notifications_write on public.admin_notifications for all to authenticated using (private.is_admin()) with check (private.is_admin());
drop policy if exists admin_notification_receipts_own on public.admin_notification_receipts;
create policy admin_notification_receipts_own on public.admin_notification_receipts for select to authenticated using (user_id=auth.uid() and private.is_admin());
drop policy if exists admin_notification_receipts_write_own on public.admin_notification_receipts;
create policy admin_notification_receipts_write_own on public.admin_notification_receipts for insert to authenticated with check (user_id=auth.uid() and private.is_admin());
drop policy if exists admin_notification_receipts_update_own on public.admin_notification_receipts;
create policy admin_notification_receipts_update_own on public.admin_notification_receipts for update to authenticated using (user_id=auth.uid() and private.is_admin()) with check (user_id=auth.uid() and private.is_admin());
grant select,insert,update on public.admin_notifications,public.admin_notification_receipts to authenticated;

-- Prompt 5 continuation: ADMIN preferences and registered browser devices.
create table if not exists public.admin_notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  heads_up_enabled boolean not null default true,
  sound_enabled boolean not null default true,
  vibration_enabled boolean not null default true,
  browser_notifications_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
create table if not exists public.admin_notification_devices (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  device_key text not null, label text not null default 'Navegador', user_agent text,
  notification_permission text not null default 'default' check (notification_permission in ('default','granted','denied','unsupported')),
  active boolean not null default true, last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(), unique (user_id,device_key)
);
create index if not exists admin_notifications_created_idx on public.admin_notifications(created_at desc);
create index if not exists admin_notifications_entity_idx on public.admin_notifications(entity_type,entity_id);
create index if not exists admin_notification_devices_user_idx on public.admin_notification_devices(user_id,active,last_seen_at desc);
alter table public.admin_notification_preferences enable row level security;
alter table public.admin_notification_devices enable row level security;
drop policy if exists admin_notification_preferences_own on public.admin_notification_preferences;
create policy admin_notification_preferences_own on public.admin_notification_preferences for all to authenticated using (user_id=(select auth.uid()) and private.is_admin()) with check (user_id=(select auth.uid()) and private.is_admin());
drop policy if exists admin_notification_devices_own on public.admin_notification_devices;
create policy admin_notification_devices_own on public.admin_notification_devices for all to authenticated using (user_id=(select auth.uid()) and private.is_admin()) with check (user_id=(select auth.uid()) and private.is_admin());
grant select,insert,update on public.admin_notification_preferences,public.admin_notification_devices to authenticated;

-- event_key guarantees one notification when an order RPC is retried.
create or replace function private.notify_admin_new_order()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.admin_notifications(event_key,type,title,description,entity_type,entity_id,action_href)
 values('order:'||new.id::text||':created','new_order','Nuevo pedido CAN-'||lpad(new.order_number::text,6,'0'),'Entró un pedido por $'||to_char(new.total,'FM999999990.00')||'.','order',new.id::text,'/admin/delivery?order='||new.id::text)
 on conflict(event_key) do nothing;
 return new;
end $$;
drop trigger if exists notify_admin_new_order on public.orders;
create trigger notify_admin_new_order after insert on public.orders for each row execute function private.notify_admin_new_order();
insert into public.admin_notifications(event_key,type,title,description,entity_type,entity_id,action_href,created_at)
select 'order:'||o.id::text||':created','new_order','Nuevo pedido CAN-'||lpad(o.order_number::text,6,'0'),'Entró un pedido por $'||to_char(o.total,'FM999999990.00')||'.','order',o.id::text,'/admin/delivery?order='||o.id::text,o.created_at
from public.orders o on conflict(event_key) do nothing;

-- Loyalty levels are assigned exclusively on customer rows.
create or replace function private.assign_customer_level()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_level uuid;
begin
 select l.id into v_level from public.customer_levels l where l.min_lifetime_points<=new.lifetime_points order by l.min_lifetime_points desc,l.sort_order desc limit 1;
 if v_level is not null then new.level_id:=v_level; end if;
 return new;
end $$;
drop trigger if exists assign_customer_level on public.customers;
create trigger assign_customer_level before insert or update of lifetime_points on public.customers for each row execute function private.assign_customer_level();
update public.customers c set level_id=(select cl.id from public.customer_levels cl where cl.min_lifetime_points<=c.lifetime_points order by cl.min_lifetime_points desc,cl.sort_order desc limit 1)
where c.level_id is distinct from (select cl.id from public.customer_levels cl where cl.min_lifetime_points<=c.lifetime_points order by cl.min_lifetime_points desc,cl.sort_order desc limit 1);
do $$begin alter publication supabase_realtime add table public.admin_notifications;exception when duplicate_object then null;end$$;
