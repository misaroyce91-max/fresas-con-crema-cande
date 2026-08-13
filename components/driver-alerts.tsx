'use client'

import {useCallback,useEffect,useRef,useState} from 'react'
import {usePathname} from 'next/navigation'
import {Bell,Check} from 'lucide-react'
import {useAuth} from '@/components/auth-provider'
import {supabase} from '@/lib/supabase'

const STORAGE_KEY='cande-driver-alerted-requests'

export function DriverAlerts(){
 const pathname=usePathname(),{user}=useAuth(),[enabled,setEnabled]=useState(false),[testing,setTesting]=useState(false)
 const audio=useRef<AudioContext|null>(null),seen=useRef<Set<string>>(new Set())

 const sound=useCallback(()=>{
  const context=audio.current
  if(!context)return
  ;[0,0.22,0.44].forEach((delay,index)=>{
   const oscillator=context.createOscillator(),gain=context.createGain(),start=context.currentTime+delay
   oscillator.type='square';oscillator.frequency.value=index===1?740:980
   gain.gain.setValueAtTime(0.0001,start);gain.gain.exponentialRampToValueAtTime(0.32,start+0.02);gain.gain.exponentialRampToValueAtTime(0.0001,start+0.18)
   oscillator.connect(gain);gain.connect(context.destination);oscillator.start(start);oscillator.stop(start+0.2)
  })
 },[])

 const alertPhone=useCallback(async(id:string,orderNumber?:number)=>{
  if(seen.current.has(id))return
  seen.current.add(id);sessionStorage.setItem(STORAGE_KEY,JSON.stringify([...seen.current].slice(-100)))
  sound();navigator.vibrate?.([350,120,350,120,500])
  if(Notification.permission==='granted'){
   const registration=await navigator.serviceWorker?.ready
   await registration?.showNotification('Nueva entrega Cande',{body:orderNumber?`Solicitud CAN-${String(orderNumber).padStart(6,'0')}`:'Hay una nueva solicitud disponible',icon:'/icons/cande-driver-192.png',badge:'/icons/cande-driver-192.png',tag:`delivery-${id}`,data:{url:'/driver'}})
  }
 },[sound])

 async function enable(){
  setTesting(true)
  audio.current ||= new AudioContext()
  await audio.current.resume()
  if('Notification'in window&&Notification.permission==='default')await Notification.requestPermission()
  setEnabled(true);sound();navigator.vibrate?.([250,100,250])
  setTimeout(()=>setTesting(false),900)
 }

 useEffect(()=>{
  try{seen.current=new Set(JSON.parse(sessionStorage.getItem(STORAGE_KEY)||'[]'))}catch{seen.current=new Set()}
 },[])

 useEffect(()=>{
  if(!enabled||!supabase||!user||user.app_metadata.role!=='DRIVER')return
  const client=supabase
  const channel=client.channel(`driver-audio-alerts-${user.id}`).on('postgres_changes',{event:'INSERT',schema:'public',table:'delivery_requests'},async payload=>{
   const request=payload.new as {id:string;order_id:string}
   const{data}=await client.rpc('driver_available_requests')
   const visible=(data||[]).find((item:any)=>item.id===request.id)
   if(visible)await alertPhone(request.id,visible.order_number)
  }).subscribe()
  return()=>{client.removeChannel(channel)}
 },[alertPhone,enabled,user])

 if(pathname!=='/driver'||!user||user.app_metadata.role!=='DRIVER')return null
 return <div className="fixed inset-x-4 bottom-5 z-[70] mx-auto max-w-xl"><button type="button" onClick={enable} className={`flex h-14 w-full items-center justify-center gap-2 rounded-full px-5 font-black text-white shadow-xl ${enabled?'bg-emerald-700':'bg-cande-500'}`}>{enabled?<Check size={20}/>:<Bell size={20}/>} {enabled?'🔔 Alertas activadas':testing?'Probando alertas...':'🔔 ACTIVAR ALERTAS'}</button></div>
}
