'use client'
import Image from 'next/image'
import Link from 'next/link'
import {ArrowLeft,Gift,Minus,Plus,ShoppingBag,X} from 'lucide-react'
import {useCart} from '@/components/cart-provider'
import {useStore} from '@/components/store-provider'
import {money} from '@/lib/data'

export default function Cart(){
 const{items,redemptions,update,removeRedemption,subtotal,rewardDiscount}=useCart()
 const{config}=useStore()
 const shipping=subtotal?config.shippingFee:0,discount=Math.min(subtotal,rewardDiscount),total=subtotal+shipping-discount
 return <main className="page max-w-3xl">
  <header className="flex items-center gap-4"><Link href="/menu" className="grid h-10 w-10 place-items-center rounded-full bg-cande-50"><ArrowLeft size={20}/></Link><div><p className="text-xs font-bold uppercase text-cande-500">Tu selección</p><h1 className="text-2xl font-black">Carrito</h1></div></header>
  {!items.length?<section className="mt-20 text-center"><ShoppingBag className="mx-auto text-cande-300" size={52}/><h2 className="mt-5 text-xl font-black">Tu carrito está esperando</h2><p className="mt-2 text-sm text-zinc-500">Agrega una combinación deliciosa para continuar.</p><Link href="/menu" className="mt-6 inline-block rounded-full bg-cande-500 px-6 py-3 font-bold text-white">Explorar menú</Link></section>:<>
   <section className="mt-7 space-y-3">{items.map(i=><article key={i.key} className={`card flex gap-4 p-3 ${i.redemptionId?'border-2 border-cande-200 bg-cande-50':''}`}><div className="relative h-24 w-24 shrink-0 overflow-hidden rounded-md"><Image src={i.image} alt={i.name} fill className="object-cover"/></div><div className="min-w-0 flex-1"><div className="flex justify-between gap-2"><div>{i.redemptionId&&<p className="mb-1 flex items-center gap-1 text-xs font-black uppercase text-cande-600"><Gift size={14}/>Recompensa</p>}<h2 className="font-extrabold">{i.name}</h2><p className="text-xs text-zinc-500">{i.size}{i.toppings.length?` · ${i.toppings.map(t=>t.name).join(', ')}`:''}</p></div><strong>{i.redemptionId?'GRATIS':money(i.unitPrice*i.quantity)}</strong></div>{i.redemptionId?<button onClick={()=>removeRedemption(i.redemptionId!)} className="mt-3 flex items-center gap-1 text-xs font-bold text-zinc-500"><X size={14}/>Quitar recompensa</button>:<div className="mt-3 inline-flex items-center rounded-full bg-cande-50"><button aria-label="Disminuir" onClick={()=>update(i.key,i.quantity-1)} className="grid h-8 w-9 place-items-center"><Minus size={14}/></button><span className="w-5 text-center text-sm font-bold">{i.quantity}</span><button aria-label="Aumentar" onClick={()=>update(i.key,i.quantity+1)} className="grid h-8 w-9 place-items-center"><Plus size={14}/></button></div>}</div></article>)}</section>
   {redemptions.some(r=>r.type==='fixed_discount')&&<section className="mt-4 rounded-md border border-green-200 bg-green-50 p-4"><p className="flex items-center gap-2 font-black text-green-800"><Gift size={18}/>$50 de descuento aplicado</p><button onClick={()=>redemptions.filter(r=>r.type==='fixed_discount').forEach(r=>removeRedemption(r.id))} className="mt-2 text-xs font-bold text-green-700">Quitar descuento</button></section>}
   <section className="card mt-6 space-y-3 p-5 text-sm"><div className="flex justify-between"><span className="text-zinc-500">Subtotal</span><strong>{money(subtotal)}</strong></div><div className="flex justify-between"><span className="text-zinc-500">Envío</span><strong>{money(shipping)}</strong></div><div className="flex justify-between"><span className="text-zinc-500">Recompensas</span><strong className="text-green-700">-{money(discount)}</strong></div><div className="flex justify-between border-t border-cande-100 pt-4 text-lg"><span className="font-bold">Total</span><strong className="text-cande-700">{money(total)}</strong></div></section>
   <Link href="/checkout" className="mt-5 flex h-14 items-center justify-center rounded-full bg-cande-500 font-bold text-white">Continuar pedido</Link>
  </>}
 </main>
}
