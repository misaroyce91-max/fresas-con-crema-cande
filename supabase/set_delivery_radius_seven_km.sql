-- Keep the configured delivery coverage aligned across environments.
do $$
begin
  update public.delivery_rate_settings
     set max_distance_km = 7,
         updated_at = now()
   where id = 'main'
     and max_distance_km is distinct from 7;

  if not exists (
    select 1
      from public.delivery_rate_settings
     where id = 'main'
       and max_distance_km = 7
  ) then
    raise exception 'Could not set the delivery radius to 7 km';
  end if;
end
$$;
