-- Daily inventory operations: purchases and idempotent consumption on delivery.
alter table public.orders add column if not exists inventory_deducted_at timestamptz;

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  inventory_item_id uuid not null references public.inventory_items(id),
  order_id uuid references public.orders(id),
  movement_type text not null check (movement_type in ('purchase','consumption','adjustment')),
  quantity numeric(12,3) not null check (quantity <> 0),
  unit_cost numeric(12,4) not null default 0 check (unit_cost >= 0),
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists inventory_movements_item_created_idx on public.inventory_movements(inventory_item_id,created_at desc);
create unique index if not exists inventory_consumption_order_item_idx on public.inventory_movements(order_id,inventory_item_id,movement_type) where order_id is not null and movement_type='consumption';
alter table public.inventory_movements enable row level security;
drop policy if exists admin_inventory_movements_all on public.inventory_movements;
create policy admin_inventory_movements_all on public.inventory_movements for all to authenticated using (private.is_admin()) with check (private.is_admin());
grant select,insert on public.inventory_movements to authenticated;

create or replace function public.admin_record_inventory_purchase(p_item_id uuid,p_quantity numeric,p_unit_cost numeric,p_notes text default null)
returns public.inventory_items language plpgsql security invoker set search_path='public','private' as $$
declare v_item public.inventory_items;
begin
 if not private.is_admin() then raise exception 'ADMIN_REQUIRED'; end if;
 if p_quantity<=0 or p_unit_cost<0 then raise exception 'INVALID_PURCHASE'; end if;
 update public.inventory_items set stock_quantity=stock_quantity+p_quantity,unit_cost=p_unit_cost,updated_at=now() where id=p_item_id returning * into v_item;
 if not found then raise exception 'INVENTORY_ITEM_NOT_FOUND'; end if;
 insert into public.inventory_movements(inventory_item_id,movement_type,quantity,unit_cost,notes,created_by) values(p_item_id,'purchase',p_quantity,p_unit_cost,nullif(trim(p_notes),''),auth.uid());
 return v_item;
end $$;
revoke all on function public.admin_record_inventory_purchase(uuid,numeric,numeric,text) from public,anon;
grant execute on function public.admin_record_inventory_purchase(uuid,numeric,numeric,text) to authenticated;

create or replace function private.deduct_delivered_order_inventory()
returns trigger language plpgsql security definer set search_path='' as $$
declare v record;
begin
 if new.status<>'delivered' or new.inventory_deducted_at is not null then return new; end if;
 for v in
  select pri.inventory_item_id,sum(pri.quantity*oi.quantity)::numeric(12,3) quantity
  from public.order_items oi join public.product_recipe_items pri on pri.product_id=oi.product_id and pri.size_name=oi.size_name
  where oi.order_id=new.id group by pri.inventory_item_id
 loop
  update public.inventory_items set stock_quantity=stock_quantity-v.quantity,updated_at=now() where id=v.inventory_item_id and stock_quantity>=v.quantity;
  if not found then raise exception 'INSUFFICIENT_INVENTORY:%',v.inventory_item_id; end if;
  insert into public.inventory_movements(inventory_item_id,order_id,movement_type,quantity,unit_cost,notes)
  select v.inventory_item_id,new.id,'consumption',-v.quantity,unit_cost,'Consumo pedido CAN-'||lpad(new.order_number::text,6,'0') from public.inventory_items where id=v.inventory_item_id
  on conflict(order_id,inventory_item_id,movement_type) where order_id is not null and movement_type='consumption' do nothing;
 end loop;
 new.inventory_deducted_at=now();
 return new;
end $$;
drop trigger if exists deduct_inventory_on_delivery on public.orders;
create trigger deduct_inventory_on_delivery before update of status on public.orders for each row execute function private.deduct_delivered_order_inventory();
