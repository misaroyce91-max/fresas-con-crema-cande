-- Replace the existing points behavior with configurable Fresas Cande.
alter table public.orders add column if not exists points_awarded_at timestamptz;
alter table public.reward_redemptions add column if not exists order_id uuid references public.orders(id);
alter table public.reward_redemptions add column if not exists client_request_id uuid;
create unique index if not exists reward_redemptions_request_uidx on public.reward_redemptions(customer_id,client_request_id) where client_request_id is not null;
create index if not exists reward_redemptions_order_idx on public.reward_redemptions(order_id);
alter table public.rewards add column if not exists code text;
alter table public.rewards add column if not exists product_id text references public.products(id);
alter table public.rewards add column if not exists size_name text;
create unique index if not exists rewards_code_uidx on public.rewards(code) where code is not null;

-- Existing earned orders are historical and must never be credited a second time.
update public.orders o set points_awarded_at=coalesce(o.delivered_at,o.created_at)
where exists(select 1 from public.points_transactions pt where pt.order_id=o.id and pt.type='earn')
  and o.points_awarded_at is null;

update public.point_rules set points_per_peso=0.2,multiplier=1,active=true where name='Regla base';
update public.rewards set active=false;
insert into public.rewards(code,name,description,points_cost,reward_type,reward_value,product_id,size_name,active,sort_order)
values
 ('cande_50_discount','$50 MXN de descuento','Canjea 200 Fresas Cande por $50 MXN de descuento.',200,'fixed_discount',50,null,null,true,1),
 ('cande_classic_12_free','Clásicas 12 oz GRATIS','Disfruta unas Fresas con Crema Clásicas de 12 oz gratis.',300,'free_product',null,'classic','12 oz',true,2)
on conflict(code) where code is not null do update set name=excluded.name,description=excluded.description,
 points_cost=excluded.points_cost,reward_type=excluded.reward_type,reward_value=excluded.reward_value,
 product_id=excluded.product_id,size_name=excluded.size_name,active=true,sort_order=excluded.sort_order;

create or replace function private.redeem_reward_impl(p_reward_id uuid,p_client_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_customer public.customers;v_reward public.rewards;v_redemption public.reward_redemptions;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_client_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
 select rr.* into v_redemption from public.reward_redemptions rr where rr.customer_id=v_user and rr.client_request_id=p_client_request_id;
 if found then
  select * into v_reward from public.rewards where id=v_redemption.reward_id;
  return jsonb_build_object('id',v_redemption.id,'reward',v_reward.name,'balance',(select points_balance from public.customers where id=v_user),'duplicate',true,'rewardType',v_reward.reward_type,'discountValue',v_reward.reward_value,'productId',v_reward.product_id,'sizeName',v_reward.size_name);
 end if;
 select * into v_customer from public.customers where id=v_user for update;
 if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
 select * into v_reward from public.rewards where id=p_reward_id and active for share;
 if not found then raise exception 'REWARD_NOT_AVAILABLE'; end if;
 if v_customer.points_balance<v_reward.points_cost then raise exception 'INSUFFICIENT_POINTS'; end if;
 if v_reward.reward_type='free_product' and (v_reward.product_id is null or v_reward.size_name is null) then raise exception 'REWARD_PRODUCT_NOT_CONFIGURED'; end if;
 update public.customers set points_balance=points_balance-v_reward.points_cost,updated_at=now() where id=v_user;
 insert into public.reward_redemptions(customer_id,reward_id,points_spent,client_request_id)
 values(v_user,v_reward.id,v_reward.points_cost,p_client_request_id) returning * into v_redemption;
 insert into public.points_transactions(customer_id,type,points,balance_after,description)
 values(v_user,'redeem',-v_reward.points_cost,v_customer.points_balance-v_reward.points_cost,'Canje: '||v_reward.name);
 return jsonb_build_object('id',v_redemption.id,'reward',v_reward.name,'balance',v_customer.points_balance-v_reward.points_cost,'duplicate',false,'rewardType',v_reward.reward_type,'discountValue',v_reward.reward_value,'productId',v_reward.product_id,'sizeName',v_reward.size_name);
end $$;

drop function if exists public.redeem_reward(uuid);
create function public.redeem_reward(p_reward_id uuid,p_client_request_id uuid)
returns jsonb language sql security invoker set search_path='' as $$select private.redeem_reward_impl(p_reward_id,p_client_request_id)$$;
revoke all on function public.redeem_reward(uuid,uuid) from public,anon;
grant execute on function public.redeem_reward(uuid,uuid) to authenticated;
revoke all on function private.redeem_reward_impl(uuid,uuid) from public,anon;
grant execute on function private.redeem_reward_impl(uuid,uuid) to authenticated;

create or replace function private.place_order_impl(
 p_client_request_id uuid,p_items jsonb,p_delivery_type text,p_address jsonb,p_references text,p_notes text,p_payment_method text,p_redemption_ids uuid[]
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_customer public.customers;v_existing public.orders;v_order public.orders;v_item jsonb;
 v_product public.products;v_size public.product_sizes;v_topping jsonb;v_toppings jsonb;v_topping_total numeric(10,2);
 v_subtotal numeric(10,2):=0;v_shipping numeric(10,2):=0;v_discount numeric(10,2):=0;v_line numeric(10,2);v_quantity integer;
 v_rate numeric(10,4):=0;v_multiplier numeric(6,2):=1;v_pending integer:=0;v_redemption_id uuid;v_redemption public.reward_redemptions;v_reward public.rewards;v_has_free_item boolean;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
 if p_client_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
 if p_delivery_type not in ('delivery','pickup') then raise exception 'INVALID_DELIVERY_TYPE'; end if;
 if p_payment_method not in ('Efectivo','Transferencia / SPEI') then raise exception 'INVALID_PAYMENT_METHOD'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'EMPTY_ORDER'; end if;
 if cardinality(coalesce(p_redemption_ids,'{}'::uuid[]))<>(select count(distinct x) from unnest(coalesce(p_redemption_ids,'{}'::uuid[])) x) then raise exception 'DUPLICATE_REDEMPTION_ID'; end if;
 v_customer:=private.ensure_customer_profile(v_user);
 select * into v_customer from public.customers where id=v_user for update;
 select * into v_existing from public.orders where client_request_id=p_client_request_id;
 if found then
  if v_existing.customer_id<>v_user then raise exception 'REQUEST_ID_CONFLICT'; end if;
  select points_per_peso,multiplier into v_rate,v_multiplier from public.point_rules where active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>=now()) order by multiplier desc,points_per_peso desc limit 1;
  v_pending:=case when v_existing.points_awarded_at is not null then v_existing.points_earned else floor(v_existing.total*coalesce(v_rate,0)*coalesce(v_multiplier,1)) end;
  return jsonb_build_object('id',v_existing.id,'orderNumber',v_existing.order_number,'subtotal',v_existing.subtotal,'deliveryFee',v_existing.delivery_fee,'discount',v_existing.discount,'total',v_existing.total,'pointsEarned',v_existing.points_earned,'strawberriesPending',v_pending,'duplicate',true);
 end if;
 for v_item in select value from jsonb_array_elements(p_items) loop
  if nullif(v_item->>'redemptionId','') is not null then continue; end if;
  v_quantity:=greatest(1,least(50,coalesce((v_item->>'quantity')::integer,1)));
  select * into v_product from public.products where id=v_item->>'productId' and active and availability_status='active';
  if not found then raise exception 'PRODUCT_NOT_AVAILABLE'; end if;
  select * into v_size from public.product_sizes where product_id=v_product.id and name=v_item->>'size' and active;
  if not found then raise exception 'SIZE_NOT_AVAILABLE'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('name',t.name,'price',t.price) order by t.name),'[]'::jsonb),coalesce(sum(t.price),0)
   into v_toppings,v_topping_total from public.toppings t where t.active and t.name in(select jsonb_array_elements_text(coalesce(v_item->'toppingNames','[]'::jsonb)));
  v_subtotal:=v_subtotal+(v_size.price+v_topping_total)*v_quantity;
 end loop;
 if p_delivery_type='delivery' then select shipping_fee into v_shipping from public.store_settings where id='main'; end if;
 foreach v_redemption_id in array coalesce(p_redemption_ids,'{}'::uuid[]) loop
  select rr.* into v_redemption from public.reward_redemptions rr where rr.id=v_redemption_id and rr.customer_id=v_user and rr.status='available' for update;
  if not found then raise exception 'REDEMPTION_NOT_AVAILABLE'; end if;
  select * into v_reward from public.rewards where id=v_redemption.reward_id and active;
  if not found then raise exception 'REWARD_NOT_AVAILABLE'; end if;
  if v_reward.reward_type='fixed_discount' then v_discount:=v_discount+least(coalesce(v_reward.reward_value,0),greatest(0,v_subtotal-v_discount));
  elsif v_reward.reward_type='free_product' then
   select exists(select 1 from jsonb_array_elements(p_items) x where x->>'redemptionId'=v_redemption.id::text and x->>'productId'=v_reward.product_id and x->>'size'=v_reward.size_name and coalesce((x->>'quantity')::integer,1)=1) into v_has_free_item;
   if not v_has_free_item then raise exception 'FREE_REWARD_ITEM_MISSING'; end if;
  else raise exception 'UNSUPPORTED_REWARD_TYPE'; end if;
 end loop;
 select points_per_peso,multiplier into v_rate,v_multiplier from public.point_rules where active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>=now()) order by multiplier desc,points_per_peso desc limit 1;
 v_pending:=floor(greatest(0,v_subtotal+v_shipping-v_discount)*coalesce(v_rate,0)*coalesce(v_multiplier,1));
 insert into public.orders(client_request_id,customer_id,delivery_type,address,references_text,notes,payment_method,subtotal,delivery_fee,discount,total,points_earned)
 values(p_client_request_id,v_user,p_delivery_type,p_address,nullif(trim(p_references),''),nullif(trim(p_notes),''),p_payment_method,v_subtotal,v_shipping,v_discount,greatest(0,v_subtotal+v_shipping-v_discount),0) returning * into v_order;
 for v_item in select value from jsonb_array_elements(p_items) loop
  if nullif(v_item->>'redemptionId','') is not null then
   if not ((v_item->>'redemptionId')::uuid=any(coalesce(p_redemption_ids,'{}'::uuid[]))) then raise exception 'REDEMPTION_NOT_ATTACHED'; end if;
   select rr.* into v_redemption from public.reward_redemptions rr where rr.id=(v_item->>'redemptionId')::uuid and rr.customer_id=v_user and rr.status='available' for update;
   select * into v_reward from public.rewards where id=v_redemption.reward_id;
   if v_reward.reward_type<>'free_product' or v_item->>'productId'<>v_reward.product_id or v_item->>'size'<>v_reward.size_name then raise exception 'INVALID_FREE_REWARD_ITEM'; end if;
   select * into v_product from public.products where id=v_reward.product_id and active and availability_status='active';
   select * into v_size from public.product_sizes where product_id=v_product.id and name=v_reward.size_name and active;
   if v_product.id is null or v_size.id is null then raise exception 'REWARD_PRODUCT_NOT_AVAILABLE'; end if;
   insert into public.order_items(order_id,product_id,product_name,size_name,unit_price,quantity,toppings,line_total) values(v_order.id,v_product.id,v_product.name,v_size.name,0,1,'[]'::jsonb,0);
  else
   v_quantity:=greatest(1,least(50,coalesce((v_item->>'quantity')::integer,1)));
   select * into v_product from public.products where id=v_item->>'productId' and active;
   select * into v_size from public.product_sizes where product_id=v_product.id and name=v_item->>'size' and active;
   select coalesce(jsonb_agg(jsonb_build_object('name',t.name,'price',t.price) order by t.name),'[]'::jsonb),coalesce(sum(t.price),0) into v_toppings,v_topping_total from public.toppings t where t.active and t.name in(select jsonb_array_elements_text(coalesce(v_item->'toppingNames','[]'::jsonb)));
   v_line:=(v_size.price+v_topping_total)*v_quantity;
   insert into public.order_items(order_id,product_id,product_name,size_name,unit_price,quantity,toppings,line_total) values(v_order.id,v_product.id,v_product.name,v_size.name,v_size.price+v_topping_total,v_quantity,v_toppings,v_line);
  end if;
 end loop;
 update public.reward_redemptions set status='used',order_id=v_order.id,used_at=now() where id=any(coalesce(p_redemption_ids,'{}'::uuid[])) and customer_id=v_user and status='available';
 return jsonb_build_object('id',v_order.id,'orderNumber',v_order.order_number,'subtotal',v_order.subtotal,'deliveryFee',v_order.delivery_fee,'discount',v_order.discount,'total',v_order.total,'pointsEarned',0,'strawberriesPending',v_pending,'duplicate',false);
end $$;

drop function if exists public.place_order(uuid,jsonb,text,jsonb,text,text,text);
create function public.place_order(p_client_request_id uuid,p_items jsonb,p_delivery_type text,p_address jsonb,p_references text,p_notes text,p_payment_method text,p_redemption_ids uuid[] default '{}')
returns jsonb language sql security invoker set search_path='' as $$select private.place_order_impl(p_client_request_id,p_items,p_delivery_type,p_address,p_references,p_notes,p_payment_method,p_redemption_ids)$$;
revoke all on function public.place_order(uuid,jsonb,text,jsonb,text,text,text,uuid[]) from public,anon;
grant execute on function public.place_order(uuid,jsonb,text,jsonb,text,text,text,uuid[]) to authenticated;
revoke all on function private.place_order_impl(uuid,jsonb,text,jsonb,text,text,text,uuid[]) from public,anon;
grant execute on function private.place_order_impl(uuid,jsonb,text,jsonb,text,text,text,uuid[]) to authenticated;

create or replace function private.award_order_strawberries()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_rate numeric(10,4);v_multiplier numeric(6,2);v_points integer;v_balance integer;
begin
 if new.status='cancelled' then return new; end if;
 if new.points_awarded_at is not null or exists(select 1 from public.points_transactions where order_id=new.id and type='earn') then return new; end if;
 if not (new.status='delivered' or new.payment_status='paid') then return new; end if;
 select points_per_peso,multiplier into v_rate,v_multiplier from public.point_rules where active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>=now()) order by multiplier desc,points_per_peso desc limit 1;
 v_points:=floor(new.total*coalesce(v_rate,0)*coalesce(v_multiplier,1));
 update public.customers set points_balance=points_balance+v_points,lifetime_points=lifetime_points+v_points,updated_at=now() where id=new.customer_id returning points_balance into v_balance;
 new.points_earned:=v_points;new.points_awarded_at:=now();
 insert into public.points_transactions(customer_id,order_id,type,points,balance_after,description) values(new.customer_id,new.id,'earn',v_points,v_balance,'Fresas Cande por pedido CAN-'||lpad(new.order_number::text,6,'0')) on conflict(order_id,type) do nothing;
 return new;
end $$;
drop trigger if exists award_order_strawberries_on_completion on public.orders;
create trigger award_order_strawberries_on_completion before update of status,payment_status on public.orders for each row execute function private.award_order_strawberries();

create or replace function public.admin_save_strawberry_rule(p_pesos_per_strawberry numeric)
returns void language plpgsql security invoker set search_path='public','private' as $$begin if not private.is_admin() then raise exception 'ADMIN_REQUIRED';end if;if p_pesos_per_strawberry<=0 then raise exception 'INVALID_RATE';end if;update public.point_rules set active=false;update public.point_rules set points_per_peso=1/p_pesos_per_strawberry,multiplier=1,active=true where name='Regla base';if not found then insert into public.point_rules(name,points_per_peso,multiplier,active) values('Regla base',1/p_pesos_per_strawberry,1,true);end if;end$$;
revoke all on function public.admin_save_strawberry_rule(numeric) from public,anon;grant execute on function public.admin_save_strawberry_rule(numeric) to authenticated;

create or replace function public.admin_save_reward(p_data jsonb)
returns uuid language plpgsql security invoker set search_path='public','private' as $$declare v_id uuid;begin if not private.is_admin() then raise exception 'ADMIN_REQUIRED';end if;v_id:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());insert into public.rewards(id,code,name,description,points_cost,reward_type,reward_value,product_id,size_name,active,sort_order) values(v_id,nullif(p_data->>'code',''),p_data->>'name',coalesce(p_data->>'description',''),(p_data->>'points_cost')::integer,p_data->>'reward_type',nullif(p_data->>'reward_value','')::numeric,nullif(p_data->>'product_id',''),nullif(p_data->>'size_name',''),coalesce((p_data->>'active')::boolean,true),coalesce((p_data->>'sort_order')::integer,0)) on conflict(id) do update set name=excluded.name,description=excluded.description,points_cost=excluded.points_cost,reward_type=excluded.reward_type,reward_value=excluded.reward_value,product_id=excluded.product_id,size_name=excluded.size_name,active=excluded.active,sort_order=excluded.sort_order;return v_id;end$$;
revoke all on function public.admin_save_reward(jsonb) from public,anon;grant execute on function public.admin_save_reward(jsonb) to authenticated;

do $$begin alter publication supabase_realtime add table public.reward_redemptions;exception when duplicate_object then null;end$$;
