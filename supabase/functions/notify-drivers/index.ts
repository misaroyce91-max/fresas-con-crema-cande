import {createClient} from 'npm:@supabase/supabase-js@2.95.0'
import webpush from 'npm:web-push@3.6.7'

const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json'}})
const sleep=(ms:number)=>new Promise(resolve=>setTimeout(resolve,ms))

Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors})
  try{
    const token=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/,'')
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const{data:{user}}=await admin.auth.getUser(token)
    if(!user||user.app_metadata?.role!=='ADMIN')return json({error:'ADMIN_REQUIRED'},403)
    const{requestId}=await req.json()
    if(!requestId)return json({error:'REQUEST_ID_REQUIRED'},400)
    const[{data:request},{data:config},{data:reputation}]=await Promise.all([
      admin.from('delivery_requests').select('id,status').eq('id',requestId).single(),
      admin.rpc('service_push_config').single(),
      admin.from('driver_reputation_config').select('first_round_seconds,second_round_seconds').eq('id','main').single()
    ])
    if(!request||request.status!=='requested')return json({sent:0,reason:'REQUEST_NOT_AVAILABLE'})
    if(!config)throw new Error('PUSH_NOT_CONFIGURED')
    webpush.setVapidDetails(config.subject,config.public_key,config.private_key)
    const sendDue=async()=>{
      const{data:offers,error}=await admin.rpc('service_due_driver_push_offers',{p_request_id:requestId})
      if(error)throw error
      let sent=0
      for(const offer of offers||[]){
        const{subscriptions}=await admin.from('push_subscriptions').select('id,subscription').eq('active',true).eq('courier_id',offer.courier_id)
        const payload=JSON.stringify({title:'🍓 Nueva entrega Cande',body:`Solicitud CAN-${String(offer.order_number).padStart(6,'0')} disponible`,url:`/driver?request=${requestId}`,tag:`delivery-${requestId}`})
        for(const row of subscriptions||[]){try{await webpush.sendNotification(row.subscription as any,payload,{TTL:300,urgency:'high'});sent++}catch(error:any){if(error?.statusCode===404||error?.statusCode===410)await admin.from('push_subscriptions').update({active:false,updated_at:new Date().toISOString()}).eq('id',row.id)}}
        await admin.from('driver_offers').update({push_sent_at:new Date().toISOString()}).eq('id',offer.offer_id).is('push_sent_at',null)
      }
      return sent
    }
    const firstSent=await sendDue()
    const staged=async()=>{const duration=Number(reputation?.first_round_seconds||20)+Number(reputation?.second_round_seconds||20)+8;for(let elapsed=5;elapsed<=duration;elapsed+=5){await sleep(5000);const{data}=await admin.from('delivery_requests').select('status').eq('id',requestId).single();if(data?.status!=='requested')break;await sendDue()}}
    EdgeRuntime.waitUntil(staged())
    return json({sent:firstSent,staged:true})
  }catch(error){return json({error:error instanceof Error?error.message:'PUSH_FAILED'},500)}
})
