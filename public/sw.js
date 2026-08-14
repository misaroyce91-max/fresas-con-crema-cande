const CACHE='cande-app-v7';
const SHELL=['/','/driver','/manifest.webmanifest','/driver-manifest.webmanifest','/icons/cande-driver-192.png','/icons/cande-driver-512.png'];
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET')return;
  const url=new URL(event.request.url);
  if(event.request.mode==='navigate'){
    const fallback=url.pathname.startsWith('/driver')?'/driver':'/';
    event.respondWith(fetch(event.request).then(async response=>{
      if(response.status===404)return Response.redirect(new URL(fallback,self.location.origin),302);
      if(response.ok&&url.origin===self.location.origin){const cache=await caches.open(CACHE);await cache.put(event.request,response.clone())}
      return response;
    }).catch(async()=>await caches.match(event.request)||Response.redirect(new URL(fallback,self.location.origin),302)));
    return;
  }
  event.respondWith(fetch(event.request).then(response=>{
    if(response.ok&&url.origin===self.location.origin){const copy=response.clone();event.waitUntil(caches.open(CACHE).then(cache=>cache.put(event.request,copy)))}
    return response;
  }).catch(()=>caches.match(event.request)));
});
self.addEventListener('push',event=>{const data=event.data?.json()||{};event.waitUntil(self.registration.showNotification(data.title||'🍓 Nueva entrega Cande',{body:data.body||'Hay una solicitud disponible.',icon:'/icons/cande-driver-192.png',badge:'/icons/cande-driver-192.png',vibrate:[500,180,500,180,800,300,500,180,500],silent:false,renotify:true,requireInteraction:true,data:{url:data.url||'/driver'},tag:data.tag||'cande-delivery'}))});
self.addEventListener('notificationclick',event=>{event.notification.close();event.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(windows=>{const url=event.notification.data?.url||'/driver';for(const client of windows){if('focus'in client){client.navigate(url);return client.focus()}}return clients.openWindow(url)}))});
