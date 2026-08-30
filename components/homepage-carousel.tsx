'use client'

import Image from 'next/image'
import Link from 'next/link'
import { useCallback, useEffect, useRef, useState } from 'react'
import { ArrowRight, Volume2, VolumeX } from 'lucide-react'
import { useAuth } from '@/components/auth-provider'
import { supabase } from '@/lib/supabase'

export type HomepagePromotion={id:string;title:string;subtitle:string;media_type:'IMAGE'|'VIDEO';media_url:string;poster_url:string|null;cta_label:string|null;cta_href:string|null;sort_order:number;loop_video:boolean}

export function HomepageCarousel(){
 const{user}=useAuth(),[items,setItems]=useState<HomepagePromotion[]>([]),[active,setActive]=useState(0),[muted,setMuted]=useState(true),visible=useRef(false),section=useRef<HTMLElement|null>(null),video=useRef<HTMLVideoElement|null>(null),seen=useRef(new Set<string>()),played=useRef(new Set<string>()),session=useRef('')
 useEffect(()=>{session.current=sessionStorage.getItem('cande-home-session')||crypto.randomUUID();sessionStorage.setItem('cande-home-session',session.current);if(!supabase)return;const load=()=>{const now=new Date().toISOString();return supabase!.from('homepage_promotions').select('id,title,subtitle,media_type,media_url,poster_url,cta_label,cta_href,sort_order,loop_video').eq('active',true).lte('starts_at',now).gt('ends_at',now).order('sort_order').then(({data})=>setItems((data||[]) as HomepagePromotion[]))};load();const refreshTimer=window.setInterval(load,60000);const channel=supabase.channel('homepage-promotions-live').on('postgres_changes',{event:'*',schema:'public',table:'homepage_promotions'},load).subscribe();return()=>{window.clearInterval(refreshTimer);supabase?.removeChannel(channel)}},[])
 useEffect(()=>{if(items.length<2)return;const timer=setInterval(()=>{if(visible.current)setActive(value=>(value+1)%items.length)},5000);return()=>clearInterval(timer)},[items.length])
 useEffect(()=>{if(!section.current)return;const observer=new IntersectionObserver(([entry])=>{visible.current=entry.isIntersecting;if(entry.isIntersecting)video.current?.play().catch(()=>undefined);else video.current?.pause()},{threshold:.35});observer.observe(section.current);return()=>observer.disconnect()},[])
 const track=useCallback((promotionId:string,eventType:'IMPRESSION'|'VIDEO_PLAY'|'CTA_CLICK')=>{if(!supabase||!session.current)return;const key=`${promotionId}:${eventType}`;if(eventType!=='CTA_CLICK'&&seen.current.has(key))return;seen.current.add(key);supabase.from('homepage_promotion_events').insert({promotion_id:promotionId,customer_id:user?.id||null,session_id:session.current,event_type:eventType}).then(()=>undefined)},[user?.id])
 useEffect(()=>{const item=items[active];if(item)track(item.id,'IMPRESSION')},[active,items,track])
 if(!items.length)return null
 const current=items[Math.min(active,items.length-1)]
 return <section ref={section} className="relative mt-7 min-h-[360px] overflow-hidden rounded-lg bg-cande-900 text-white">
  {current.media_type==='VIDEO'?<video ref={video} key={current.id} src={current.media_url} poster={current.poster_url||undefined} autoPlay muted={muted} playsInline loop={current.loop_video} preload="metadata" onPlay={()=>{if(!played.current.has(current.id)){played.current.add(current.id);track(current.id,'VIDEO_PLAY')}}} className="absolute inset-0 h-full w-full object-cover"/>:<Image key={current.id} src={current.media_url} alt={current.title} fill sizes="(max-width: 768px) 100vw, 1180px" className="object-cover"/>}
  <div className="absolute inset-0 bg-gradient-to-t from-cande-900 via-cande-900/35 to-transparent"/><div className="relative z-10 flex min-h-[360px] flex-col justify-end p-6"><h2 className="max-w-xl text-3xl font-black">{current.title}</h2>{current.subtitle&&<p className="mt-2 max-w-xl text-sm text-white/85">{current.subtitle}</p>}<div className="mt-5 flex items-center gap-3">{current.cta_label&&current.cta_href&&<Link onClick={()=>track(current.id,'CTA_CLICK')} href={current.cta_href} className="inline-flex min-h-12 items-center gap-2 rounded-full bg-cande-500 px-6 text-sm font-black">{current.cta_label}<ArrowRight size={17}/></Link>}{current.media_type==='VIDEO'&&<button onClick={()=>setMuted(value=>!value)} aria-label={muted?'Activar sonido':'Silenciar'} className="grid h-12 w-12 place-items-center rounded-full bg-black/40">{muted?<VolumeX/>:<Volume2/>}</button>}</div></div>
  {items.length>1&&<div className="absolute bottom-3 right-4 z-20 flex gap-1.5">{items.map((item,index)=><button key={item.id} onClick={()=>setActive(index)} aria-label={`Mostrar promoción ${index+1}`} className={`h-2.5 rounded-full transition-all ${index===active?'w-7 bg-white':'w-2.5 bg-white/50'}`}/>)}</div>}
 </section>
}
