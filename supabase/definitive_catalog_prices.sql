-- Definitive public catalog prices. Historical order_items remain unchanged.
begin;

with definitive_prices(product_id,size_name,price) as (
 values
  ('classic','10 oz',80::numeric),('classic','12 oz',95::numeric),('classic','16 oz',115::numeric),
  ('oreo','10 oz',90::numeric),('oreo','12 oz',105::numeric),('oreo','16 oz',120::numeric),
  ('carlos-v','10 oz',90::numeric),('carlos-v','12 oz',105::numeric),('carlos-v','16 oz',120::numeric),
  ('kinder-delice','10 oz',95::numeric),('kinder-delice','12 oz',110::numeric),('kinder-delice','16 oz',120::numeric),
  ('kinder-bueno','10 oz',95::numeric),('kinder-bueno','12 oz',110::numeric),('kinder-bueno','16 oz',120::numeric),
  ('nutella','10 oz',95::numeric),('nutella','12 oz',110::numeric),('nutella','16 oz',120::numeric)
)
update public.product_sizes ps set price=d.price,active=true
from definitive_prices d where ps.product_id=d.product_id and ps.name=d.size_name;

update public.product_sizes ps set active=false
from public.products p
where p.id=ps.product_id and p.active and ps.name not in ('10 oz','12 oz','16 oz');

update public.toppings set name='Krankys',price=10,active=true where name='Kranky';
update public.toppings set price=10,active=true where name in ('Chocoretas','Chispas de chocolate','Krankys');
insert into public.toppings(name,price,active)
values ('Leche condensada',10,true),('Chocolate líquido',10,true),('Extra crema',10,true)
on conflict(name) do update set price=excluded.price,active=true;
update public.toppings set active=false
where name not in ('Chocoretas','Krankys','Chispas de chocolate','Leche condensada','Chocolate líquido','Extra crema');

commit;
