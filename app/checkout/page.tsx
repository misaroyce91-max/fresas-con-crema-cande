'use client'

import Link from 'next/link'
import { FormEvent, useEffect, useMemo, useState } from 'react'
import { ArrowLeft, Check, Copy, LocateFixed, MapPin, MessageCircle, Store } from 'lucide-react'
import { useCart } from '@/components/cart-provider'
import { useStore } from '@/components/store-provider'
import { useAuth } from '@/components/auth-provider'
import { supabase } from '@/lib/supabase'
import { money } from '@/lib/data'
import { orderTotal, toppingsUnitTotal } from '@/lib/pricing'
import {FirstPurchaseGift,useFirstPurchaseOffer} from '@/components/first-purchase-gift'

type DeliveryType = 'delivery' | 'pickup'
type LocationState = 'idle' | 'loading' | 'shared' | 'denied' | 'unavailable'
type DeliveryQuote = { configured:boolean;serviceable:boolean;distanceKm?:number;fee?:number;driverPay?:number;businessShare?:number;reason?:string;freeShipping?:boolean }

const BUSINESS_WHATSAPP = '527222219560'

export default function Checkout() {
  const firstPurchaseOffer = useFirstPurchaseOffer()
  const { items, redemptions, subtotal, rewardDiscount, clear } = useCart()
  const { config } = useStore()
  const { user, profile, refreshProfile } = useAuth()
  const [type, setType] = useState<DeliveryType>('delivery')
  const [payment, setPayment] = useState('Efectivo')
  const [name, setName] = useState('')
  const [phone, setPhone] = useState('')
  const [address, setAddress] = useState('')
  const [references, setReferences] = useState('')
  const [notes, setNotes] = useState('')
  const [coordinates, setCoordinates] = useState<{ latitude: number; longitude: number } | null>(null)
  const [locationState, setLocationState] = useState<LocationState>('idle')
  const [done, setDone] = useState(false)
  const [confirmedMessage, setConfirmedMessage] = useState('')
  const [orderId, setOrderId] = useState('CAN-PENDIENTE')
  const [requestId, setRequestId] = useState('')
  const [saving, setSaving] = useState(false)
  const [confirmedTotal, setConfirmedTotal] = useState(0)
  const [confirmedPoints, setConfirmedPoints] = useState(0)
  const [distanceEnabled, setDistanceEnabled] = useState(false)
  const [deliveryQuote, setDeliveryQuote] = useState<DeliveryQuote | null>(null)
  const [quoteLoading, setQuoteLoading] = useState(false)

  useEffect(() => {
    setRequestId(crypto.randomUUID())
  }, [])

  useEffect(() => {
    if (profile) { setName(profile.name); setPhone(profile.phone) }
  }, [profile])

  useEffect(()=>{supabase?.from('delivery_rate_settings').select('enabled').eq('id','main').single().then(({data})=>setDistanceEnabled(Boolean(data?.enabled)))},[])

  useEffect(()=>{
    if(type!=='delivery'||!coordinates||!supabase){setDeliveryQuote(null);setQuoteLoading(false);return}
    let active=true;setQuoteLoading(true)
    supabase.rpc('quote_delivery',{p_lat:coordinates.latitude,p_lng:coordinates.longitude,p_subtotal:subtotal}).then(({data,error})=>{if(active){setDeliveryQuote(error?{configured:true,serviceable:false,reason:error.message}:data as DeliveryQuote);setQuoteLoading(false)}})
    return()=>{active=false}
  },[coordinates,subtotal,type])

  const shipping = type === 'delivery' ? distanceEnabled ? Number(deliveryQuote?.fee||0) : config.shippingFee : 0
  const discount = Math.min(subtotal, rewardDiscount)
  const total = orderTotal(subtotal, shipping, discount)
  const productsSubtotal=items.reduce((sum,item)=>sum+Number(item.unitPrice)*item.quantity,0)
  const toppingsSubtotal=items.reduce((sum,item)=>sum+toppingsUnitTotal(item.toppings)*item.quantity,0)
  const points = Math.floor(total * config.pointsPerPeso)
  const mapsUrl = coordinates
    ? `https://www.google.com/maps?q=${coordinates.latitude},${coordinates.longitude}`
    : ''

  const message = useMemo(() => {
    const products = items.map((item) => {
      const lines = [`${item.quantity}x ${item.name} ${item.size}`]
      if (item.toppings.length) lines.push(`Toppings: ${item.toppings.map((t) => t.name).join(', ')}`)
      return lines.join('\n')
    }).concat(firstPurchaseOffer.eligible ? ['🎁 1x Fresas Clásicas Chicas — Primera compra: GRATIS'] : []).join('\n\n')

    return [
      '\u{1F353} NUEVO PEDIDO - FRESAS CON CREMA CANDE',
      `Pedido: ${orderId}`,
      '',
      `Cliente: ${name}`,
      `Teléfono: ${phone}`,
      `Entrega: ${type === 'delivery' ? 'Domicilio' : 'Recoger pedido'}`,
      ...(type==='delivery'&&deliveryQuote?.distanceKm?[`Distancia aproximada: ${Number(deliveryQuote.distanceKm).toFixed(1)} km`]:[]),
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
      '\u{1F4CD} Ubicación:',
      mapsUrl || 'Ubicación no compartida — solicitar por WhatsApp',
      '',
      'Notas:',
      notes || 'Sin notas',
      '',
      `Fresas Cande al completar el pedido: ${points} 🍓`,
    ].join('\n')
  }, [address, deliveryQuote, discount, firstPurchaseOffer.eligible, items, mapsUrl, name, notes, orderId, payment, phone, points, references, shipping, subtotal, total, type])

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

  function openWhatsApp(text = confirmedMessage || message) {
    window.location.href = `https://wa.me/${BUSINESS_WHATSAPP}?text=${encodeURIComponent(text)}`
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
    if (!user) { window.location.href='/account?next=/checkout'; return }
    if (!supabase || !requestId || saving) return
    setSaving(true)
    const { data, error } = await supabase.rpc('place_order', {
      p_client_request_id: requestId,
      p_items: items.map(item=>({productId:item.productId,size:item.size,quantity:item.quantity,toppingIds:item.toppings.map(t=>t.id).filter(Boolean),toppingNames:item.toppings.map(t=>t.name),redemptionId:item.redemptionId||null})),
      p_redemption_ids: redemptions.map(redemption=>redemption.id),
      p_delivery_type: type,
      p_address: type==='delivery'?{address,coordinates,mapsUrl:mapsUrl||null}:null,
      p_references: references,
      p_notes: notes,
      p_payment_method: payment,
    })
    setSaving(false)
    if(error){alert(`No pudimos guardar el pedido: ${error.message}`);return}
    const saved=data as any
    const savedOrderId=`CAN-${String(saved.orderNumber).padStart(6,'0')}`
    let finalMessage=message
      .replace(`Pedido: ${orderId}`,`Pedido: ${savedOrderId}`)
      .replace(`Subtotal: ${money(subtotal)}`,`Subtotal: ${money(Number(saved.subtotal))}`)
      .replace(`Envío: ${money(shipping)}`,`Envío: ${money(Number(saved.deliveryFee))}`)
      .replace(`Descuento: ${money(discount)}`,`Descuento: ${money(Number(saved.discount))}`)
      .replace(`Total: ${money(total)}`,`Total: ${money(Number(saved.total))}`)
      .replace(`Fresas Cande al completar el pedido: ${points} 🍓`,`Fresas Cande al completar el pedido: ${saved.strawberriesPending} 🍓`)
    if(!saved.gift) finalMessage=finalMessage.replace(/\n\n🎁 1x Fresas Clásicas Chicas — Primera compra: GRATIS/,'')
    setOrderId(savedOrderId)
    setConfirmedTotal(Number(saved.total));setConfirmedPoints(Number(saved.strawberriesPending))
    setConfirmedMessage(finalMessage)
    setDone(true)
    clear()
    await refreshProfile()
    openWhatsApp(finalMessage)
  }

  if (done) return <main className="page max-w-xl text-center">
    <div className="mx-auto mt-12 grid h-20 w-20 place-items-center rounded-full bg-green-100 text-green-700"><Check size={38} /></div>
    <h1 className="mt-6 text-3xl font-black">¡Pedido guardado! 🍓</h1>
    <p className="mt-2 text-zinc-500">Tu pedido quedó registrado. Tus Fresas Cande se acreditarán al pagarlo o completarlo.</p>
    <section className="card mt-7 p-6 text-left">
      <p className="text-xs font-bold uppercase text-cande-500">Pedido {orderId}</p>
      <div className="mt-4 flex justify-between"><span>Total</span><strong>{money(confirmedTotal)}</strong></div>
      <div className="mt-3 flex justify-between"><span>Fresas al completar</span><strong className="text-cande-600">+{confirmedPoints} 🍓</strong></div>
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
      <FirstPurchaseGift />
      {!user&&<section className="rounded-lg border-2 border-cande-500 bg-cande-50 p-5"><h2 className="font-black text-cande-900">Crea tu cuenta para acumular Fresas Cande</h2><p className="mt-2 text-sm text-zinc-600">Guardaremos este pedido, tus 🍓 y tu historial para que puedas consultarlos desde cualquier celular.</p><Link href="/account?next=/checkout" className="mt-4 inline-flex rounded-full bg-cande-500 px-5 py-3 text-sm font-bold text-white">Entrar o registrarme</Link></section>}
      <section className="card p-5">
        <h2 className="font-extrabold">Tus datos</h2>
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <input required readOnly={Boolean(profile)} className="input read-only:bg-zinc-50" placeholder="Nombre" value={name} onChange={(e) => setName(e.target.value)} />
          <input required readOnly={Boolean(profile)} className="input read-only:bg-zinc-50" type="tel" inputMode="tel" placeholder="Teléfono" value={phone} onChange={(e) => setPhone(e.target.value)} />
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
              {locationState === 'denied' && <p role="status" className="mt-3 text-center text-xs font-bold leading-relaxed text-cande-800">{distanceEnabled?'Necesitamos la ubicación para calcular el envío. Activa el permiso o elige Recoger pedido.':'No se compartió la ubicación. Puedes continuar con dirección y referencias.'}</p>}
              {locationState === 'unavailable' && <p role="status" className="mt-3 text-center text-xs font-bold leading-relaxed text-cande-800">{distanceEnabled?'No pudimos calcular el envío. Intenta compartir la ubicación otra vez o elige Recoger pedido.':'No pudimos obtener tu ubicación. Puedes continuar normalmente con la dirección.'}</p>}
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
        <div className="flex justify-between text-sm"><span>Productos</span><strong>{money(productsSubtotal)}</strong></div>
        <div className="mt-2 flex justify-between text-sm"><span>Toppings y extras</span><strong>{money(toppingsSubtotal)}</strong></div>
        <div className="mt-2 flex justify-between border-t border-cande-100 pt-2 text-sm"><span>Subtotal</span><strong>{money(subtotal)}</strong></div>
        <div className="mt-2 flex justify-between text-sm"><span>Envío según distancia</span><strong>{quoteLoading?'Calculando…':distanceEnabled&&!deliveryQuote?'Comparte ubicación':money(shipping)}</strong></div>
        {type==='delivery'&&deliveryQuote?.distanceKm&&<div className="mt-2 flex justify-between text-sm text-cande-700"><span>Distancia aproximada</span><strong>{Number(deliveryQuote.distanceKm).toFixed(1)} km</strong></div>}
        {type==='delivery'&&deliveryQuote&&!deliveryQuote.serviceable&&<p className="mt-3 rounded-md bg-red-50 p-3 text-sm font-bold text-red-700">Por el momento esta dirección está fuera de nuestra zona de entrega.</p>}
        <div className="mt-2 flex justify-between text-sm"><span>Descuento</span><strong>{money(discount)}</strong></div>
        <div className="mt-4 flex justify-between border-t pt-4 text-lg"><strong>Total</strong><strong className="text-cande-700">{money(total)}</strong></div>
      </section>

      <button disabled={!items.length||saving||(type==='delivery'&&distanceEnabled&&(quoteLoading||!deliveryQuote?.serviceable))} className="flex h-14 w-full items-center justify-center gap-2 rounded-full bg-[#25D366] px-5 font-bold text-white disabled:opacity-40">
        <MessageCircle size={20} /> {saving?'Guardando pedido…':user?'Enviar pedido por WhatsApp':'Crear cuenta para continuar'}
      </button>
      <p className="text-center text-xs text-zinc-500">Primero guardaremos tu pedido. Las Fresas Cande se acreditan al pagarlo o completarlo; después abriremos WhatsApp.</p>
    </form>
  </main>
}
