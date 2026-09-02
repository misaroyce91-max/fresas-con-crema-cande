'use client'

import { Heart } from 'lucide-react'
import { useFavorites } from '@/components/favorites-provider'

export function FavoriteButton({ productId, className = '' }: { productId: string; className?: string }) {
  const { isFavorite, toggleFavorite } = useFavorites()
  const favorite = isFavorite(productId)

  return <button
    type="button"
    onClick={() => { void toggleFavorite(productId) }}
    aria-label={favorite ? 'Quitar de favoritos' : 'Guardar en favoritos'}
    aria-pressed={favorite}
    className={`grid h-11 w-11 place-items-center rounded-full bg-white/95 text-cande-600 shadow-sm transition hover:scale-105 focus:outline-none focus:ring-2 focus:ring-cande-500 ${className}`}
  >
    <Heart size={20} fill={favorite ? 'currentColor' : 'none'} />
  </button>
}
