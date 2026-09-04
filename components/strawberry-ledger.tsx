'use client'

import {useCallback,useEffect,useState} from 'react'
import {Clock3} from 'lucide-react'
import {useAuth} from '@/components/auth-provider'
import {supabase} from '@/lib/supabase'

type Movement={id:string;type:string;points:number;balance_before:number;balance_after:number;description:string|null;created_at:string}

export function StrawberryLedger(){
 const{user,profile}=useAuth()
 const[movements,setMovements]=useState<Movement[]>([])
 const load=useCallback(async()=>{if(!supabase||!user){setMovements([]);return}const{data}=await supabase.from('points_transactions').select('id,type,points,balance_before,balance_after,description,created_at').eq('customer_id',user.id).order('created_at',{ascending:false}).limit(50);setMovements((data||[])as Movement[])},[user])
 useEffect(()=>{load();if(!supabase||!user)return;const channel=supabase.channel(`strawberry-ledger-${user.id}`).on('postgres_changes',{event:'INSERT',schema:'public',table:'points_transactions',filter:`customer_id=eq.${user.id}`},load).subscribe();return()=>{supabase?.removeChannel(channel)}},[load,user])
 if(!user)return null
 const spent=movements.filter(m=>m.type==='redeem').reduce((sum,m)=>sum-Math.min(0,m.points),0)
 const refunded=movements.filter(m=>m.type==='refund').reduce((sum,m)=>sum+Math.max(0,m.points),0)
 return <section className="page max-w-4xl !pt-0"><div className="card p-5"><div className="grid grid-cols-2 gap-3 sm:grid-cols-4"><Metric label="Disponibles" value={profile?.points_balance||0}/><Metric label="Históricas" value={profile?.lifetime_points||0}/><Metric label="Gastadas" value={spent}/><Metric label="Devueltas" value={refunded}/></div>{movements.length?<><h2 className="section-title mt-7 flex items-center gap-2"><Clock3 size={20}/>Historial de Fresas</h2><div className="mt-3 divide-y divide-cande-50">{movements.map(m=><article key={m.id} className="flex items-center gap-3 py-3"><span className={`grid h-10 w-10 shrink-0 place-items-center rounded-full text-sm font-black ${m.points>0?'bg-green-50 text-green-700':'bg-cande-50 text-cande-700'}`}>{m.points>0?'+':''}{m.points}</span><div className="min-w-0 flex-1"><p className="truncate text-sm font-bold">{m.description||m.type}</p><p className="text-xs text-zinc-500">{new Date(m.created_at).toLocaleString('es-MX')} · Saldo {m.balance_before} → {m.balance_after}</p></div></article>)}</div></>:<p className="mt-5 text-sm text-zinc-500">Aún no tienes movimientos de Fresas.</p>}</div></section>
}

function Metric({label,value}:{label:string;value:number}){return <div className="rounded-2xl bg-cande-50 p-3 text-center"><strong className="block text-xl text-cande-800">🍓 {value}</strong><span className="text-[11px] font-bold text-zinc-500">{label}</span></div>}
