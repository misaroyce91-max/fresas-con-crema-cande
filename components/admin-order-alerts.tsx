'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { Bell, BellRing, Check } from 'lucide-react'
import { supabase } from '@/lib/supabase'

type OrderInsert = { id: string; order_number: number }

export function AdminOrderAlerts() {
  const [enabled, setEnabled] = useState(false)
  const [notice, setNotice] = useState('')
  const audio = useRef<AudioContext | null>(null)
  const seen = useRef(new Set<string>())

  const sound = useCallback(() => {
    const context = audio.current
    if (!context) return
    ;[659, 880, 1047, 1319].forEach((frequency, index) => {
      const oscillator = context.createOscillator()
      const gain = context.createGain()
      const start = context.currentTime + index * 0.18
      oscillator.type = 'sine'
      oscillator.frequency.value = frequency
      gain.gain.setValueAtTime(0.0001, start)
      gain.gain.exponentialRampToValueAtTime(0.34, start + 0.025)
      gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.38)
      oscillator.connect(gain)
      gain.connect(context.destination)
      oscillator.start(start)
      oscillator.stop(start + 0.4)
    })
  }, [])

  const alertOrder = useCallback((order: OrderInsert) => {
    if (seen.current.has(order.id)) return
    seen.current.add(order.id)
    const label = `CAN-${String(order.order_number).padStart(6, '0')}`
    setNotice(`Pedido nuevo ${label}`)
    sound()
    navigator.vibrate?.([350, 140, 350, 140, 650])
    if ('Notification' in window && Notification.permission === 'granted' && document.hidden) {
      new Notification('Nuevo pedido Cande', { body: `${label} entró a la Torre de Control.`, tag: `admin-order-${order.id}` })
    }
  }, [sound])

  useEffect(() => {
    if (!enabled || !supabase) return
    const client = supabase
    const channel = client.channel('admin-new-order-alerts')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'orders' }, payload => alertOrder(payload.new as OrderInsert))
      .subscribe()
    return () => { client.removeChannel(channel) }
  }, [alertOrder, enabled])

  async function enable() {
    audio.current ||= new AudioContext()
    await audio.current.resume()
    if ('Notification' in window && Notification.permission === 'default') await Notification.requestPermission()
    setEnabled(true)
    setNotice('Alertas ADMIN activadas')
    sound()
    navigator.vibrate?.([180, 90, 180])
  }

  return <div className="mt-4 max-w-sm">
    <button type="button" onClick={enable} className={`flex min-h-12 w-full items-center justify-center gap-2 rounded-md border px-4 py-3 text-sm font-black ${enabled ? 'border-emerald-200 bg-emerald-50 text-emerald-800' : 'border-cande-200 bg-white text-cande-700'}`}>
      {enabled ? <Check size={18} /> : <Bell size={18} />}
      {enabled ? 'Alertas ADMIN activadas' : 'Activar alertas de pedidos'}
    </button>
    {notice && <p role="status" className="mt-2 flex items-center gap-2 text-xs font-bold text-cande-700"><BellRing size={15} />{notice}</p>}
  </div>
}
