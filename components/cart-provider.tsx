'use client'
import {createContext,useContext,useEffect,useMemo,useState} from 'react'

export type CartItem={key:string;productId:string;name:string;image:string;size:string;toppings:{name:string;price:number}[];quantity:number;unitPrice:number;redemptionId?:string}
export type CartRedemption={id:string;type:'fixed_discount'|'free_product';label:string;value?:number;productId?:string;sizeName?:string}
type CartCtx={items:CartItem[];redemptions:CartRedemption[];add:(item:Omit<CartItem,'key'>)=>void;addRedemption:(reward:CartRedemption,item?:Omit<CartItem,'key'>)=>void;removeRedemption:(id:string)=>void;update:(key:string,quantity:number)=>void;clear:()=>void;count:number;subtotal:number;rewardDiscount:number}
const CartContext=createContext<CartCtx|null>(null)

export function CartProvider({children}:{children:React.ReactNode}){
 const[items,setItems]=useState<CartItem[]>([]),[redemptions,setRedemptions]=useState<CartRedemption[]>([])
 useEffect(()=>{try{setItems(JSON.parse(localStorage.getItem('cande-cart')||'[]'));setRedemptions(JSON.parse(localStorage.getItem('cande-redemptions')||'[]'))}catch{}},[])
 useEffect(()=>{localStorage.setItem('cande-cart',JSON.stringify(items))},[items])
 useEffect(()=>{localStorage.setItem('cande-redemptions',JSON.stringify(redemptions))},[redemptions])
 useEffect(()=>{const refresh=(event:Event)=>{const config=(event as CustomEvent).detail;if(!config?.products)return;setItems(current=>current.map(item=>{if(item.redemptionId)return item;const product=config.products.find((p:any)=>p.id===item.productId);if(!product)return item;const selected=item.toppings.map(t=>config.toppings.find((x:any)=>x.name===t.name)||t);return{...item,name:product.name,image:product.image,toppings:selected,unitPrice:Number(product.prices[item.size]||item.unitPrice)+selected.reduce((n:number,t:any)=>n+Number(t.price||0),0)}}))};addEventListener('cande-store-updated',refresh);return()=>removeEventListener('cande-store-updated',refresh)},[])
 const value=useMemo<CartCtx>(()=>({items,redemptions,add:item=>setItems(v=>[...v,{...item,key:crypto.randomUUID()}]),addRedemption:(reward,item)=>{setRedemptions(v=>v.some(x=>x.id===reward.id)?v:[...v,reward]);if(item)setItems(v=>v.some(x=>x.redemptionId===reward.id)?v:[...v,{...item,key:crypto.randomUUID()}])},removeRedemption:id=>{setRedemptions(v=>v.filter(x=>x.id!==id));setItems(v=>v.filter(x=>x.redemptionId!==id))},update:(key,quantity)=>setItems(v=>v.map(i=>i.key===key&&i.redemptionId?i:i.key===key?{...i,quantity}:i).filter(i=>i.quantity>0)),clear:()=>{setItems([]);setRedemptions([])},count:items.reduce((n,i)=>n+i.quantity,0),subtotal:items.reduce((n,i)=>n+i.unitPrice*i.quantity,0),rewardDiscount:redemptions.filter(r=>r.type==='fixed_discount').reduce((n,r)=>n+Number(r.value||0),0)}),[items,redemptions])
 return <CartContext.Provider value={value}>{children}</CartContext.Provider>
}
export const useCart=()=>{const c=useContext(CartContext);if(!c)throw new Error('useCart fuera de provider');return c}
