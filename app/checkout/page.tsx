'use client'

import Link from 'next/link'
import { FormEvent, useEffect, useMemo, useState } from 'react'
import { ArrowLeft, Check, Copy, LocateFixed, MapPin, MessageCircle, Store } from 'lucide-react'
import { useCart } from '@/components/cart-provider'
import { useStore } from '@/components/store-provider'
import { money } from '@/lib/data'

type DeliveryType = 'delivery' | 'pickup'
type LocationState = 'idle' | 'loading' | 'shared' | 'denied' | 'unavailable'

const BUSINESS_WHATSAPP = '527222219560'

export default function Checkout() {
  const { items, subtotal, clear } = useCart()
  const { config } = useStore()
  const [type, setType] = useState<DeliveryType>('delivery')
  const [payment, setPayment] = useState('Efectivo')
  const [name, setName] = useState('Mariana Cruz')
  const [phone, setPhone] = useState('')
  const [address, setAddress] = useState('')
  const [references, setReferences] = useState('')
  const [notes, setNotes] = useState('')
  const [coordinates, setCoordinates] = useState<{ latitude: number; longitude: number } | null>(null)
  const [locationState, setLocationState] = useState<LocationState>('idle')
  const [done, setDone] = useState(false)
  const [confirmedMessage, setConfirmedMessage] = useState('')
  const [orderId, setOrderId] = useState('CAN-PENDIENTE')

  useEffect(() => {
    setOrderId(`CAN-${Math.floor(1000 + Math.random() * 9000)}`)
  }, [])

  const shipping = type === 'delivery' ? config.shippingFee : 0
  const discount = 0
  const total = subtotal + shipping - discount
  const points = Math.floor(subtotal * config.pointsPerPeso)
  const mapsUrl = coordinates
    ? `https://www.google.com/maps?q=${coordinates.latitude},${coordinates.longitude}`
    : ''

  const message = useMemo(() => {
    const products = items.map((item) => {
      const lines = [`${item.quantity}x ${item.name} ${item.size}`]
      if (item.toppings.length) lines.push(`Toppings: ${item.toppings.map((t) => t.name).join(', ')}`)
      return lines.join('\n')
    }).join('\n\n')

    return [
      '🍓 NUEVO PEDIDO - FRESAS CON CREMA CANDE',
      `Pedido: ${orderId}`,
      '',
      `Cliente: ${name}`,
      `Teléfono: ${phone}`,
      `Entrega: ${type === 'delivery' ? 'Domicilio' : 'Recoger pedido'}`,
      '',
      'PEDIDO:',
      products,
      '',
      `Subtotal: ${money(subtotal)}`,
      `Envío: ${money(shipping)}`,
      `Descuento: ${money(discount)}`,
      `Total: ${money(total)}`,
      '',
      `Método de pago: ${payment}`,
      '',
      'Dirección:',
      type === 'delivery' ? address : 'Recoger en sucursal',
      '',
      'Referencias:',
      references || 'Sin referencias',
      '',
      '📍 Ubicación:',
      mapsUrl || 'Ubicación no compartida — solicitar por WhatsApp',
      '',
      'Notas:',
      notes || 'Sin notas',
      '',
      `Puntos ganados: ${points} pts`,
    ].join('\n')
  }, [address, discount, items, mapsUrl, name, notes, orderId, payment, phone, points, references, shipping, subtotal, total, type])

  function requestLocation() {
    if (!('geolocation' in navigator)) {
      setLocationState('unavailable')
      return
    }

    setLocationState('loading')
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        setCoordinates({ latitude: Number(coords.latitude.toFixed(6)), longitude: Number(coords.longitude.toFixed(6)) })
        setLocationState('shared')
      },
      (error) => {
        setCoordinates(null)
        setLocationState(error.code === error.PERMISSION_DENIED ? 'denied' : 'unavailable')
      },
      { enableHighAccuracy: true, timeout: 12000, maximumAge: 60000 },
    )
  }

  function saveOrder() {
    const order = {
      orderId,
      customer: { name, phone },
      delivery: {
        type,
        address: type === 'delivery' ? address : '',
        references,
        coordinates,
        mapsUrl: mapsUrl || null,
      },
      notes,
      payment,
      subtotal,
      shipping,
      discount,
      total,
      points,
      date: new Date().toISOString(),
      status: 'Recibido',
      items,
    }

    const previousOrders = JSON.parse(localStorage.getItem('cande-orders') || '[]')
    localStorage.setItem('cande-orders', JSON.stringify([order, ...previousOrders]))
    localStorage.setItem('cande-last-order', JSON.stringify(order))

    const currentPoints = Number(localStorage.getItem('cande-points') || '184')
    localStorage.setItem('cande-points', String(currentPoints + points))

    const stats = JSON.parse(localStorage.getItem('cande-stats') || '{"sales":0,"orders":0,"points":0}')
    localStorage.setItem('cande-stats', JSON.stringify({
      sales: Number(stats.sales || 0) + total,
      orders: Number(stats.orders || 0) + 1,
      points: Number(stats.points || 0) + points,
    }))
  }

  function openWhatsApp(text = confirmedMessage || message) {
    window.location.href = `https://wa.me/${BUSINESS_WHATSAPP}?text=${encodeURIComponent(text)}`
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    const finalMessage = message
    saveOrder()
    setConfirmedMessage(finalMessage)
    setDone(true)
    clear()
    // Assigning the location from the user's submit gesture works reliably on Android.
    openWhatsApp(finalMessage)
  }

  if (done) return <main className="page max-w-xl text-center">
    <div className="mx-auto mt-12 grid h-20 w-20 place-items-center rounded-full bg-green-100 text-green-700"><Check size={38} /></div>
    <h1 className="mt-6 text-3xl font-black">¡Pedido guardado! 🍓</h1>
    <p className="mt-2 text-zinc-500">Sumamos tus puntos y abrimos WhatsApp con el pedido listo.</p>
    <section className="card mt-7 p-6 text-left">
      <p className="text-xs font-bold uppercase text-cande-500">Pedido {orderId}</p>
      <div className="mt-4 flex justify-between"><span>Total</span><strong>{money(total)}</strong></div>
      <div className="mt-3 flex justify-between"><span>Puntos ganados</span><strong className="text-cande-600">+{points} pts</strong></div>
      <div className="mt-4 rounded-md bg-cande-50 p-4 text-sm">
        <strong className="block text-cande-900">📍 Ubicación de entrega</strong>
        {mapsUrl ? <a href={mapsUrl} target="_blank" rel="noreferrer" className="mt-1 block break-all font-bold text-cande-600">Abrir en Google Maps</a> : <p className="mt-1 text-zinc-600">Ubicación no compartida — solicitar por WhatsApp.</p>}
      </div>
      <button onClick={() => openWhatsApp()} className="mt-6 flex h-12 w-full items-center justify-center gap-2 rounded-full bg-[#25D366] font-bold text-white">
        <MessageCircle size={19} /> Enviar pedido por WhatsApp
      </button>
      <button onClick={() => navigator.clipboard?.writeText(confirmedMessage)} className="mt-3 flex w-full items-center justify-center gap-2 text-sm font-bold text-cande-600"><Copy size={16} />Copiar mensaje</button>
    </section>
    <Link href="/orders" className="mt-6 inline-flex rounded-full bg-cande-500 px-7 py-3 font-bold text-white">Ver mis pedidos</Link>
  </main>

  return <main className="page max-w-2xl">
    <header className="flex items-center gap-4">
      <Link href="/cart" className="grid h-10 w-10 place-items-center rounded-full bg-cande-50"><ArrowLeft size={20} /></Link>
      <div><p className="text-xs font-bold uppercase text-cande-500">Último paso</p><h1 className="text-2xl font-black">Completa tu pedido</h1></div>
    </header>

    <form onSubmit={submit} className="mt-7 space-y-6">
      <section className="card p-5">
        <h2 className="font-extrabold">Tus datos</h2>
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <input required className="input" placeholder="Nombre" value={name} onChange={(e) => setName(e.target.value)} />
          <input required className="input" type="tel" inputMode="tel" placeholder="Teléfono" value={phone} onChange={(e) => setPhone(e.target.value)} />
        </div>
      </section>

      <section className="card p-5">
        <h2 className="font-extrabold">¿Cómo lo recibes?</h2>
        <div className="mt-4 grid grid-cols-2 gap-3">
          <button type="button" onClick={() => setType('delivery')} className={`flex items-center justify-center gap-2 rounded-md border p-4 text-sm font-bold ${type === 'delivery' ? 'border-cande-500 bg-cande-50 text-cande-700' : 'border-zinc-200'}`}><MapPin size={19} />A domicilio</button>
          <button type="button" onClick={() => setType('pickup')} className={`flex items-center justify-center gap-2 rounded-md border p-4 text-sm font-bold ${type === 'pickup' ? 'border-cande-500 bg-cande-50 text-cande-700' : 'border-zinc-200'}`}><Store size={19} />Recoger</button>
        </div>
        {type === 'delivery' && <div className="mt-3 space-y-3">
          <div className="overflow-hidden rounded-lg border-2 border-cande-500 bg-cande-50 shadow-[0_12px_28px_rgba(242,46,98,.13)]">
            <div className={`p-5 ${locationState === 'shared' ? 'bg-cande-500 text-white' : 'bg-cande-50 text-cande-900'}`}>
              <div className="flex items-start gap-3">
                <span className={`grid h-11 w-11 shrink-0 place-items-center rounded-full ${locationState === 'shared' ? 'bg-white text-cande-600' : 'bg-cande-500 text-white'}`}><LocateFixed size={22} /></span>
                <div>
                  <h3 className="text-lg font-black">{locationState === 'shared' ? '✅ ¡Ubicación recibida!' : '📍 Compártenos tu ubicación'}</h3>
                  <p className={`mt-2 text-sm leading-relaxed ${locationState === 'shared' ? 'text-white' : 'text-zinc-700'}`}>{locationState === 'shared' ? 'Ya sabemos dónde entregar tu pedido.' : 'Ayúdanos a llegar directamente hasta ti. Comparte tu ubicación exacta para encontrar tu domicilio más rápido y evitar retrasos en tu pedido.'}</p>
                </div>
              </div>
            </div>
            <div className="p-4">
              <button type="button" onClick={requestLocation} disabled={locationState === 'loading'} className="flex h-14 w-full items-center justify-center gap-2 rounded-full bg-cande-500 px-4 text-sm font-black uppercase text-white shadow-lg shadow-cande-200 transition active:scale-[.98] disabled:opacity-60">
                {locationState === 'loading' ? 'OBTENIENDO UBICACIÓN…' : locationState === 'shared' ? 'ACTUALIZAR MI UBICACIÓN' : '📍 COMPARTIR MI UBICACIÓN'}
              </button>
              {locationState === 'shared' && mapsUrl && <a href={mapsUrl} target="_blank" rel="noreferrer" className="mt-3 block break-all text-center text-xs font-bold text-cande-700">Ver ubicación en Google Maps</a>}
              {locationState === 'denied' && <p role="status" className="mt-3 text-center text-xs leading-relaxed text-zinc-600">No se compartió la ubicación. Puedes continuar con dirección y referencias.</p>}
              {locationState === 'unavailable' && <p role="status" className="mt-3 text-center text-xs leading-relaxed text-zinc-600">No pudimos obtener tu ubicación. Puedes continuar normalmente con la dirección.</p>}
            </div>
          </div>
          <div className="pt-2"><label className="mb-2 block text-xs font-bold uppercase text-zinc-500">Dirección</label><input required className="input" placeholder="Dirección completa" value={address} onChange={(e) => setAddress(e.target.value)} /></div>
          <div><label className="mb-2 block text-xs font-bold uppercase text-zinc-500">Referencias</label><input className="input" placeholder="Entre calles, color de fachada, número…" value={references} onChange={(e) => setReferences(e.target.value)} /></div>
        </div>}
        <textarea className="input mt-3 min-h-24" placeholder="Notas del pedido" value={notes} onChange={(e) => setNotes(e.target.value)} />
      </section>

      <section className="card p-5">
        <h2 className="font-extrabold">Método de pago</h2>
        <div className="mt-4 space-y-2">{['Efectivo', 'Transferencia / SPEI'].map((method) => <label key={method} className="flex cursor-pointer items-center gap-3 rounded-md border border-zinc-200 p-4"><input type="radio" name="payment" checked={payment === method} onChange={() => setPayment(method)} className="accent-cande-500" /><span className="font-bold">{method}</span></label>)}</div>
      </section>

      <section className="card p-5">
        <div className="flex justify-between text-sm"><span>Subtotal</span><strong>{money(subtotal)}</strong></div>
        <div className="mt-2 flex justify-between text-sm"><span>Envío</span><strong>{money(shipping)}</strong></div>
        <div className="mt-2 flex justify-between text-sm"><span>Descuento</span><strong>{money(discount)}</strong></div>
        <div className="mt-4 flex justify-between border-t pt-4 text-lg"><strong>Total</strong><strong className="text-cande-700">{money(total)}</strong></div>
      </section>

      <button disabled={!items.length} className="flex h-14 w-full items-center justify-center gap-2 rounded-full bg-[#25D366] px-5 font-bold text-white disabled:opacity-40">
        <MessageCircle size={20} /> Enviar pedido por WhatsApp
      </button>
      <p className="text-center text-xs text-zinc-500">Primero guardaremos tu pedido y tus puntos. Después abriremos WhatsApp.</p>
    </form>
  </main>
}
