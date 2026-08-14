'use client'

import { useEffect, useState } from 'react'
import { usePathname } from 'next/navigation'
import { Download, Share2, Smartphone, X } from 'lucide-react'

type InstallEvent = Event & { prompt: () => Promise<void>; userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }> }
type Platform = 'ios' | 'android' | 'other'
const DISMISSED_KEY = 'cande-install-dismissed-at'
const DISMISS_FOR_MS = 14 * 24 * 60 * 60 * 1000

function isStandalone() {
  return window.matchMedia('(display-mode: standalone)').matches
    || Boolean((navigator as Navigator & { standalone?: boolean }).standalone)
}

function detectPlatform(): Platform {
  const ios = /iPad|iPhone|iPod/.test(navigator.userAgent)
    || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
  if (ios) return 'ios'
  return /Android/i.test(navigator.userAgent) ? 'android' : 'other'
}

function useInstallState() {
  const [installEvent, setInstallEvent] = useState<InstallEvent | null>(null)
  const [installed, setInstalled] = useState(true)
  const [platform, setPlatform] = useState<Platform>('other')
  const [showHelp, setShowHelp] = useState(false)

  useEffect(() => {
    setInstalled(isStandalone())
    setPlatform(detectPlatform())
    const ready = (event: Event) => { event.preventDefault(); setInstallEvent(event as InstallEvent); setInstalled(false) }
    const completed = () => { localStorage.removeItem(DISMISSED_KEY); setInstallEvent(null); setInstalled(true); setShowHelp(false) }
    addEventListener('beforeinstallprompt', ready)
    addEventListener('appinstalled', completed)
    return () => { removeEventListener('beforeinstallprompt', ready); removeEventListener('appinstalled', completed) }
  }, [])

  const install = async () => {
    if (!installEvent) { setShowHelp(true); return }
    await installEvent.prompt()
    const choice = await installEvent.userChoice
    if (choice.outcome === 'accepted') { setInstallEvent(null); setInstalled(true) }
    else setShowHelp(true)
  }
  return { installed, platform, showHelp, setShowHelp, install }
}

function Instructions({ platform, close }: { platform: Platform; close: () => void }) {
  return <div className="mt-4 rounded-md border border-cande-100 bg-white p-4">
    <h3 className="flex items-center gap-2 font-black text-cande-900"><Share2 size={18} className="text-cande-600" />Cómo instalarla</h3>
    {platform === 'ios'
      ? <p className="mt-2 text-sm leading-relaxed text-zinc-700"><strong>Safari</strong> → Compartir → Agregar a pantalla de inicio → Agregar.</p>
      : <p className="mt-2 text-sm leading-relaxed text-zinc-700"><strong>Chrome ⋮</strong> → Agregar a pantalla principal o Instalar aplicación → Instalar.</p>}
    <button type="button" onClick={close} className="mt-3 h-10 w-full rounded-full border border-cande-300 text-sm font-bold text-cande-700">Entendido</button>
  </div>
}

export function InstallCandeCard({ accountOnly = false }: { accountOnly?: boolean }) {
  const path = usePathname()
  const { installed, platform, showHelp, setShowHelp, install } = useInstallState()
  if (installed || (accountOnly && path !== '/account')) return null
  return <section className="card mt-5 border border-cande-200 bg-cande-50 p-5" aria-label="Instalar Fresas Cande">
    <div className="flex items-start gap-3"><span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-cande-500 text-white"><Smartphone size={21} /></span><div><h2 className="text-lg font-black text-cande-900">📲 Instala Fresas Cande en tu celular</h2><p className="mt-1 text-sm leading-relaxed text-zinc-700">Ten nuestra app para pedir más rápido, consultar tus puntos, promociones y recompensas.</p></div></div>
    <button type="button" onClick={install} className="mt-4 flex h-12 w-full items-center justify-center gap-2 rounded-full bg-cande-500 font-black text-white"><Download size={18} />📲 INSTALAR APP</button>
    {showHelp && <Instructions platform={platform} close={() => setShowHelp(false)} />}
  </section>
}

export function InstallCande() {
  const path = usePathname()
  const { installed, platform, showHelp, setShowHelp, install } = useInstallState()
  const [dismissed, setDismissed] = useState(true)
  useEffect(() => { const at = Number(localStorage.getItem(DISMISSED_KEY) || 0); setDismissed(Date.now() - at < DISMISS_FOR_MS) }, [])
  if (installed || dismissed || path === '/' || path === '/account' || path.startsWith('/admin') || path.startsWith('/driver') || path.startsWith('/qr')) return null
  const dismiss = () => { localStorage.setItem(DISMISSED_KEY, String(Date.now())); setDismissed(true); setShowHelp(false) }
  return <aside role="dialog" aria-label="Instalar Fresas con Crema Cande" className="fixed inset-x-3 bottom-[142px] z-50 mx-auto max-w-md overflow-hidden rounded-lg border border-cande-200 bg-white shadow-[0_18px_55px_rgba(81,20,39,.24)] md:bottom-6">
    <button type="button" onClick={dismiss} aria-label="Cerrar invitación" className="absolute right-2 top-2 grid h-10 w-10 place-items-center rounded-full text-zinc-500"><X size={19} /></button>
    <div className="flex gap-4 bg-cande-50 p-5 pr-12"><span className="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-cande-500 text-white"><Smartphone size={23} /></span><div><h2 className="text-lg font-black text-cande-900">📲 Instala Fresas Cande</h2><p className="mt-2 text-sm leading-relaxed text-zinc-700">Ten Fresas Cande en tu celular para pedir más rápido, consultar tus 🍓, promociones y recompensas.</p></div></div>
    <div className="p-4"><button type="button" onClick={install} className="flex h-12 w-full items-center justify-center gap-2 rounded-full bg-cande-500 font-black text-white"><Download size={19} />📲 INSTALAR APP</button>{showHelp && <Instructions platform={platform} close={() => setShowHelp(false)} />}<button type="button" onClick={dismiss} className="mt-2 h-10 w-full text-sm font-bold text-zinc-500">Ahora no</button></div>
  </aside>
}
