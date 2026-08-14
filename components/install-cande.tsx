'use client'
import {useEffect,useState} from 'react'
import {usePathname} from 'next/navigation'
import {Download} from 'lucide-react'
type InstallEvent=Event&{prompt:()=>Promise<void>;userChoice:Promise<{outcome:string}>}
export function InstallCande(){const path=usePathname(),[event,setEvent]=useState<InstallEvent|null>(null);useEffect(()=>{const ready=(e:Event)=>{e.preventDefault();setEvent(e as InstallEvent)};addEventListener('beforeinstallprompt',ready);return()=>removeEventListener('beforeinstallprompt',ready)},[]);if(path!=='/'||!event)return null;return <button onClick={async()=>{await event.prompt();const choice=await event.userChoice;if(choice.outcome==='accepted')setEvent(null)}} className="fixed right-3 top-3 z-40 flex h-10 items-center gap-2 rounded-full border border-cande-200 bg-white/95 px-3 text-xs font-black text-cande-700 shadow-sm backdrop-blur"><Download size={15}/>Agregar Cande</button>}
