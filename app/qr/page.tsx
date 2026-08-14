import Image from 'next/image'
import Link from 'next/link'
import {Download,Printer} from 'lucide-react'

const url='https://fresas-con-crema-cande.vercel.app/'

export default function QrPage(){return <main className="min-h-screen bg-white px-5 py-10 print:p-0">
 <section className="mx-auto max-w-xl text-center">
  <p className="text-xs font-black uppercase text-cande-500 print:hidden">QR oficial de clientes</p>
  <h1 className="mt-2 text-3xl font-black">Fresas con Crema Cande</h1>
  <p className="mt-2 text-zinc-500 print:hidden">Este QR apunta permanentemente a la página oficial, nunca a localhost ni a un enlace temporal.</p>
  <div className="mx-auto mt-7 w-full max-w-[440px] border-8 border-white bg-white p-4 shadow-sm print:mt-12 print:max-w-[560px] print:border-0 print:shadow-none">
   <Image src="/api/qr" alt="Código QR oficial de Fresas con Crema Cande" width={1600} height={1600} priority unoptimized className="h-auto w-full"/>
   <p className="mt-4 text-2xl font-black">Escanea y pide aquí 🍓</p>
   <p className="mt-2 break-all text-xs text-zinc-500">{url}</p>
  </div>
  <div className="mt-7 grid gap-3 sm:grid-cols-2 print:hidden">
   <a href="/api/qr" download="qr-fresas-cande.png" className="flex h-13 items-center justify-center gap-2 rounded-full bg-cande-500 py-3 font-black text-white"><Download size={18}/>Descargar QR normal</a>
   <Link href="/qr?imprimir=1" className="flex h-13 items-center justify-center gap-2 rounded-full border border-cande-500 py-3 font-black text-cande-700"><Printer size={18}/>Versión para imprimir</Link>
  </div>
  <p className="mt-5 text-sm text-zinc-500 print:hidden">Para imprimir con el texto, abre el menú del navegador y elige Imprimir en esta página.</p>
 </section>
</main>}
