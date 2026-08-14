-- Server-authoritative order pricing. Product and topping prices are snapshotted in order_items.
create or replace function private.place_order_impl(
 p_client_request_id uuid,p_items jsonb,p_delivery_type text,p_address jsonb,p_references text,p_notes text,p_payment_method text,p_redemption_ids uuid[]
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_customer public.customers;v_existing public.orders;v_order public.orders;v_item jsonb;
 v_product public.products;v_size public.product_sizes;v_toppings jsonb;v_topping_total numeric(10,2);
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
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'price',t.price) order by t.name),'[]'::jsonb)
   into v_toppings from public.toppings t
   where t.active
    and (case when jsonb_array_length(coalesce(v_item->'toppingIds','[]'::jsonb))>0 then t.id::text in(select jsonb_array_elements_text(v_item->'toppingIds')) else t.name in(select jsonb_array_elements_text(coalesce(v_item->'toppingNames','[]'::jsonb))) end)
    and (not exists(select 1 from public.topping_products tp where tp.product_id=v_product.id) or exists(select 1 from public.topping_products tp where tp.product_id=v_product.id and tp.topping_id=t.id));
  select coalesce(sum((entry->>'price')::numeric),0) into v_topping_total from jsonb_array_elements(v_toppings) entry;
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
   select * into v_product from public.products where id=v_item->>'productId' and active and availability_status='active';
   select * into v_size from public.product_sizes where product_id=v_product.id and name=v_item->>'size' and active;
   select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.name,'price',t.price) order by t.name),'[]'::jsonb)
    into v_toppings from public.toppings t
    where t.active
     and (case when jsonb_array_length(coalesce(v_item->'toppingIds','[]'::jsonb))>0 then t.id::text in(select jsonb_array_elements_text(v_item->'toppingIds')) else t.name in(select jsonb_array_elements_text(coalesce(v_item->'toppingNames','[]'::jsonb))) end)
     and (not exists(select 1 from public.topping_products tp where tp.product_id=v_product.id) or exists(select 1 from public.topping_products tp where tp.product_id=v_product.id and tp.topping_id=t.id));
   select coalesce(sum((entry->>'price')::numeric),0) into v_topping_total from jsonb_array_elements(v_toppings) entry;
   v_line:=(v_size.price+v_topping_total)*v_quantity;
   insert into public.order_items(order_id,product_id,product_name,size_name,unit_price,quantity,toppings,line_total) values(v_order.id,v_product.id,v_product.name,v_size.name,v_size.price,v_quantity,v_toppings,v_line);
  end if;
 end loop;
 update public.reward_redemptions set status='used',order_id=v_order.id,used_at=now() where id=any(coalesce(p_redemption_ids,'{}'::uuid[])) and customer_id=v_user and status='available';
 return jsonb_build_object('id',v_order.id,'orderNumber',v_order.order_number,'subtotal',v_order.subtotal,'deliveryFee',v_order.delivery_fee,'discount',v_order.discount,'total',v_order.total,'pointsEarned',0,'strawberriesPending',v_pending,'duplicate',false);
end $$;
