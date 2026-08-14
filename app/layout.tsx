import type { Metadata } from 'next'; import './globals.css'; import { CartProvider } from '@/components/cart-provider'; import { StoreProvider } from '@/components/store-provider'; import { Nav } from '@/components/nav'
import {PwaRegister}from'@/components/pwa-register'
import {AuthProvider}from'@/components/auth-provider'
import {DriverAlerts}from'@/components/driver-alerts'
import {InstallCande,InstallCandeCard}from'@/components/install-cande'
export const metadata:Metadata={title:'Fresas con Crema Cande',description:'Fresas frescas, crema de la casa y recompensas en cada compra.',manifest:'/manifest.webmanifest',themeColor:'#f22e62',icons:{icon:'/icons/cande-driver-192.png',apple:'/icons/cande-driver-192.png'}}
const installPromptCapture=`(()=>{window.addEventListener('beforeinstallprompt',event=>{event.preventDefault();window.__candeInstallPrompt=event;window.dispatchEvent(new Event('candeinstallready'))});window.addEventListener('appinstalled',()=>{window.__candeInstallPrompt=null;window.dispatchEvent(new Event('candeappinstalled'))})})()`
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="es"><head><script dangerouslySetInnerHTML={{__html:installPromptCapture}}/></head><body><PwaRegister/><AuthProvider><StoreProvider><CartProvider>{children}<InstallCandeCard accountOnly/><Nav/><InstallCande/><DriverAlerts/></CartProvider></StoreProvider></AuthProvider></body></html>}
