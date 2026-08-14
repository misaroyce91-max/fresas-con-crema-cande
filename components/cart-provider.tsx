'use client'

import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import { cartSubtotal } from '@/lib/pricing'

export type CartItem = {
  key: string
  productId: string
  name: string
  image: string
  size: string
  toppings: { id?: string; name: string; price: number }[]
  quantity: number
  unitPrice: number
  redemptionId?: string
}
export type CartRedemption = { id: string; type: 'fixed_discount' | 'free_product'; label: string; value?: number; productId?: string; sizeName?: string }
type CartCtx = { items: CartItem[]; redemptions: CartRedemption[]; add: (item: Omit<CartItem, 'key'>) => void; addRedemption: (reward: CartRedemption, item?: Omit<CartItem, 'key'>) => void; removeRedemption: (id: string) => void; update: (key: string, quantity: number) => void; clear: () => void; count: number; subtotal: number; rewardDiscount: number }
const CartContext = createContext<CartCtx | null>(null)

export function CartProvider({ children }: { children: React.ReactNode }) {
  const [items, setItems] = useState<CartItem[]>([])
  const [redemptions, setRedemptions] = useState<CartRedemption[]>([])

  useEffect(() => {
    try {
      setItems(JSON.parse(localStorage.getItem('cande-cart') || '[]'))
      setRedemptions(JSON.parse(localStorage.getItem('cande-redemptions') || '[]'))
    } catch {}
  }, [])
  useEffect(() => { localStorage.setItem('cande-cart', JSON.stringify(items)) }, [items])
  useEffect(() => { localStorage.setItem('cande-redemptions', JSON.stringify(redemptions)) }, [redemptions])
  useEffect(() => {
    const refresh = (event: Event) => {
      const config = (event as CustomEvent).detail
      if (!config?.products) return
      setItems((current) => current.map((item) => {
        if (item.redemptionId) return item
        const product = config.products.find((candidate: any) => candidate.id === item.productId)
        if (!product) return item
        const selected = item.toppings.map((topping) =>
          config.toppings.find((candidate: any) => candidate.id === topping.id)
          || config.toppings.find((candidate: any) => candidate.name === topping.name)
          || topping,
        )
        return { ...item, name: product.name, image: product.image, toppings: selected, unitPrice: Number(product.prices[item.size] || item.unitPrice) }
      }))
    }
    addEventListener('cande-store-updated', refresh)
    return () => removeEventListener('cande-store-updated', refresh)
  }, [])

  const value = useMemo<CartCtx>(() => ({
    items,
    redemptions,
    add: (item) => setItems((current) => [...current, { ...item, key: crypto.randomUUID() }]),
    addRedemption: (reward, item) => {
      setRedemptions((current) => current.some((entry) => entry.id === reward.id) ? current : [...current, reward])
      if (item) setItems((current) => current.some((entry) => entry.redemptionId === reward.id) ? current : [...current, { ...item, key: crypto.randomUUID() }])
    },
    removeRedemption: (id) => {
      setRedemptions((current) => current.filter((entry) => entry.id !== id))
      setItems((current) => current.filter((entry) => entry.redemptionId !== id))
    },
    update: (key, quantity) => setItems((current) => current.map((item) => item.key === key && !item.redemptionId ? { ...item, quantity } : item).filter((item) => item.quantity > 0)),
    clear: () => { setItems([]); setRedemptions([]) },
    count: items.reduce((total, item) => total + item.quantity, 0),
    subtotal: cartSubtotal(items),
    rewardDiscount: redemptions.filter((reward) => reward.type === 'fixed_discount').reduce((total, reward) => total + Number(reward.value || 0), 0),
  }), [items, redemptions])

  return <CartContext.Provider value={value}>{children}</CartContext.Provider>
}

export const useCart = () => {
  const context = useContext(CartContext)
  if (!context) throw new Error('useCart fuera de provider')
  return context
}
