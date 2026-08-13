'use client'
import {createContext,useContext,useEffect,useMemo,useState} from 'react'
import {products as seedProducts,toppings as seedToppings,rewards as seedRewards,promotions as seedPromotions,Product,Promotion} from '@/lib/data'

export type ManagedProduct=Product&{active:boolean;specialty:boolean;featured:boolean;favorite:boolean;sortOrder:number}
export type ManagedTopping={name:string;price:number;active:boolean;productIds:string[]}
export type ManagedReward={name:string;points:number;icon:string;active:boolean}
export type ManagedPromotion=Promotion&{active:boolean;productIds:string[];discountPesos:number;discountPercent:number;extraPoints:number;doublePoints:boolean;freeShipping:boolean;comboPrice:number|null}
export type StoreConfig={products:ManagedProduct[];toppings:ManagedTopping[];rewards:ManagedReward[];promotions:ManagedPromotion[];shippingFee:number;pointsPerPeso:number;hero:{title:string;description:string;image:string;button:string}}
const initial:StoreConfig={products:seedProducts.map((p,i)=>({...p,active:true,specialty:i<3,featured:i<4,favorite:i<3,sortOrder:i})),toppings:seedToppings.map(t=>({...t,active:true,productIds:[]})),rewards:seedRewards.map(r=>({...r,active:true})),promotions:seedPromotions.map(p=>({...p,active:true,productIds:[],discountPesos:0,discountPercent:0,extraPoints:0,doublePoints:p.id.includes('double'),freeShipping:false,comboPrice:null})),shippingFee:35,pointsPerPeso:.1,hero:{title:'Tu antojo tiene recompensa',description:'Fresas frescas, crema de la casa y algo rico esperándote.',image:'/images/cande-classic.png',button:'Ver menú'}}
const C=createContext<{config:StoreConfig;save:(c:StoreConfig)=>void}|null>(null)
export function StoreProvider({children}:{children:React.ReactNode}){const[config,setConfig]=useState(initial);useEffect(()=>{try{const saved=localStorage.getItem('cande-store-config');if(saved)setConfig(JSON.parse(saved))}catch{}},[]);function save(next:StoreConfig){setConfig(next);localStorage.setItem('cande-store-config',JSON.stringify(next));dispatchEvent(new CustomEvent('cande-store-updated',{detail:next}))}return <C.Provider value={{config,save}}>{children}</C.Provider>}
export function useStore(){const value=useContext(C);if(!value)throw new Error('useStore fuera de StoreProvider');return value}
