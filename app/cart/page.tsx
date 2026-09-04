'use client'

import Image from 'next/image'
import Link from 'next/link'
import { ArrowLeft, Gift, Minus, Plus, ShoppingBag, X } from 'lucide-react'
import { useCart } from '@/components/cart-provider'
import { useStore } from '@/components/store-provider'
import { money } from '@/lib/data'
import { itemLineTotal, orderTotal, toppingsUnitTotal } from '@/lib/pricing'
import {FirstPurchaseGift} from '@/components/first-purchase-gift'

export default function Cart() {
  const { items, redemptions, update, removeRedemption, subtotal, rewardDiscount } = useCart()
  const { config } = useStore()
  const shipping = subtotal ? config.shippingFee : 0
  const discount = Math.min(subtotal, rewardDiscount)
  const total = orderTotal(subtotal, shipping, discount)

  return <main className="page max-w-3xl">
    <header className="flex items-center gap-4"><Link href="/menu" className="grid h-10 w-10 place-items-center rounded-full bg-cande-50"><ArrowLeft size={20} /></Link><div><p className="text-xs font-bold uppercase text-cande-500">Tu selección</p><h1 className="text-2xl font-black">Carrito</h1></div></header>
    {!items.length ? <section className="empty-state mt-14"><span className="empty-state-icon"><ShoppingBag size={27}/></span><h2 className="mt-5 text-xl font-black">Tu carrito está esperando</h2><p className="mt-2 text-sm text-zinc-500">Agrega una combinación deliciosa y personalizada para continuar.</p><Link href="/menu" className="mt-6 inline-flex min-h-12 items-center rounded-full bg-cande-500 px-6 font-bold text-white shadow-soft">Ver menú</Link></section> : <>
      <div className="mt-6"><FirstPurchaseGift compact /></div>
      <section className="mt-4 space-y-3">{items.map((item) => {
        const toppingTotal = toppingsUnitTotal(item.toppings)
        return <article key={item.key} className={`card flex gap-4 p-3 ${item.redemptionId ? 'border-2 border-cande-200 bg-cande-50' : ''}`}>
          <div className="relative h-24 w-24 shrink-0 overflow-hidden rounded-md"><Image src={item.image} alt={item.name} fill className="object-cover" /></div>
          <div className="min-w-0 flex-1">
            <div className="flex justify-between gap-2"><div>{item.redemptionId && <p className="mb-1 flex items-center gap-1 text-xs font-black uppercase text-cande-600"><Gift size={14} />Recompensa</p>}<h2 className="font-extrabold">{item.name}</h2><p className="text-xs text-zinc-500">{item.size}</p></div><strong>{item.redemptionId ? 'GRATIS' : money(itemLineTotal(item))}</strong></div>
            {!item.redemptionId && <div className="mt-2 text-xs text-zinc-600"><p>Producto: {money(item.unitPrice)}</p>{item.toppings.map((topping) => <p key={topping.id || topping.name}>{topping.name}: +{money(topping.price)}</p>)}{toppingTotal > 0 && <p className="font-bold">Extras por unidad: +{money(toppingTotal)}</p>}</div>}
            {item.redemptionId ? <button onClick={() => removeRedemption(item.redemptionId!)} className="mt-3 flex items-center gap-1 text-xs font-bold text-zinc-500"><X size={14} />Quitar recompensa</button> : <div className="mt-3 inline-flex items-center rounded-full bg-cande-50"><button aria-label="Disminuir" onClick={() => update(item.key, item.quantity - 1)} className="grid h-8 w-9 place-items-center"><Minus size={14} /></button><span className="w-5 text-center text-sm font-bold">{item.quantity}</span><button aria-label="Aumentar" onClick={() => update(item.key, item.quantity + 1)} className="grid h-8 w-9 place-items-center"><Plus size={14} /></button></div>}
          </div>
        </article>
      })}</section>
      {redemptions.some((reward) => reward.type === 'fixed_discount') && <section className="mt-4 rounded-md border border-green-200 bg-green-50 p-4"><p className="flex items-center gap-2 font-black text-green-800"><Gift size={18} />Descuento aplicado</p><button onClick={() => redemptions.filter((reward) => reward.type === 'fixed_discount').forEach((reward) => removeRedemption(reward.id))} className="mt-2 text-xs font-bold text-green-700">Quitar descuento</button></section>}
      <section className="card mt-6 space-y-3 p-5 text-sm"><div className="flex justify-between"><span className="text-zinc-500">Subtotal productos + toppings</span><strong>{money(subtotal)}</strong></div><div className="flex justify-between"><span className="text-zinc-500">Envío</span><strong>{money(shipping)}</strong></div><div className="flex justify-between"><span className="text-zinc-500">Recompensas</span><strong className="text-green-700">-{money(discount)}</strong></div><div className="flex justify-between border-t border-cande-100 pt-4 text-lg"><span className="font-bold">Total</span><strong className="text-cande-700">{money(total)}</strong></div></section>
      <Link href="/checkout" className="mt-5 flex h-14 items-center justify-center rounded-full bg-cande-500 font-bold text-white">Continuar pedido</Link>
    </>}
  </main>
}
