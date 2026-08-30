-- Profiles reconstructed outside the Auth trigger still receive a permanent unique code.
alter table public.customers alter column referral_code
set default ('CAN' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)));
