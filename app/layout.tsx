import type { Metadata, Viewport } from 'next'; import './globals.css'; import { CartProvider } from '@/components/cart-provider'; import { StoreProvider } from '@/components/store-provider'; import { Nav } from '@/components/nav'
import {PwaRegister}from'@/components/pwa-register'
import {AuthProvider}from'@/components/auth-provider'
import {DriverAlerts}from'@/components/driver-alerts'
import {InstallCande,InstallCandeCard}from'@/components/install-cande'
import {ReferralCapture}from'@/components/referral-capture'
import {FavoritesProvider}from'@/components/favorites-provider'
import {WhatsAppHelp}from'@/components/whatsapp-help'
export const metadata:Metadata={title:'Fresas con Crema Cande',description:'Fresas frescas, crema de la casa y recompensas en cada compra.',manifest:'/manifest.webmanifest',icons:{icon:'/icons/cande-driver-192.png',apple:'/icons/cande-driver-192.png'}}
export const viewport:Viewport={themeColor:'#f22e62'}
const installPromptCapture=`(()=>{window.addEventListener('beforeinstallprompt',event=>{event.preventDefault();window.__candeInstallPrompt=event;window.dispatchEvent(new Event('candeinstallready'))});window.addEventListener('appinstalled',()=>{window.__candeInstallPrompt=null;window.dispatchEvent(new Event('candeappinstalled'))})})()`
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="es"><head><script dangerouslySetInnerHTML={{__html:installPromptCapture}}/></head><body><PwaRegister/><ReferralCapture/><AuthProvider><FavoritesProvider><StoreProvider><CartProvider>{children}<InstallCandeCard accountOnly/><WhatsAppHelp/><Nav/><InstallCande/><DriverAlerts/></CartProvider></StoreProvider></FavoritesProvider></AuthProvider></body></html>}
