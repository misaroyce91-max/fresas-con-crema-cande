'use client'
import{useEffect}from'react';export function PwaRegister(){useEffect(()=>{if('serviceWorker'in navigator)navigator.serviceWorker.register('/sw.js').then(registration=>registration.update()).catch(()=>undefined)},[]);return null}
