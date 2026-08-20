begin;
alter function public.admin_expansion_dashboard(integer,numeric) security invoker;
alter function public.admin_save_expansion_config(jsonb) security invoker;
create index if not exists branches_updated_by_idx on public.branches(updated_by);
create index if not exists expansion_config_updated_by_idx on public.expansion_config(updated_by);
commit;
