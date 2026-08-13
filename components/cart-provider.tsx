'use client'
import { createContext, useContext, useEffect, useMemo, useState } from 'react'

export type CartItem = { key:string; productId:string; name:string; image:string; size:string; toppings:{name:string;price:number}[]; quantity:number; unitPrice:number }
type CartCtx = { items:CartItem[]; add:(item:Omit<CartItem,'key'>)=>void; update:(key:string,quantity:number)=>void; clear:()=>void; count:number; subtotal:number }
const CartContext = createContext<CartCtx | null>(null)
export function CartProvider({children}:{children:React.ReactNode}) {
 const [items,setItems] = useState<CartItem[]>([])
 useEffect(()=>{ const saved=localStorage.getItem('cande-cart'); if(saved) try{setItems(JSON.parse(saved))}catch{} },[])
 useEffect(()=>{ localStorage.setItem('cande-cart',JSON.stringify(items)) },[items])
 useEffect(()=>{const refresh=(event:Event)=>{const config=(event as CustomEvent).detail;if(!config?.products)return;setItems(current=>current.map(item=>{const product=config.products.find((p:any)=>p.id===item.productId);if(!product)return item;const selected=item.toppings.map(t=>config.toppings.find((x:any)=>x.name===t.name)||t);return {...item,name:product.name,image:product.image,toppings:selected,unitPrice:Number(product.prices[item.size]||item.unitPrice)+selected.reduce((n:number,t:any)=>n+Number(t.price||0),0)}}))};addEventListener('cande-store-updated',refresh);return()=>removeEventListener('cande-store-updated',refresh)},[])
 const value=useMemo(()=>({items,add:(item:Omit<CartItem,'key'>)=>setItems(v=>[...v,{...item,key:crypto.randomUUID()}]),update:(key:string,quantity:number)=>setItems(v=>quantity<1?v.filter(i=>i.key!==key):v.map(i=>i.key===key?{...i,quantity}:i)),clear:()=>setItems([]),count:items.reduce((n,i)=>n+i.quantity,0),subtotal:items.reduce((n,i)=>n+i.unitPrice*i.quantity,0)}),[items])
 return <CartContext.Provider value={value}>{children}</CartContext.Provider>
}
export const useCart=()=>{const c=useContext(CartContext);if(!c)throw new Error('useCart fuera de provider');return c}
