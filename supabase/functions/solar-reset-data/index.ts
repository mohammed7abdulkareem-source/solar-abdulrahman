import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2.57.4";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const reply=(data:unknown,status=200)=>Response.json(data,{status,headers:{...cors,"Cache-Control":"no-store"}});
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return reply({error:'الطريقة غير مسموحة'},405);
 try{
  const header=req.headers.get('Authorization')||'';
  if(!header.startsWith('Bearer '))return reply({error:'يجب تسجيل الدخول'},401);
  const url=Deno.env.get('SUPABASE_URL')!,anon=Deno.env.get('SUPABASE_ANON_KEY')!;
  const client=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:header}}});
  const {data:{user},error:authError}=await client.auth.getUser();
  if(authError||!user?.email)return reply({error:'جلسة الدخول غير صالحة'},401);
  const {data:profile,error:profileError}=await client.from('profiles').select('is_admin,active,user_type').eq('id',user.id).single();
  if(profileError||!profile?.active||!profile.is_admin||['installer','warehouse'].includes(profile.user_type))return reply({error:'التصفير للأدمن فقط'},403);
  const b=await req.json();
  if(b.confirmation!=='تصفير بيانات عبدالرحمن سولار'||typeof b.requestId!=='string'||!b.requestId.match(/^[0-9a-f-]{36}$/i)||typeof b.password!=='string'||!b.password||b.password.length>1024)return reply({error:'أكمل الباسورد وعبارة التأكيد'},400);
  // An admin session alone cannot reset: verify their password at this moment.
  const verifier=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
  const verified=await verifier.auth.signInWithPassword({email:user.email,password:b.password});
  if(verified.error||verified.data.user?.id!==user.id)return reply({error:'الباسورد غير صحيح أو المحاولات كثيرة؛ حاول مجدداً لاحقاً'},403);
  // Revoke only the temporary verification session, not other devices.
  await verifier.auth.signOut({scope:'local'});
  const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data,error}=await admin.rpc('solar_execute_reset',{actor_id:user.id,request_id:b.requestId,confirmation:b.confirmation});
  if(error)return reply({error:error.message||'تعذر التصفير؛ أعد المعاينة'},409);
  return reply(data);
 }catch{return reply({error:'تعذر تنفيذ الطلب؛ تحقق من الاتصال وأعد المعاينة قبل المحاولة'},400)}
});
