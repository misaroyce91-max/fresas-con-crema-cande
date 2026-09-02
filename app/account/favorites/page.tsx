'use client'

import Image from 'next/image'
import Link from 'next/link'
import { Heart, Menu as MenuIcon } from 'lucide-react'
import { FavoriteButton } from '@/components/favorite-button'
import { useAuth } from '@/components/auth-provider'
import { useFavorites } from '@/components/favorites-provider'
import { useStore } from '@/components/store-provider'

export default function FavoritesPage() {
  const { user, loading: authLoading } = useAuth()
  const { config, loading: storeLoading } = useStore()
  const { favoriteIds, loading, message } = useFavorites()
  const products = config.products.filter((product) => favoriteIds.has(product.id))

  if (authLoading || storeLoading || loading) return <main className="page max-w-2xl"><p className="text-sm text-zinc-500">Cargando tus favoritos...</p></main>
  if (!user) return <main className="page max-w-2xl"><p className="text-xs font-bold uppercase text-cande-500">Tu cuenta</p><h1 className="mt-1 text-3xl font-black">Tus favoritos</h1><p className="mt-3 text-sm text-zinc-500">Inicia sesión para guardar y ver tus antojos favoritos en cualquier dispositivo.</p><Link href="/account?next=/account/favorites" className="mt-6 inline-flex rounded-full bg-cande-500 px-5 py-3 text-sm font-bold text-white">Iniciar sesión</Link></main>

  return <main className="page max-w-2xl">
    <p className="text-xs font-bold uppercase text-cande-500">Tu cuenta</p>
    <h1 className="mt-1 flex items-center gap-2 text-3xl font-black"><Heart className="fill-cande-500 text-cande-500" />Tus favoritos</h1>
    <p className="mt-2 text-sm text-zinc-500">Guarda tus fresas preferidas y encuéntralas rápido cuando tengas antojo.</p>
    {message && <p role="status" className="mt-4 rounded-md bg-cande-50 p-3 text-sm font-bold text-cande-800">{message}</p>}
    {!products.length ? <section className="mt-8 rounded-lg border border-dashed border-cande-200 bg-cande-50 p-7 text-center"><Heart className="mx-auto text-cande-500" size={28}/><h2 className="mt-3 text-lg font-black">Aún no tienes favoritos</h2><p className="mt-2 text-sm text-zinc-500">Toca el corazón de cualquier producto del menú para guardarlo aquí.</p><Link href="/menu" className="mt-5 inline-flex items-center gap-2 rounded-full bg-cande-500 px-5 py-3 text-sm font-bold text-white"><MenuIcon size={17}/>Ver menú</Link></section> : <div className="mt-7 grid gap-4 sm:grid-cols-2">{products.map((product) => <article key={product.id} className="card relative overflow-hidden"><div className="relative aspect-[4/3] bg-cande-50"><Image src={product.image} alt={product.name} fill className="object-contain" unoptimized/><FavoriteButton productId={product.id} className="absolute right-3 top-3"/></div><div className="p-4"><p className="text-xs font-bold uppercase text-cande-500">{product.category}</p><h2 className="mt-1 text-lg font-black">{product.name}</h2><p className="mt-1 line-clamp-2 text-sm text-zinc-500">{product.description}</p><Link href="/menu" className="mt-4 inline-flex text-sm font-bold text-cande-700">Personalizar y agregar</Link></div></article>)}</div>}
  </main>
}
