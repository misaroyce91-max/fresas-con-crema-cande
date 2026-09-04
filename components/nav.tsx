'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { Gift, Home, Menu as MenuIcon, ReceiptText, ShoppingBag, UserRound } from 'lucide-react'
import { money } from '@/lib/data'
import { useCart } from './cart-provider'

const links = [
  ['/', 'Inicio', Home],
  ['/menu', 'Menú', MenuIcon],
  ['/orders', 'Pedidos', ReceiptText],
  ['/rewards', 'Rewards', Gift],
  ['/account', 'Cuenta', UserRound],
] as const

export function Nav() {
  const path = usePathname()
  const { count, subtotal } = useCart()

  if (path.startsWith('/admin') || path.startsWith('/driver') || path.startsWith('/qr')) return null

  const orderHref = count > 0 ? '/cart' : '/menu'
  const showOrderCta = path !== '/cart' && path !== '/checkout'

  return (
    <>
      {showOrderCta && (
        <Link
          href={orderHref}
          aria-label={count > 0 ? `Pedir ahora, ${count} productos en el carrito por ${money(subtotal)}` : 'Pedir ahora, elegir productos'}
          className="fixed bottom-[68px] left-1/2 z-40 flex h-14 max-w-[calc(100vw-24px)] -translate-x-1/2 items-center gap-2 whitespace-nowrap rounded-full bg-cande-500 px-5 font-bold text-white shadow-[0_12px_32px_rgba(242,46,98,.4)] transition active:scale-95 md:bottom-5"
        >
          <ShoppingBag size={20} />
          Pedir ahora
          {count > 0 && (
            <>
              <span className="grid h-6 min-w-6 place-items-center rounded-full bg-white px-1 text-xs text-cande-600">{count}</span>
              <span className="text-sm text-white/90">· {money(subtotal)}</span>
            </>
          )}
        </Link>
      )}
      <nav className="fixed inset-x-0 bottom-0 z-30 border-t border-cande-100 bg-white/95 pb-[max(8px,env(safe-area-inset-bottom))] pt-2 backdrop-blur">
        <div className="mx-auto grid max-w-xl grid-cols-5 md:max-w-3xl">
          {links.map(([href, label, Icon]) => {
            const active = href === '/' ? path === href : path === href || path.startsWith(`${href}/`)
            return (
              <Link aria-current={active?'page':undefined} key={href} href={href} className={`relative flex min-h-12 min-w-0 flex-col items-center justify-center gap-1 rounded-2xl py-1 text-[10px] font-bold ${active ? 'text-cande-600' : 'text-zinc-500'}`}>
                <span className={`grid h-7 min-w-9 place-items-center rounded-full ${active?'bg-cande-100':''}`}><Icon size={19} strokeWidth={active ? 2.7 : 2} /></span>
                <span>{label}</span>
              </Link>
            )
          })}
        </div>
      </nav>
    </>
  )
}
