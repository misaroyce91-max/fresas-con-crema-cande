'use client'

import { useEffect, useState } from 'react'
import { usePathname } from 'next/navigation'
import { Download, Share2, Smartphone, X } from 'lucide-react'

type InstallEvent = Event & {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

const DISMISSED_KEY = 'cande-install-dismissed-at'
const DISMISS_FOR_MS = 14 * 24 * 60 * 60 * 1000

function isStandalone() {
  return window.matchMedia('(display-mode: standalone)').matches
    || Boolean((navigator as Navigator & { standalone?: boolean }).standalone)
}

function isIosDevice() {
  return /iPad|iPhone|iPod/.test(navigator.userAgent)
    || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
}

function isAndroidDevice() {
  return /Android/i.test(navigator.userAgent)
}

export function InstallCande() {
  const path = usePathname()
  const [installEvent, setInstallEvent] = useState<InstallEvent | null>(null)
  const [eligible, setEligible] = useState(false)
  const [platform, setPlatform] = useState<'ios' | 'android' | null>(null)
  const [showIosHelp, setShowIosHelp] = useState(false)

  useEffect(() => {
    const dismissedAt = Number(localStorage.getItem(DISMISSED_KEY) || 0)
    const dismissedRecently = Date.now() - dismissedAt < DISMISS_FOR_MS
    const iosDevice = isIosDevice()
    const androidDevice = isAndroidDevice()
    setPlatform(iosDevice ? 'ios' : androidDevice ? 'android' : null)
    if (!isStandalone() && !dismissedRecently && (iosDevice || androidDevice)) setEligible(true)

    const ready = (event: Event) => {
      event.preventDefault()
      if (isStandalone() || dismissedRecently) return
      setInstallEvent(event as InstallEvent)
      setEligible(true)
    }
    const installed = () => {
      localStorage.removeItem(DISMISSED_KEY)
      setInstallEvent(null)
      setEligible(false)
      setShowIosHelp(false)
    }
    addEventListener('beforeinstallprompt', ready)
    addEventListener('appinstalled', installed)
    return () => {
      removeEventListener('beforeinstallprompt', ready)
      removeEventListener('appinstalled', installed)
    }
  }, [])

  if (!eligible || path.startsWith('/admin') || path.startsWith('/driver') || path.startsWith('/qr')) return null

  const dismiss = () => {
    localStorage.setItem(DISMISSED_KEY, String(Date.now()))
    setEligible(false)
    setShowIosHelp(false)
  }
  const install = async () => {
    if (!installEvent) {
      setShowIosHelp(true)
      return
    }
    await installEvent.prompt()
    const choice = await installEvent.userChoice
    if (choice.outcome === 'accepted') {
      setInstallEvent(null)
      setEligible(false)
    }
  }

  return <aside role="dialog" aria-label="Instalar Fresas con Crema Cande" className="fixed inset-x-3 bottom-[142px] z-50 mx-auto max-w-md overflow-hidden rounded-lg border border-cande-200 bg-white shadow-[0_18px_55px_rgba(81,20,39,.24)] md:bottom-6">
    <button onClick={dismiss} aria-label="Cerrar invitación" className="absolute right-2 top-2 grid h-10 w-10 place-items-center rounded-full text-zinc-500"><X size={19} /></button>
    <div className="flex gap-4 bg-cande-50 p-5 pr-12">
      <span className="grid h-12 w-12 shrink-0 place-items-center rounded-full bg-cande-500 text-white"><Smartphone size={23} /></span>
      <div><h2 className="text-lg font-black text-cande-900">🍓 ¡Ten Fresas Cande en tu celular!</h2><p className="mt-2 text-sm leading-relaxed text-zinc-700">Instala nuestra app para pedir más rápido, consultar tus 🍓 Fresas Cande, recompensas y promociones.</p></div>
    </div>
    {showIosHelp ? <div className="p-5 pt-4">
      <h3 className="flex items-center gap-2 font-black"><Share2 size={18} className="text-cande-600" />Para instalar en {platform === 'ios' ? 'iPhone' : 'Android'}</h3>
      {platform === 'ios' ? <ol className="mt-3 space-y-2 text-sm text-zinc-700"><li>1. Abre esta página en Safari.</li><li>2. Toca Compartir.</li><li>3. Selecciona Agregar a pantalla de inicio.</li><li>4. Toca Agregar.</li></ol> : <ol className="mt-3 space-y-2 text-sm text-zinc-700"><li>1. Abre el menú ⋮ de Chrome.</li><li>2. Toca Instalar aplicación o Agregar a pantalla principal.</li><li>3. Confirma con Instalar.</li></ol>}
      <button onClick={() => setShowIosHelp(false)} className="mt-4 h-11 w-full rounded-full border border-cande-300 font-bold text-cande-700">Entendido</button>
    </div> : <div className="grid gap-2 p-4">
      <button onClick={install} className="flex h-13 items-center justify-center gap-2 rounded-full bg-cande-500 py-3 font-black text-white shadow-lg shadow-cande-200"><Download size={19} />📲 INSTALAR APP</button>
      <button onClick={dismiss} className="h-10 text-sm font-bold text-zinc-500">Ahora no</button>
      {platform === 'ios' && <p className="text-center text-[11px] text-zinc-500">En iPhone te mostraremos los pasos para agregarla.</p>}
    </div>}
  </aside>
}
