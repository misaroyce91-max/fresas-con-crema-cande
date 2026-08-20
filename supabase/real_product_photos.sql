begin;

update public.products
set image_url = case id
  when 'classic' then '/images/products/clasicas.jpg'
  when 'oreo' then '/images/products/oreo.jpg'
  when 'kinder-bueno' then '/images/products/kinder-bueno.jpg'
  when 'kinder-delice' then '/images/products/kinder-delice.jpg'
  when 'nutella' then '/images/products/nutella.jpg'
  else image_url
end
where id in ('classic', 'oreo', 'kinder-bueno', 'kinder-delice', 'nutella');

commit;
