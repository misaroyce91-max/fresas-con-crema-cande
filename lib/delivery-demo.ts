export type DriverStatus = 'Disponible' | 'Ocupado' | 'No disponible'
export type DeliveryStage = 'requested' | 'assigned' | 'heading_to_pickup' | 'picked_up' | 'delivering' | 'delivered'
export type Driver = { id:string; name:string; phone:string; status:DriverStatus; assigned:number; delivered:number; fee:number; lastActivity:string }
export type DeliveryOrder = { orderId:string; customer:{name:string;phone:string}; total:number; date:string; delivery:{type:string;address:string;references?:string;mapsUrl?:string|null}; status:string;notes?:string;payment?:string }
export type DeliveryRequest = { order:DeliveryOrder; pickupZone:string; pickupAddress:string; deliveryZone:string;distanceKm?:number|null;pay:number;stage:DeliveryStage;driverId?:string;rejectedBy?:string[];requestedAt:string;acceptedAt?:string;updatedAt:string }

export const drivers:Driver[] = [
  {id:'d1',name:'Luis Hernández',phone:'722 410 2381',status:'Disponible',assigned:0,delivered:38,fee:35,lastActivity:'Hace 12 min'},
  {id:'d2',name:'Diego Martínez',phone:'722 318 9044',status:'Ocupado',assigned:1,delivered:27,fee:35,lastActivity:'En ruta'},
  {id:'d3',name:'Carlos Reyes',phone:'722 660 1520',status:'Disponible',assigned:0,delivered:19,fee:40,lastActivity:'Hace 28 min'},
  {id:'d4',name:'Emiliano Cruz',phone:'722 501 7732',status:'No disponible',assigned:0,delivered:31,fee:35,lastActivity:'Ayer, 21:10'},
]
export const demoOrders:DeliveryOrder[] = [
  {orderId:'CAN-5834',customer:{name:'Andrea López',phone:'722 118 4052'},total:218,date:new Date().toISOString(),delivery:{type:'delivery',address:'Av. Independencia 214, Centro, Toluca',references:'Portón blanco, frente a la farmacia',mapsUrl:'https://www.google.com/maps?q=19.2826,-99.6557'},status:'Recibido'},
  {orderId:'CAN-5829',customer:{name:'Fernanda Ruiz',phone:'722 704 9130'},total:165,date:new Date().toISOString(),delivery:{type:'delivery',address:'Col. Universidad, Toluca',references:'Casa rosa, timbre lateral'},status:'Recibido'},
]
export const REQUESTS_KEY='cande-delivery-requests'
export const PRESENCE_KEY='cande-driver-presence'
export function readRequests():DeliveryRequest[]{try{return JSON.parse(localStorage.getItem(REQUESTS_KEY)||'[]')}catch{return []}}
export function writeRequests(requests:DeliveryRequest[]){localStorage.setItem(REQUESTS_KEY,JSON.stringify(requests));window.dispatchEvent(new Event('cande-delivery-update'))}
export function zoneFromAddress(address:string){return address.split(',').slice(-2).join(',').trim()||'Zona por confirmar'}
