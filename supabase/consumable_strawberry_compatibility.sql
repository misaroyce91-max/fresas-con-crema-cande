-- Compatibilidad no destructiva para la pantalla CRM existente.
-- Conserva la firma anterior, pero delega al único camino auditable.
create or replace function public.admin_adjust_customer_strawberries(
  p_customer_id uuid,
  p_delta integer,
  p_reason text
)
returns public.customers
language plpgsql
security invoker
set search_path = ''
as $$
declare
  result public.customers;
begin
  perform public.admin_adjust_strawberries(
    p_customer_id,
    p_delta,
    gen_random_uuid(),
    p_reason
  );

  select *
  into result
  from public.customers
  where id = p_customer_id;

  return result;
end
$$;

revoke all on function public.admin_adjust_customer_strawberries(uuid, integer, text)
  from public, anon;
grant execute on function public.admin_adjust_customer_strawberries(uuid, integer, text)
  to authenticated;
