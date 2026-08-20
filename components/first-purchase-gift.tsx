'use client'
import {useEffect,useState} from 'react'
import {Gift} from 'lucide-react'
import {supabase} from '@/lib/supabase'
import {useAuth} from '@/components/auth-provider'

export type FirstPurchaseOffer={eligible:boolean;promotionId?:string;productId?:string;productName?:string;sizeName?:string;referencePrice?:number}
export function useFirstPurchaseOffer(){const{user}=useAuth();const[offer,setOffer]=useState<FirstPurchaseOffer>({eligible:false});useEffect(()=>{let active=true;if(!user||!supabase){setOffer({eligible:false});return}supabase.rpc('first_purchase_offer').then(({data})=>{if(active&&data)setOffer(data as FirstPurchaseOffer)});return()=>{active=false}},[user]);return offer}
export function FirstPurchaseGift({compact=false}:{compact?:boolean}){const offer=useFirstPurchaseOffer();if(!offer.eligible)return null;return <section className={`rounded-md border-2 border-cande-200 bg-cande-50 ${compact?'p-4':'p-5'}`}><p className="flex items-center gap-2 font-black text-cande-800"><Gift size={20}/>🎁 ¡Tienes {offer.productName} {offer.sizeName} GRATIS!</p><p className="mt-1 text-sm text-zinc-600">Se agregarán automáticamente a tu primera compra. El servidor validará que puedas usar el regalo.</p></section>}
