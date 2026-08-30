'use client'
import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { ReferralProgram } from '@/components/referral-program'
export default function ReferralsPage(){return <main className="page max-w-3xl"><Link href="/account" className="inline-flex items-center gap-2 text-sm font-bold text-cande-600"><ArrowLeft size={17}/>Mi Cuenta</Link><header className="mt-5"><p className="text-xs font-black uppercase text-cande-500">Programa Cande</p><h1 className="mt-1 text-3xl font-black">Invita y Gana</h1></header><div className="mt-6"><ReferralProgram/></div></main>}
