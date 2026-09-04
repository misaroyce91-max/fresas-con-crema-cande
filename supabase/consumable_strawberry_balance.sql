-- Fresas 11: saldo consumible, ledger auditable e idempotencia completa.
-- Migración no destructiva: conserva saldos y movimientos existentes.

alter table public.points_transactions add column if not exists balance_before integer;
alter table public.points_transactions add column if not exists reward_id uuid references public.rewards(id);
alter table public.points_transactions add column if not exists redemption_id uuid references public.reward_redemptions(id);
alter table public.points_transactions add column if not exists idempotency_key uuid;
alter table public.points_transactions add column if not exists created_by uuid references auth.users(id);
alter table public.reward_redemptions add column if not exists refunded_at timestamptz;
alter table public.reward_redemptions add column if not exists refund_transaction_id uuid references public.points_transactions(id);

update public.points_transactions
set balance_before=balance_after-points
where balance_before is null;

alter table public.points_transactions alter column balance_before set not null;
alter table public.points_transactions drop constraint if exists points_transactions_type_check;
alter table public.points_transactions add constraint points_transactions_type_check
 check(type in('earn','redeem','refund','adjustment','expired','expiration'));
alter table public.points_transactions drop constraint if exists points_transactions_balance_math_check;
alter table public.points_transactions add constraint points_transactions_balance_math_check
 check(balance_after=balance_before+points);

create index if not exists points_transactions_reward_idx on public.points_transactions(reward_id);
create index if not exists points_transactions_redemption_idx on public.points_transactions(redemption_id);
create index if not exists points_transactions_created_by_idx on public.points_transactions(created_by);
create unique index if not exists points_transactions_idempotency_uidx
 on public.points_transactions(customer_id,idempotency_key) where idempotency_key is not null;
create unique index if not exists points_transactions_redemption_redeem_uidx
 on public.points_transactions(redemption_id) where type='redeem' and redemption_id is not null;
create unique index if not exists points_transactions_redemption_refund_uidx
 on public.points_transactions(redemption_id) where type='refund' and redemption_id is not null;
create unique index if not exists reward_redemptions_refund_transaction_uidx
 on public.reward_redemptions(refund_transaction_id) where refund_transaction_id is not null;

create or replace function private.protect_strawberry_balance()
returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in('anon','authenticated') and
   (new.points_balance is distinct from old.points_balance or new.lifetime_points is distinct from old.lifetime_points)
 then raise exception 'BALANCE_BACKEND_ONLY'; end if;
 return new;
end$$;
drop trigger if exists protect_strawberry_balance on public.customers;
create trigger protect_strawberry_balance before update on public.customers
 for each row execute function private.protect_strawberry_balance();

create or replace function private.protect_strawberry_ledger()
returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in('anon','authenticated') then raise exception 'LEDGER_IMMUTABLE'; end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end$$;
drop trigger if exists protect_strawberry_ledger on public.points_transactions;
create trigger protect_strawberry_ledger before update or delete on public.points_transactions
 for each row execute function private.protect_strawberry_ledger();

revoke insert,update,delete on public.points_transactions from anon,authenticated;
revoke all on function public.admin_adjust_customer_strawberries(uuid,integer,text) from public,anon,authenticated;
revoke all on function private.redeem_reward_impl(uuid) from public,anon,authenticated;

create or replace function private.redeem_reward_impl(p_reward_id uuid,p_client_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();c public.customers;rw public.rewards;rr public.reward_redemptions;before_balance integer;after_balance integer;tx_id uuid;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if p_client_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;
 select * into c from public.customers where id=u for update;
 if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 select * into rr from public.reward_redemptions where customer_id=u and client_request_id=p_client_request_id;
 if found then
  select * into rw from public.rewards where id=rr.reward_id;
  return jsonb_build_object('id',rr.id,'reward',rw.name,'pointsSpent',rr.points_spent,'balance',c.points_balance,'duplicate',true,'rewardType',rw.reward_type,'discountValue',rw.reward_value,'productId',rw.product_id,'sizeName',rw.size_name);
 end if;
 select * into rw from public.rewards where id=p_reward_id and active and not claim_only for share;
 if not found then raise exception 'REWARD_NOT_AVAILABLE';end if;
 if rw.points_cost<=0 then raise exception 'INVALID_REWARD_COST';end if;
 if c.points_balance<rw.points_cost then raise exception 'INSUFFICIENT_POINTS';end if;
 if rw.reward_type='free_product' and(rw.product_id is null or rw.size_name is null)then raise exception 'REWARD_PRODUCT_NOT_CONFIGURED';end if;
 before_balance:=c.points_balance;after_balance:=before_balance-rw.points_cost;
 insert into public.reward_redemptions(customer_id,reward_id,points_spent,client_request_id)
 values(u,rw.id,rw.points_cost,p_client_request_id) returning * into rr;
 update public.customers set points_balance=after_balance,updated_at=now() where id=u;
 insert into public.points_transactions(customer_id,type,points,balance_before,balance_after,reward_id,redemption_id,idempotency_key,description)
 values(u,'redeem',-rw.points_cost,before_balance,after_balance,rw.id,rr.id,p_client_request_id,'Canje: '||rw.name) returning id into tx_id;
 return jsonb_build_object('id',rr.id,'transactionId',tx_id,'reward',rw.name,'pointsSpent',rw.points_cost,'balanceBefore',before_balance,'balance',after_balance,'duplicate',false,'rewardType',rw.reward_type,'discountValue',rw.reward_value,'productId',rw.product_id,'sizeName',rw.size_name);
end$$;

create or replace function public.admin_refund_strawberries(p_redemption_id uuid,p_idempotency_key uuid,p_description text default 'Reembolso administrativo')
returns jsonb language plpgsql security definer set search_path='' as $$
declare admin_id uuid:=auth.uid();rr public.reward_redemptions;c public.customers;rw public.rewards;existing public.points_transactions;before_balance integer;after_balance integer;tx_id uuid;
begin
 if admin_id is null or not private.is_admin() then raise exception 'ADMIN_REQUIRED';end if;
 if p_idempotency_key is null then raise exception 'REQUEST_ID_REQUIRED';end if;
 select * into rr from public.reward_redemptions where id=p_redemption_id for update;
 if not found then raise exception 'REDEMPTION_NOT_FOUND';end if;
 select * into c from public.customers where id=rr.customer_id for update;
 select * into existing from public.points_transactions where customer_id=rr.customer_id and idempotency_key=p_idempotency_key;
 if found then return jsonb_build_object('transactionId',existing.id,'balance',existing.balance_after,'duplicate',true);end if;
 if rr.refund_transaction_id is not null or exists(select 1 from public.points_transactions where redemption_id=rr.id and type='refund')then raise exception 'ALREADY_REFUNDED';end if;
 if rr.points_spent<=0 then raise exception 'NOTHING_TO_REFUND';end if;
 select * into rw from public.rewards where id=rr.reward_id;
 before_balance:=c.points_balance;after_balance:=before_balance+rr.points_spent;
 update public.customers set points_balance=after_balance,updated_at=now() where id=c.id;
 insert into public.points_transactions(customer_id,type,points,balance_before,balance_after,reward_id,redemption_id,idempotency_key,description,created_by)
 values(c.id,'refund',rr.points_spent,before_balance,after_balance,rr.reward_id,rr.id,p_idempotency_key,coalesce(nullif(trim(p_description),''),'Reembolso: '||coalesce(rw.name,'recompensa')),admin_id) returning id into tx_id;
 update public.reward_redemptions set status='cancelled',refunded_at=now(),refund_transaction_id=tx_id where id=rr.id;
 return jsonb_build_object('transactionId',tx_id,'pointsRefunded',rr.points_spent,'balanceBefore',before_balance,'balance',after_balance,'duplicate',false);
end$$;

create or replace function public.admin_adjust_strawberries(p_customer_id uuid,p_points integer,p_idempotency_key uuid,p_description text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare admin_id uuid:=auth.uid();c public.customers;existing public.points_transactions;before_balance integer;after_balance integer;tx_id uuid;
begin
 if admin_id is null or not private.is_admin() then raise exception 'ADMIN_REQUIRED';end if;
 if p_idempotency_key is null then raise exception 'REQUEST_ID_REQUIRED';end if;
 if p_points=0 or p_points is null then raise exception 'INVALID_ADJUSTMENT';end if;
 if nullif(trim(p_description),'') is null then raise exception 'DESCRIPTION_REQUIRED';end if;
 select * into c from public.customers where id=p_customer_id for update;
 if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 select * into existing from public.points_transactions where customer_id=c.id and idempotency_key=p_idempotency_key;
 if found then return jsonb_build_object('transactionId',existing.id,'balance',existing.balance_after,'duplicate',true);end if;
 before_balance:=c.points_balance;after_balance:=before_balance+p_points;
 if after_balance<0 then raise exception 'INSUFFICIENT_POINTS';end if;
 update public.customers set points_balance=after_balance,updated_at=now() where id=c.id;
 insert into public.points_transactions(customer_id,type,points,balance_before,balance_after,idempotency_key,description,created_by)
 values(c.id,'adjustment',p_points,before_balance,after_balance,p_idempotency_key,trim(p_description),admin_id) returning id into tx_id;
 return jsonb_build_object('transactionId',tx_id,'points',p_points,'balanceBefore',before_balance,'balance',after_balance,'duplicate',false);
end$$;

create or replace function private.award_order_strawberries()
returns trigger language plpgsql security definer set search_path='' as $$
declare rate numeric;mult numeric;pts int;before_balance int;after_balance int;
begin
 if new.status='cancelled'or new.customer_id is null then return new;end if;
 if new.points_awarded_at is not null or exists(select 1 from public.points_transactions where order_id=new.id and type='earn')then return new;end if;
 if not(new.status='delivered'or new.payment_status='paid')then return new;end if;
 select points_per_peso,multiplier into rate,mult from public.point_rules where active and(starts_at is null or starts_at<=now())and(ends_at is null or ends_at>=now())order by multiplier desc,points_per_peso desc limit 1;
 pts:=floor(new.total*coalesce(rate,0)*coalesce(mult,1));
 select points_balance into before_balance from public.customers where id=new.customer_id for update;
 after_balance:=before_balance+pts;
 update public.customers set points_balance=after_balance,lifetime_points=lifetime_points+pts,updated_at=now()where id=new.customer_id;
 new.points_earned:=pts;new.points_awarded_at:=now();
 insert into public.points_transactions(customer_id,order_id,type,points,balance_before,balance_after,description)
 values(new.customer_id,new.id,'earn',pts,before_balance,after_balance,'Fresas Cande por pedido CAN-'||lpad(new.order_number::text,6,'0'))on conflict(order_id,type)do nothing;
 update public.promotion_redemptions set status='used',used_at=now()where order_id=new.id and status='reserved';
 return new;
end$$;

revoke all on function public.admin_refund_strawberries(uuid,uuid,text) from public,anon;
revoke all on function public.admin_adjust_strawberries(uuid,integer,uuid,text) from public,anon;
grant execute on function public.admin_refund_strawberries(uuid,uuid,text) to authenticated;
grant execute on function public.admin_adjust_strawberries(uuid,integer,uuid,text) to authenticated;
revoke all on function private.redeem_reward_impl(uuid,uuid) from public,anon;
grant execute on function private.redeem_reward_impl(uuid,uuid) to authenticated;
