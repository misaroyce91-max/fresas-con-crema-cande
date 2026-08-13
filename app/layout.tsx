import type { Metadata } from 'next'; import './globals.css'; import { CartProvider } from '@/components/cart-provider'; import { StoreProvider } from '@/components/store-provider'; import { Nav } from '@/components/nav'
import {PwaRegister}from'@/components/pwa-register'
import {AuthProvider}from'@/components/auth-provider'
import {DriverAlerts}from'@/components/driver-alerts'
export const metadata:Metadata={title:'Fresas con Crema Cande',description:'Fresas frescas, crema de la casa y recompensas en cada compra.',manifest:'/driver-manifest.webmanifest',themeColor:'#f22e62',icons:{icon:'/icons/cande-driver-192.png',apple:'/icons/cande-driver-192.png'}}
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="es"><body><PwaRegister/><AuthProvider><StoreProvider><CartProvider>{children}<Nav/><DriverAlerts/></CartProvider></StoreProvider></AuthProvider></body></html>}
