'use client'

import Image from 'next/image'
import Link from 'next/link'
import { useMemo, useState } from 'react'
import { ArrowRight, Bike, CalendarDays, Gift, MapPin, Search, Sparkles, Star } from 'lucide-react'
import { Logo } from '@/components/logo'
import { InstallCandeCard } from '@/components/install-cande'
import { money } from '@/lib/data'
import { useStore } from '@/components/store-provider'
import { useAuth } from '@/components/auth-provider'
import { ReferralProgram } from '@/components/referral-program'
import { HomepageCarousel } from '@/components/homepage-carousel'

const date = (value: string) => new Intl.DateTimeFormat('es-MX', {
  day: 'numeric', month: 'short', timeZone: 'America/Mexico_City',
}).format(new Date(value))

export default function Home() {
  const { config } = useStore()
  const { user, profile } = useAuth()
  const [query, setQuery] = useState('')
  const now = new Date()
  const availableProducts = config.products.filter(product => product.active && product.availability === 'active').sort((a, b) => a.sortOrder - b.sortOrder)
  const products = availableProducts.filter(product => product.featured)
  const categories = [...new Set(availableProducts.map(product => product.category).filter(Boolean))]
  const results = useMemo(() => {
    const term = query.trim().toLocaleLowerCase('es-MX')
    if (!term) return []
    return availableProducts.filter(product => [product.name, product.category, product.description, ...product.ingredients].join(' ').toLocaleLowerCase('es-MX').includes(term)).slice(0, 6)
  }, [availableProducts, query])
  const promo = config.promotions.find(item => item.active && now >= new Date(item.startsAt) && now <= new Date(item.endsAt))
  const quick = [[Bike, 'Envío', '/checkout'], [MapPin, 'Recoger', '/checkout'], [Sparkles, 'Promos', promo ? '#promo' : '/menu'], [Gift, 'Recompensas', '/rewards']] as const
  const points = profile?.points_balance || 0

  return <main className="page">
    <header className="flex items-center justify-between">
      <Logo />
      <Link href="/account" className="grid h-10 min-w-10 place-items-center rounded-full bg-cande-100 px-3 text-xs font-bold text-cande-700">{user ? (profile?.name.split(' ')[0] || 'Cuenta') : 'Entrar'}</Link>
    </header>

    <section className="relative mt-6 min-h-[410px] overflow-hidden rounded-lg bg-cande-100">
      <Image src={config.hero.image} alt="Fresas con crema Cande" fill priority className="object-cover" />
      <div className="absolute inset-0 bg-gradient-to-r from-white/95 via-white/60 to-transparent" />
      <div className="relative z-10 max-w-[68%] px-6 py-8">
        <span className="pill inline-block bg-white/90 px-3 py-1.5 text-xs font-bold text-cande-600">{config.hero.title}</span>
        <h1 className="mt-4 text-3xl font-black leading-tight text-cande-900">{profile ? `¡Hola, ${profile.name.split(' ')[0]}! 👋` : '¡Hola! 🍓'}</h1>
        <p className="mt-3 text-sm leading-relaxed text-zinc-700">{config.hero.description}</p>
        <Link href="/menu" className="mt-6 inline-flex items-center gap-2 rounded-full bg-cande-500 px-5 py-3 text-sm font-bold text-white">{config.hero.button}<ArrowRight size={17} /></Link>
      </div>
    </section>

    <section className="card relative z-10 -mt-12 mx-3 p-5">
      <div className="flex justify-between"><div><p className="text-xs font-bold uppercase text-zinc-500">{user ? 'Tus puntos' : 'Cande Rewards'}</p><p className="mt-1 text-3xl font-black text-cande-700">{points} <span className="text-sm">pts</span></p></div><Star fill="currentColor" className="text-cande-500" /></div>
      {user ? <p className="mt-3 text-xs text-zinc-600">Saldo guardado en tu cuenta Cande.</p> : <Link href="/account" className="mt-3 inline-flex text-sm font-bold text-cande-600">Regístrate para acumular puntos</Link>}
    </section>

    <InstallCandeCard />

    <HomepageCarousel />

    <section className="mt-7" aria-label="Buscar en el menú">
      <label className="flex min-h-14 items-center gap-3 rounded-md border border-cande-100 bg-white px-4 shadow-sm focus-within:border-cande-400 focus-within:ring-4 focus-within:ring-cande-50">
        <Search size={20} className="shrink-0 text-cande-500" />
        <input value={query} onChange={event => setQuery(event.target.value)} className="min-w-0 flex-1 bg-transparent py-3 text-base outline-none" placeholder="¿Qué se te antoja hoy?" />
      </label>
      {categories.length > 0 && <div className="hide-scroll mt-3 flex gap-2 overflow-x-auto pb-1">{categories.map(category => <button type="button" key={category} onClick={() => setQuery(category)} className="shrink-0 rounded-full border border-cande-100 bg-cande-50 px-4 py-2 text-xs font-bold text-cande-700">{category}</button>)}</div>}
      {query.trim() && <div className="mt-3 overflow-hidden rounded-md border border-cande-100 bg-white">{results.map(product => <Link href="/menu" key={product.id} className="flex items-center gap-3 border-b border-cande-50 p-3 last:border-0"><span className="relative h-16 w-16 shrink-0 overflow-hidden rounded-md bg-cande-50"><Image src={product.image} alt="" fill className="object-contain" /></span><span className="min-w-0 flex-1"><strong className="block truncate">{product.name}</strong><small className="text-zinc-500">{product.category}</small></span><ArrowRight size={17} className="shrink-0 text-cande-500" /></Link>)}{!results.length && <p className="p-4 text-sm text-zinc-500">No encontramos productos con esa búsqueda.</p>}</div>}
    </section>

    {promo && <section id="promo" className="relative mt-8 min-h-[360px] overflow-hidden rounded-lg bg-cande-900 text-white">
      <Image src={promo.image} alt={promo.title} fill className="object-cover" />
      <div className="absolute inset-0 bg-gradient-to-t from-cande-900 via-cande-900/70 to-transparent" />
      <div className="relative z-10 flex min-h-[360px] flex-col justify-end p-6">
        <span className="text-xs font-black uppercase text-cande-200">{promo.eyebrow}</span><h2 className="mt-2 text-3xl font-black">{promo.title}</h2><p className="mt-3 text-sm text-white/85">{promo.description}</p>
        <p className="mt-4 flex gap-2 text-xs font-bold text-white/75"><CalendarDays size={15} />Válida del {date(promo.startsAt)} al {date(promo.endsAt)}</p>
        <Link href="/menu" className="mt-5 flex h-12 w-fit items-center gap-2 rounded-full bg-cande-500 px-6 text-sm font-black">Pedir ahora<ArrowRight size={17} /></Link>
      </div>
    </section>}

    <div className="mt-8"><ReferralProgram compact /></div>

    <section className="mt-8 grid grid-cols-4 gap-2">
      {quick.map(([Icon, label, href]) => <Link href={href} key={label} className="flex flex-col items-center gap-2 text-center text-[11px] font-bold"><span className="grid h-12 w-12 place-items-center rounded-full bg-cande-50 text-cande-600"><Icon size={21} /></span>{label}</Link>)}
    </section>

    <section className="mt-10">
      <div className="flex justify-between"><div><p className="text-xs font-bold uppercase text-cande-500">Seleccionados por Cande</p><h2 className="section-title mt-1">Productos destacados</h2></div><Link className="text-sm font-bold text-cande-600" href="/menu">Ver todos</Link></div>
      <div className="hide-scroll -mx-4 mt-4 flex gap-4 overflow-x-auto px-4 pb-4">
        {products.map(product => <Link href="/menu" key={product.id} className="card min-w-[190px] overflow-hidden"><div className="relative h-44 bg-cande-50"><Image src={product.image} alt={product.name} fill className="object-contain" /></div><div className="p-4"><h3 className="font-extrabold">{product.name}</h3><p className="mt-1 text-sm text-zinc-500">Desde <strong className="text-cande-700">{money(startingPrice(product.prices, product.availableSizes))}</strong></p></div></Link>)}
      </div>
    </section>
  </main>
}

function startingPrice(prices: Record<string, number>, availableSizes: Record<string, boolean>) {
  const values = Object.entries(prices).filter(([size]) => availableSizes[size]).map(([, price]) => Number(price)).filter(price => price > 0)
  return values.length ? Math.min(...values) : 0
}
