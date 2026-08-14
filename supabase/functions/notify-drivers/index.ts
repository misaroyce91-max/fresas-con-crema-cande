import {createClient} from 'npm:@supabase/supabase-js@2.95.0'
import webpush from 'npm:web-push@3.6.7'

const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}})

Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors})
  try{
    const authorization=req.headers.get('Authorization')||''
    const token=authorization.replace(/^Bearer\s+/,'')
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const{data:{user}}=await admin.auth.getUser(token)
    if(!user||user.app_metadata?.role!=='ADMIN')return json({error:'ADMIN_REQUIRED'},403)
    const{requestId}=await req.json()
    if(!requestId)return json({error:'REQUEST_ID_REQUIRED'},400)

    const[{data:request},{data:config},{data:couriers},{data:assignments}]=await Promise.all([
      admin.from('delivery_requests').select('id,status,order_id,orders(order_number)').eq('id',requestId).single(),
      admin.rpc('service_push_config').single(),
      admin.from('couriers').select('id').eq('active',true).eq('status','available'),
      admin.from('delivery_assignments').select('courier_id,status').in('status',['accepted','heading_to_pickup','picked_up','delivering'])
    ])
    if(!request||request.status!=='requested')return json({sent:0,reason:'REQUEST_NOT_AVAILABLE'})
    if(!config)throw new Error('PUSH_NOT_CONFIGURED')
    const counts=new Map<string,number>()
    for(const row of assignments||[])counts.set(row.courier_id,(counts.get(row.courier_id)||0)+1)
    const eligible=(couriers||[]).map(c=>c.id).filter(id=>(counts.get(id)||0)<3)
    if(!eligible.length)return json({sent:0,reason:'NO_AVAILABLE_DRIVERS'})
    const{subscriptions}=await admin.from('push_subscriptions').select('id,subscription').eq('active',true).in('courier_id',eligible).then(({data,error})=>({subscriptions:data,error}))
    webpush.setVapidDetails(config.subject,config.public_key,config.private_key)
    const orderNumber=(request.orders as any)?.order_number
    const payload=JSON.stringify({title:'🍓 Nueva entrega Cande',body:`Solicitud CAN-${String(orderNumber).padStart(6,'0')} disponible`,url:`/driver?request=${request.id}`,tag:`delivery-${request.id}`})
    let sent=0
    await Promise.all((subscriptions||[]).map(async row=>{try{await webpush.sendNotification(row.subscription as any,payload,{TTL:300,urgency:'high'});sent++}catch(error:any){if(error?.statusCode===404||error?.statusCode===410)await admin.from('push_subscriptions').update({active:false,updated_at:new Date().toISOString()}).eq('id',row.id)}}))
    return json({sent})
  }catch(error){return json({error:error instanceof Error?error.message:'PUSH_FAILED'},500)}
})
