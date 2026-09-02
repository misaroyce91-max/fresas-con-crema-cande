'use client'

import Image from 'next/image'
import Link from 'next/link'
import { useState } from 'react'
import { Minus, Plus, ShoppingBag, SlidersHorizontal } from 'lucide-react'
import { money } from '@/lib/data'
import { useCart } from '@/components/cart-provider'
import { ManagedProduct, ManagedTopping, useStore } from '@/components/store-provider'
import { Logo } from '@/components/logo'
import { EmptyMenu, MenuSkeleton } from '@/components/ui-state'

function ProductCard({ product, toppings }: { product: ManagedProduct; toppings: ManagedTopping[] }) {
  const offered = Object.keys(product.availableSizes).filter((size) => product.availableSizes[size])
  const [size, setSize] = useState(offered[0] || '')
  const [selected, setSelected] = useState<string[]>([])
  const [quantity, setQuantity] = useState(1)
  const { add } = useCart()
  const available = toppings.filter((topping) => topping.active && (!product.toppingIds.length || product.toppingIds.includes(topping.id)))
  const chosen = available.filter((topping) => selected.includes(topping.name))
  const productPrice = Number(product.prices[size] || 0)
  const unitTotal = productPrice + chosen.reduce((total, topping) => total + Number(topping.price), 0)
  const from = offered.length ? Math.min(...offered.map((offeredSize) => Number(product.prices[offeredSize]))) : 0

  return <article className="card overflow-hidden">
    <div className="relative aspect-[4/5] overflow-hidden bg-cande-50"><Image src={product.image} alt={product.name} fill sizes="(min-width: 768px) 50vw, 100vw" className="object-contain object-center" unoptimized />{product.specialty && <span className="pill absolute left-3 top-3 bg-white px-3 py-1 text-xs font-bold text-cande-600 shadow">Especialidad</span>}</div>
    <div className="p-5">
      <div className="flex justify-between gap-3"><div><p className="text-[10px] font-bold uppercase text-cande-500">{product.category}</p><h2 className="text-xl font-black">{product.name}</h2><p className="mt-1 text-sm text-zinc-500">{product.description}</p></div><strong className="text-cande-700">{money(from)}+</strong></div>
      <p className="mt-5 text-xs font-bold uppercase text-zinc-500">Elige tamaño</p>
      <div className="mt-2 grid grid-cols-4 gap-2">{offered.map((offeredSize) => <button onClick={() => setSize(offeredSize)} className={`rounded-md border py-2 text-xs font-bold ${size === offeredSize ? 'border-cande-500 bg-cande-50 text-cande-700' : 'border-zinc-200'}`} key={offeredSize}>{offeredSize}</button>)}</div>
      <p className="mt-5 text-xs font-bold uppercase text-zinc-500">Toppings</p>
      <div className="mt-2 flex flex-wrap gap-2">{available.map((topping) => {
        const active = selected.includes(topping.name)
        return <button key={topping.id} onClick={() => setSelected((current) => active ? current.filter((name) => name !== topping.name) : [...current, topping.name])} className={`rounded-full border px-3 py-2 text-xs ${active ? 'border-cande-500 bg-cande-500 font-bold text-white' : 'border-zinc-200 text-zinc-600'}`}>{topping.name} +{money(topping.price)}</button>
      })}</div>
      <div className="mt-5 flex items-center gap-3">
        <div className="flex h-12 items-center rounded-full border"><button aria-label="Disminuir" onClick={() => setQuantity(Math.max(1, quantity - 1))} className="grid h-12 w-10 place-items-center"><Minus size={16} /></button><strong className="w-6 text-center">{quantity}</strong><button aria-label="Aumentar" onClick={() => setQuantity(quantity + 1)} className="grid h-12 w-10 place-items-center"><Plus size={16} /></button></div>
        <button disabled={!offered.length} onClick={() => add({ productId: product.id, name: product.name, image: product.image, size, toppings: chosen, quantity, unitPrice: productPrice })} className="flex h-12 flex-1 items-center justify-center gap-2 rounded-full bg-cande-500 px-4 text-sm font-bold text-white disabled:opacity-50"><ShoppingBag size={18} />Agregar · {money(unitTotal * quantity)}</button>
      </div>
    </div>
  </article>
}

export default function Menu() {
  const { count, subtotal } = useCart()
  const { config, loading } = useStore()
  const products = config.products.filter((product) => product.availability === 'active' && product.active).sort((a, b) => a.sortOrder - b.sortOrder)
  return <main className="page">
    <header className="flex items-center justify-between"><Logo /><SlidersHorizontal className="text-cande-700" /></header>
    <div className="mt-8"><p className="text-xs font-bold uppercase text-cande-500">Fresas para hoy</p><h1 className="mt-1 text-3xl font-black">Elige tu favorita</h1><p className="mt-2 text-sm text-zinc-500">Personalízala a tu gusto. La preparamos al confirmar.</p></div>
    {loading ? <MenuSkeleton /> : products.length ? <div className="mt-6 grid gap-5 md:grid-cols-2">{products.map((product) => <ProductCard key={product.id} product={product} toppings={config.toppings} />)}</div> : <EmptyMenu />}
    {count > 0 && <Link href="/cart" className="fixed bottom-[138px] right-4 z-40 flex items-center gap-3 rounded-full bg-cande-900 px-5 py-3 text-sm font-bold text-white shadow-xl"><ShoppingBag size={18} />{count} · {money(subtotal)}</Link>}
  </main>
}
