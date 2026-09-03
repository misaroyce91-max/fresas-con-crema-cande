-- Fresas 7: non-sending WhatsApp copilot foundation.
-- Additive only. Meta Business Agent remains the sole active agent.
create table if not exists public.whatsapp_integration_settings (
  id text primary key default 'main',
  current_agent text not null default 'META_BUSINESS_AGENT',
  mode text not null default 'copilot' check(mode in('copilot','test','active')),
  coexistence_status text not null default 'unverified' check(coexistence_status in('unverified','eligible','ineligible','approved')),
  webhook_enabled boolean not null default false,
  outbound_enabled boolean not null default false,
  automatic_replies_enabled boolean not null default false,
  test_numbers text[] not null default '{}',
  weekly_promotion_limit integer not null default 2 check(weekly_promotion_limit between 0 and 7),
  minimum_hours_between_messages integer not null default 48 check(minimum_hours_between_messages between 1 and 720),
  allowed_start time not null default '10:00', allowed_end time not null default '19:00',
  updated_at timestamptz not null default now(), updated_by uuid references auth.users(id),
  check(not automatic_replies_enabled or (mode='active' and coexistence_status='approved' and webhook_enabled and outbound_enabled))
);
create table if not exists public.whatsapp_consents (
  id uuid primary key default gen_random_uuid(), customer_id uuid references public.customers(id) on delete set null,
  phone text not null, marketing_opt_in boolean not null default false,
  service_messages_allowed boolean not null default true,
  source text not null check(source in('checkout','account','whatsapp','store','admin','import')),
  consent_text text, consented_at timestamptz, opted_out_at timestamptz, opt_out_keyword text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(phone)
);
create table if not exists public.whatsapp_templates (
  id uuid primary key default gen_random_uuid(), meta_template_id text unique, name text not null,
  language text not null default 'es_MX', category text not null check(category in('MARKETING','UTILITY','AUTHENTICATION')),
  body text not null, media_type text check(media_type in('IMAGE','VIDEO','DOCUMENT')),
  status text not null default 'draft' check(status in('draft','submitted','approved','rejected','paused','disabled')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(name,language)
);
create table if not exists public.whatsapp_campaigns (
  id uuid primary key default gen_random_uuid(), name text not null, objective text not null,
  segment jsonb not null default '{}'::jsonb, message text not null, media_url text,
  template_id uuid references public.whatsapp_templates(id), promotion_id uuid references public.promotions(id),
  scheduled_at timestamptz, frequency text not null default 'once', valid_until timestamptz,
  send_limit integer not null default 0 check(send_limit>=0),
  status text not null default 'draft' check(status in('draft','pending_approval','approved','scheduled','active','paused','finished','cancelled')),
  audience_count integer not null default 0, estimated_cost numeric(12,2) not null default 0,
  sent_count integer not null default 0, delivered_count integer not null default 0,
  read_count integer not null default 0, reply_count integer not null default 0,
  opt_out_count integer not null default 0, attributed_orders integer not null default 0,
  attributed_sales numeric(12,2) not null default 0, estimated_profit numeric(12,2) not null default 0,
  approved_by uuid references auth.users(id), approved_at timestamptz,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.whatsapp_conversations (
  id uuid primary key default gen_random_uuid(), customer_id uuid references public.customers(id) on delete set null,
  phone text not null, status text not null default 'new' check(status in('new','ai_assisting','waiting_customer','human_required','order_created','resolved','closed')),
  intent text, cart jsonb, order_id uuid references public.orders(id) on delete set null,
  assigned_to uuid references auth.users(id), automation_paused boolean not null default true,
  campaign_id uuid references public.whatsapp_campaigns(id) on delete set null,
  last_message_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.whatsapp_messages (
  id uuid primary key default gen_random_uuid(), external_message_id text unique,
  conversation_id uuid not null references public.whatsapp_conversations(id) on delete cascade,
  direction text not null check(direction in('inbound','outbound')),
  sender_type text not null check(sender_type in('customer','meta_agent','cande_copilot','human','system')),
  message_type text not null default 'text', body text, payload jsonb not null default '{}'::jsonb,
  status text not null default 'received', created_at timestamptz not null default now()
);
create table if not exists public.whatsapp_event_log (
  id uuid primary key default gen_random_uuid(), event_key text not null unique,
  event_type text not null, source text not null, campaign_id uuid references public.whatsapp_campaigns(id) on delete set null,
  conversation_id uuid references public.whatsapp_conversations(id) on delete set null,
  success boolean not null default true, error_code text, metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists whatsapp_consents_customer_idx on public.whatsapp_consents(customer_id);
create index if not exists whatsapp_campaigns_status_schedule_idx on public.whatsapp_campaigns(status,scheduled_at);
create index if not exists whatsapp_conversations_status_last_idx on public.whatsapp_conversations(status,last_message_at desc);
create index if not exists whatsapp_messages_conversation_idx on public.whatsapp_messages(conversation_id,created_at);
create index if not exists whatsapp_settings_updated_by_idx on public.whatsapp_integration_settings(updated_by);
create index if not exists whatsapp_campaigns_template_idx on public.whatsapp_campaigns(template_id);
create index if not exists whatsapp_campaigns_promotion_idx on public.whatsapp_campaigns(promotion_id);
create index if not exists whatsapp_campaigns_approved_by_idx on public.whatsapp_campaigns(approved_by);
create index if not exists whatsapp_campaigns_created_by_idx on public.whatsapp_campaigns(created_by);
create index if not exists whatsapp_conversations_customer_idx on public.whatsapp_conversations(customer_id);
create index if not exists whatsapp_conversations_order_idx on public.whatsapp_conversations(order_id);
create index if not exists whatsapp_conversations_assigned_idx on public.whatsapp_conversations(assigned_to);
create index if not exists whatsapp_conversations_campaign_idx on public.whatsapp_conversations(campaign_id);
create index if not exists whatsapp_event_campaign_idx on public.whatsapp_event_log(campaign_id);
create index if not exists whatsapp_event_conversation_idx on public.whatsapp_event_log(conversation_id);

alter table public.whatsapp_integration_settings enable row level security;
alter table public.whatsapp_consents enable row level security;
alter table public.whatsapp_templates enable row level security;
alter table public.whatsapp_campaigns enable row level security;
alter table public.whatsapp_conversations enable row level security;
alter table public.whatsapp_messages enable row level security;
alter table public.whatsapp_event_log enable row level security;
do $$declare t text;begin foreach t in array array['whatsapp_integration_settings','whatsapp_consents','whatsapp_templates','whatsapp_campaigns','whatsapp_conversations','whatsapp_messages','whatsapp_event_log'] loop execute format('drop policy if exists whatsapp_admin_all on public.%I',t);execute format('create policy whatsapp_admin_all on public.%I for all to authenticated using (private.is_admin()) with check (private.is_admin())',t);end loop;end$$;
grant select,insert,update on public.whatsapp_integration_settings,public.whatsapp_consents,public.whatsapp_templates,public.whatsapp_campaigns,public.whatsapp_conversations,public.whatsapp_messages,public.whatsapp_event_log to authenticated;

insert into public.whatsapp_integration_settings(id,current_agent,mode,coexistence_status,webhook_enabled,outbound_enabled,automatic_replies_enabled)
values('main','META_BUSINESS_AGENT','copilot','unverified',false,false,false)
on conflict(id) do update set current_agent='META_BUSINESS_AGENT',mode='copilot',coexistence_status='unverified',webhook_enabled=false,outbound_enabled=false,automatic_replies_enabled=false,updated_at=now();

create or replace function public.admin_set_whatsapp_campaign_status(p_campaign_id uuid,p_status text)
returns public.whatsapp_campaigns language plpgsql security invoker set search_path='public','private' as $$
declare v_campaign public.whatsapp_campaigns;v_outbound boolean;
begin
 if not private.is_admin() then raise exception 'ADMIN_REQUIRED';end if;
 if p_status not in('draft','pending_approval','approved','paused','cancelled') then raise exception 'STATUS_NOT_AVAILABLE_IN_COPILOT_MODE';end if;
 select outbound_enabled into v_outbound from public.whatsapp_integration_settings where id='main';
 if p_status='approved' and coalesce(v_outbound,false) then raise exception 'OUTBOUND_MUST_REMAIN_DISABLED_UNTIL_COEXISTENCE_IS_VERIFIED';end if;
 update public.whatsapp_campaigns set status=p_status,approved_by=case when p_status='approved' then auth.uid() else approved_by end,approved_at=case when p_status='approved' then now() else approved_at end,updated_at=now() where id=p_campaign_id returning * into v_campaign;
 insert into public.audit_events(actor_id,event_type,entity_type,entity_id,reason,new_value) values(auth.uid(),'whatsapp_campaign_status','whatsapp_campaign',p_campaign_id::text,'Copilot: sin envío automático',jsonb_build_object('status',p_status));
 return v_campaign;
end$$;
revoke all on function public.admin_set_whatsapp_campaign_status(uuid,text) from public,anon;
grant execute on function public.admin_set_whatsapp_campaign_status(uuid,text) to authenticated;
