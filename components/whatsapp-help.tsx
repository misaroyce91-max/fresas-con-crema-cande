'use client'

import { MessageCircle } from 'lucide-react'
import { usePathname } from 'next/navigation'

const phone = process.env.NEXT_PUBLIC_BUSINESS_WHATSAPP || '527222219560'

function context(path:string){
 if(path.startsWith('/checkout'))return 'Hola, necesito ayuda para completar mi pedido.'
 if(path.startsWith('/orders'))return 'Hola, necesito ayuda con el seguimiento de mi pedido.'
 if(path.startsWith('/cart'))return 'Hola, tengo una duda sobre mi carrito.'
 if(path.startsWith('/menu'))return 'Hola, quisiera consultar un producto del menú.'
 if(path.startsWith('/rewards'))return 'Hola, necesito ayuda con mis recompensas.'
 return 'Hola, necesito atención de Fresas Cande.'
}

export function WhatsAppHelp(){
 const path=usePathname()
 if(path.startsWith('/admin')||path.startsWith('/driver')||path.startsWith('/qr'))return null
 const href=`https://wa.me/${phone}?text=${encodeURIComponent(context(path))}`
 return <a href={href} target="_blank" rel="noreferrer" aria-label="Solicitar ayuda por WhatsApp" className="fixed bottom-[76px] left-3 z-30 grid h-12 w-12 place-items-center rounded-2xl border border-emerald-400/30 bg-emerald-500 text-white shadow-float md:bottom-5 md:left-5"><MessageCircle size={22}/></a>
}
