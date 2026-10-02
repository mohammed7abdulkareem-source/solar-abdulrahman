import {createClient} from 'npm:@supabase/supabase-js@2.57.4';
import webpush from 'npm:web-push@3.6.7';
import {timingSafeEqual} from 'node:crypto';
import {Buffer} from 'node:buffer';
const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
function allowedEndpoint(endpoint:string){
 try{const u=new URL(endpoint);return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&(
 ['fcm.googleapis.com','updates.push.services.mozilla.com','web.push.apple.com'].includes(u.hostname)||/^[a-z0-9.-]+\.notify\.windows\.com$/.test(u.hostname));}catch{return false}
}
Deno.serve(async(req)=>{
 if(req.method!=='POST')return new Response('Method not allowed',{status:405});
 const token=req.headers.get('x-solar-push-token')||'';
 if(token.length!==64)return new Response('Unauthorized',{status:401});
 const {data:config,error:configError}=await db.rpc('solar_push_worker_config');
 if(configError||!config?.solar_push_worker_token)return new Response('Not configured',{status:503});
 const expected=String(config.solar_push_worker_token);
 if(token.length!==expected.length||!timingSafeEqual(Buffer.from(token),Buffer.from(expected)))return new Response('Unauthorized',{status:401});
 if(!config.solar_push_vapid_public||!config.solar_push_vapid_private)return new Response('Not configured',{status:503});
 const requestBody=await req.json().catch(()=>({}));
 if(requestBody.selfTest===true){
  try{
   const receiver=webpush.generateVAPIDKeys();
   const auth=Buffer.from(crypto.getRandomValues(new Uint8Array(16))).toString('base64url');
   const details=webpush.generateRequestDetails({endpoint:'https://fcm.googleapis.com/fcm/send/self-test',keys:{p256dh:receiver.publicKey,auth}},'encrypted health check',{
    vapidDetails:{subject:'https://solar-abdulrahman.vercel.app',publicKey:config.solar_push_vapid_public,privateKey:config.solar_push_vapid_private},contentEncoding:'aes128gcm'
   });
   return Response.json({encryptionReady:details.body.length>0,networkSend:false});
  }catch{return new Response('Encryption check failed',{status:500})}
 }
 const {data:batch,error}=await db.rpc('solar_push_claim');
 if(error)return new Response('Queue unavailable',{status:503});
 let accepted=0,failed=0;
 await Promise.all((batch||[]).map(async(d:any)=>{
  let status=0;
  try{
   if(!allowedEndpoint(d.endpoint))status=422;
   else{
    const details=webpush.generateRequestDetails({endpoint:d.endpoint,keys:d.keys},JSON.stringify(d.notification),{
     vapidDetails:{subject:'https://solar-abdulrahman.vercel.app',publicKey:config.solar_push_vapid_public,privateKey:config.solar_push_vapid_private},
     TTL:86400,urgency:'high',topic:d.notification.id.replaceAll('-','').slice(0,32),contentEncoding:'aes128gcm'
    });
    const response=await fetch(details.endpoint,{method:'POST',headers:details.headers,body:details.body,redirect:'error',signal:AbortSignal.timeout(8000)});
    status=response.status;await response.body?.cancel();
   }
  }catch{status=0}
  if(status>=200&&status<300)accepted++;else failed++;
  const {error:saveError}=await db.rpc('solar_push_finish',{delivery_id:d.deliveryId,attempt_number:d.attempt,http_status:status});
  if(saveError)console.error('Push acknowledgement failed'); // Lease permits recovery; never log endpoints/keys.
 }));
 return Response.json({processed:(batch||[]).length,accepted,failed});
});
