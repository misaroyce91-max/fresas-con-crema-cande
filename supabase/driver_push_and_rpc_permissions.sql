-- Privileged public entrypoints remain narrow and validate the caller inside
-- their private implementations. The private schema is never granted out.
create or replace function public.accept_delivery(p_request_id uuid)
returns public.delivery_assignments language sql security definer set search_path=''
as $$select private.accept_delivery_impl(p_request_id)$$;
create or replace function public.driver_availability(p_available boolean)
returns public.couriers language sql security definer set search_path=''
as $$select private.driver_availability_impl(p_available)$$;
create or replace function public.driver_update_delivery(p_assignment_id uuid,p_status text)
returns public.delivery_assignments language sql security definer set search_path=''
as $$select private.driver_update_delivery_impl(p_assignment_id,p_status)$$;
revoke all on function public.accept_delivery(uuid),public.driver_availability(boolean),public.driver_update_delivery(uuid,text) from public,anon;
grant execute on function public.accept_delivery(uuid),public.driver_availability(boolean),public.driver_update_delivery(uuid,text) to authenticated;

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  courier_id uuid not null references public.couriers(id) on delete cascade,
  endpoint text not null unique,
  subscription jsonb not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
drop policy if exists driver_manages_own_push on public.push_subscriptions;
create policy driver_manages_own_push on public.push_subscriptions
for all to authenticated
using (
  courier_id=(select id from public.couriers where user_id=(select auth.uid()) and active)
  and private.is_driver()
)
with check (
  courier_id=(select id from public.couriers where user_id=(select auth.uid()) and active)
  and private.is_driver()
);
grant select,insert,update,delete on public.push_subscriptions to authenticated;

create or replace function public.driver_push_public_key()
returns text language plpgsql security definer set search_path=''
as $$
begin
  if not private.is_driver() then raise exception 'DRIVER_REQUIRED'; end if;
  return 'BK6iYe_igsjipcGtVDtfE4R-cej35AflmkdxIv9XaKFQtSu9zp_OWINefjXaJAWYOFs8FW75pDhF3UXlhp93vTE';
end $$;
revoke all on function public.driver_push_public_key() from public,anon;
grant execute on function public.driver_push_public_key() to authenticated;

-- Only the service role used by the Edge Function may decrypt VAPID secrets.
create or replace function public.service_push_config()
returns table(public_key text,private_key text,subject text)
language plpgsql security definer set search_path=''
as $$
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  return query
  select
    max(decrypted_secret) filter(where name='cande_vapid_public'),
    max(decrypted_secret) filter(where name='cande_vapid_private'),
    max(decrypted_secret) filter(where name='cande_vapid_subject')
  from vault.decrypted_secrets
  where name in ('cande_vapid_public','cande_vapid_private','cande_vapid_subject');
end $$;
revoke all on function public.service_push_config() from public,anon,authenticated;
grant execute on function public.service_push_config() to service_role;
