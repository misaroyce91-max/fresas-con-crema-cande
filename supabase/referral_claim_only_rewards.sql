-- Keep referral entitlements out of the points catalog while preserving the existing reward/order flow.
alter table public.rewards add column if not exists claim_only boolean not null default false;

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

create or replace function private.claim_referral_reward_impl(p_referral_id uuid,p_product_id text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare u uuid:=auth.uid();r public.referrals;s public.referral_settings;p public.products;rw public.rewards;rd public.reward_redemptions;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 select * into r from public.referrals where id=p_referral_id and referrer_id=u for update;if not found then raise exception 'REFERRAL_NOT_FOUND';end if;
 if r.reward_redemption_id is not null then select * into rd from public.reward_redemptions where id=r.reward_redemption_id;return jsonb_build_object('id',rd.id,'duplicate',true);end if;
 if r.status<>'QUALIFIED' then raise exception 'REWARD_NOT_AVAILABLE';end if;
 select * into s from public.referral_settings where id='main' and active;if not found or not(p_product_id=any(s.eligible_product_ids))then raise exception 'PRODUCT_NOT_ELIGIBLE';end if;
 select p0.* into p from public.products p0 join public.product_sizes ps on ps.product_id=p0.id and ps.name=s.reward_size_name and ps.active where p0.id=p_product_id and p0.active and p0.availability_status='active';if not found then raise exception 'PRODUCT_NOT_AVAILABLE';end if;
 select * into rw from public.rewards where code='REFERRAL_'||upper(replace(p.id,'-','_'))limit 1;
 if not found then insert into public.rewards(name,description,points_cost,reward_type,active,sort_order,code,product_id,size_name,claim_only)values('Referido: '||p.name||' '||s.reward_size_name,'Premio por invitar a un amigo',1,'free_product',true,-10,'REFERRAL_'||upper(replace(p.id,'-','_')),p.id,s.reward_size_name,true)returning * into rw;end if;
 insert into public.reward_redemptions(customer_id,reward_id,points_spent,status,client_request_id)values(u,rw.id,0,'available',gen_random_uuid())returning * into rd;
 update public.referrals set status='REWARD_CREATED',reward_redemption_id=rd.id,reward_created_at=now(),updated_at=now()where id=r.id;
 return jsonb_build_object('id',rd.id,'rewardId',rw.id,'productId',p.id,'productName',p.name,'sizeName',s.reward_size_name,'duplicate',false);
end
$$;
