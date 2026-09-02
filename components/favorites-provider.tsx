'use client'

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { useAuth } from '@/components/auth-provider'
import { supabase } from '@/lib/supabase'

type FavoritesValue = {
  favoriteIds: Set<string>
  loading: boolean
  message: string | null
  isFavorite: (productId: string) => boolean
  toggleFavorite: (productId: string) => Promise<boolean>
  refresh: () => Promise<void>
}

const FavoritesContext = createContext<FavoritesValue | null>(null)

export function FavoritesProvider({ children }: { children: React.ReactNode }) {
  const { user } = useAuth()
  const [favoriteIds, setFavoriteIds] = useState<Set<string>>(new Set())
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    if (!supabase || !user) {
      setFavoriteIds(new Set())
      return
    }
    setLoading(true)
    const { data, error } = await supabase
      .from('customer_favorites')
      .select('product_id')
      .eq('customer_id', user.id)
      .order('created_at', { ascending: false })
    setLoading(false)
    if (error) {
      setMessage('No pudimos cargar tus favoritos. Intenta nuevamente.')
      return
    }
    setFavoriteIds(new Set((data || []).map((item) => item.product_id)))
  }, [user])

  useEffect(() => {
    setMessage(null)
    void refresh()
  }, [refresh])

  const toggleFavorite = useCallback(async (productId: string) => {
    if (!supabase || !user) {
      setMessage('Inicia sesión para guardar tus favoritos.')
      return false
    }
    setMessage(null)
    if (favoriteIds.has(productId)) {
      const { error } = await supabase
        .from('customer_favorites')
        .delete()
        .eq('customer_id', user.id)
        .eq('product_id', productId)
      if (error) {
        setMessage('No pudimos quitar este favorito. Intenta nuevamente.')
        return false
      }
      setFavoriteIds((current) => {
        const next = new Set(current)
        next.delete(productId)
        return next
      })
      return true
    }

    const { error } = await supabase
      .from('customer_favorites')
      .insert({ customer_id: user.id, product_id: productId })
    if (error && error.code !== '23505') {
      setMessage('No pudimos guardar este favorito. Intenta nuevamente.')
      return false
    }
    setFavoriteIds((current) => new Set(current).add(productId))
    return true
  }, [favoriteIds, user])

  const value = useMemo<FavoritesValue>(() => ({
    favoriteIds,
    loading,
    message,
    isFavorite: (productId) => favoriteIds.has(productId),
    toggleFavorite,
    refresh,
  }), [favoriteIds, loading, message, refresh, toggleFavorite])

  return <FavoritesContext.Provider value={value}>{children}</FavoritesContext.Provider>
}

export function useFavorites() {
  const value = useContext(FavoritesContext)
  if (!value) throw new Error('useFavorites fuera de FavoritesProvider')
  return value
}
