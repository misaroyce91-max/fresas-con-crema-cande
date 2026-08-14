export type Product = { id:string; name:string; description:string; image:string; badge?:string; prices:Record<string,number> }
export type Promotion = { id:string; eyebrow:string; title:string; description:string; image:string; startsAt:string; endsAt:string; ctaHref:string }
export const sizes = ['10 oz','12 oz','16 oz']
export const products: Product[] = [
  {id:'classic',name:'Clásicas',description:'Fresas frescas, crema de la casa y un toque de amor Cande.',image:'/images/cande-classic.png',badge:'La favorita',prices:{'10 oz':80,'12 oz':95,'16 oz':115}},
  {id:'oreo',name:'Oreo',description:'Crema suave, fresas y abundante galleta de chocolate.',image:'/images/cande-oreo.png',prices:{'10 oz':90,'12 oz':105,'16 oz':120}},
  {id:'kinder-bueno',name:'Kinder Bueno',description:'Fresas, crema, avellana y crujientes trozos de wafer.',image:'/images/cande-special.png',badge:'Especial',prices:{'10 oz':95,'12 oz':110,'16 oz':120}},
  {id:'kinder-delice',name:'Kinder Delice',description:'Chocolate, pastelito suave y nuestra crema artesanal.',image:'/images/cande-special.png',prices:{'10 oz':95,'12 oz':110,'16 oz':120}},
  {id:'nutella',name:'Nutella',description:'La combinación intensa de avellana, crema y fresa.',image:'/images/cande-classic.png',prices:{'10 oz':95,'12 oz':110,'16 oz':120}},
  {id:'ferrero',name:'Ferrero',description:'Un antojo premium con avellana, chocolate y textura crujiente.',image:'/images/cande-special.png',prices:{'10 oz':88,'12 oz':102,'16 oz':132}},
  {id:'carlos-v',name:'Carlos V',description:'Chocolate con leche en trocitos sobre fresas muy frescas.',image:'/images/cande-oreo.png',prices:{'10 oz':90,'12 oz':105,'16 oz':120}},
]
export const toppings = [{name:'Chocoretas',price:10},{name:'Krankys',price:10},{name:'Chispas de chocolate',price:10},{name:'Leche condensada',price:10},{name:'Chocolate líquido',price:10},{name:'Extra crema',price:10}]
export const rewards = [{name:'Topping gratis',points:120,icon:'sparkles'},{name:'$20 de descuento',points:180,icon:'ticket'},{name:'Fresa clásica 10 oz gratis',points:300,icon:'gift'},{name:'Fresa especial gratis',points:450,icon:'crown'}]
export const promotions: Promotion[] = [
  {id:'double-points-august',eyebrow:'🍓 Promoción de hoy',title:'Hoy gana 2X puntos',description:'Haz tu pedido y avanza el doble hacia tu próxima recompensa Cande.',image:'/images/cande-special.png',startsAt:'2026-08-10T00:00:00-06:00',endsAt:'2026-08-18T23:59:59-06:00',ctaHref:'/menu'},
  {id:'couples-combo-july',eyebrow:'Combo Pareja',title:'Dos antojos saben mejor',description:'Una combinación especial para compartir.',image:'/images/cande-oreo.png',startsAt:'2026-07-01T00:00:00-06:00',endsAt:'2026-07-31T23:59:59-06:00',ctaHref:'/menu'},
]
export const money = (n:number) => new Intl.NumberFormat('es-MX',{style:'currency',currency:'MXN',maximumFractionDigits:0}).format(n)
