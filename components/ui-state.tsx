import Link from 'next/link'
import { PackageOpen } from 'lucide-react'

export function MenuSkeleton() {
  return <div className="mt-6 grid gap-5 md:grid-cols-2" aria-label="Cargando menú" aria-busy="true">
    {[0, 1, 2, 3].map(index => <article className="card overflow-hidden" key={index}>
      <div className="skeleton aspect-[4/5]" />
      <div className="space-y-3 p-5"><div className="skeleton h-3 w-20" /><div className="skeleton h-7 w-2/3" /><div className="skeleton h-4 w-full" /><div className="skeleton h-12 w-full" /></div>
    </article>)}
  </div>
}

export function EmptyMenu() {
  return <section className="empty-state mt-8" aria-live="polite">
    <span className="empty-state-icon"><PackageOpen size={27} /></span>
    <h2 className="mt-4 text-xl font-black">El menú se está preparando</h2>
    <p className="mt-2 max-w-sm text-sm leading-relaxed text-zinc-600">Aún no hay productos disponibles. Vuelve a intentarlo en unos minutos o escríbenos para ayudarte.</p>
    <Link href="/" className="mt-5 inline-flex h-11 items-center justify-center rounded-full bg-cande-500 px-5 text-sm font-bold text-white">Volver al inicio</Link>
  </section>
}
