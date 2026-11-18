import {normalizeHonorific,validHonorific} from '../_shared/user-name.mjs';
import {normalizeUserPhone,validUserPhone} from '../_shared/user-phone.mjs';
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2.57.4";

const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const field=(body:any,key:string)=>Object.hasOwn(body,key);
const reply=(body:any,status=200)=>Response.json(body,{status,headers:cors});
const roleOf=(u:any)=>u.user_type==='warehouse'||u.user_type==='installer'?u.user_type:u.is_admin?'admin':'user';
const unavailable=(error:any)=>error?.status===404||error?.code==='user_not_found';
async function passwordTag(secret:string,password:string,requestId:string){
 const encoder=new TextEncoder();
 const key=await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 const signed=await crypto.subtle.sign('HMAC',key,encoder.encode(requestId+'|'+password));
 return Array.from(new Uint8Array(signed),value=>value.toString(16).padStart(2,'0')).join('');
}

Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return reply({ok:false,error:'استخدم طلبًا صحيحًا'},405);
 try{
  const url=Deno.env.get('SUPABASE_URL')!,secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const client=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:req.headers.get('Authorization')||''}}});
  const {data:{user}}=await client.auth.getUser();if(!user)return reply({ok:false,error:'يجب تسجيل الدخول'},401);
  const admin=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:actor,error:profileError}=await admin.from('profiles').select('is_admin,active,user_type').eq('id',user.id).single();
  if(profileError||!actor?.active||!actor.is_admin||['warehouse','installer'].includes(actor.user_type))return reply({ok:false,error:'للأدمن فقط'},403);
  const b=await req.json();
  const command=async(action:string,id:string|null,payload:any)=>{
   const {data,error}=await admin.rpc('solar_admin_user_wizard',{actor_id:user.id,action,request_id:id,payload});
   if(error)throw error;return data;
  };
  const directory=()=>command('directory',null,{});
  const current=async(id:string)=>{
   const row=(await directory()).users.find((u:any)=>u.id===id);
   if(!row)throw Error('حساب المستخدم غير موجود');return row;
  };
  if(b.action==='directory'||b.action==='list')return reply({ok:true,...await directory()});
  const legacy=['create','update','toggle','delete'].includes(b.action);
  const id=b.request_id||(legacy?crypto.randomUUID():'');
  if(!uuid.test(id))throw Error('رقم طلب الحفظ غير صحيح');
  if(b.user_id&&!uuid.test(b.user_id))throw Error('معرّف المستخدم غير صحيح');

  async function saveDetails(input:any,requestId:string){
   const creating=!input.user_id,targetId=input.user_id||requestId;
   const username=String(input.username||'').trim().toLowerCase(),name=String(input.display_name||username).trim();
   const password=String(input.password||'');
   if(!/^[a-z0-9_.-]{2,30}$/.test(username)||!name||name.length>150)throw Error('تحقق من اسم المستخدم والاسم الظاهر');
   if((creating||password)&&password.length<6)throw Error('يجب أن يتكون الرقم السري من ستة أحرف على الأقل');
   if(password.length>128)throw Error('الرقم السري طويل');
   if((creating||field(input,'phone'))&&!validUserPhone(input.phone))throw Error('أدخل رقم هاتف صحيحاً للمستخدم');
   if(field(input,'honorific')&&!validHonorific(input.honorific))throw Error('الكنية غير صحيحة أو أطول من 50 حرفاً');
   const payload:any={user_id:targetId,creating,username,display_name:name};
   if(!creating)payload.token=input.token;
   if(field(input,'phone'))payload.phone=normalizeUserPhone(input.phone);
   if(field(input,'honorific'))payload.honorific=normalizeHonorific(input.honorific);
   if(password)payload.credentialTag=await passwordTag(secret,password,requestId);
   let authUser:any=null;
   if(creating){
    await command('check_create',requestId,payload);
    const lookup=await admin.auth.admin.getUserById(targetId);
    if(lookup.error&&!unavailable(lookup.error))throw lookup.error;
    authUser=lookup.data?.user;
    if(!authUser){
     const provision=await admin.auth.admin.createUser({id:targetId,email:username+'@solar-user.local',password,email_confirm:true,
      ban_duration:'876000h',user_metadata:{display_name:name},app_metadata:{solar_wizard_request:requestId,solar_wizard_actor:user.id,
       solar_wizard_credential:payload.credentialTag}});
     authUser=provision.data?.user;
     if(provision.error||!authUser){
      const recovery=await admin.auth.admin.getUserById(targetId);
      if(recovery.error||!recovery.data?.user)throw provision.error||Error('تعذر إنشاء الحساب');
      authUser=recovery.data.user;
     }
    }
    if(authUser.id!==targetId||authUser.app_metadata?.solar_wizard_actor!==user.id||
       authUser.app_metadata?.solar_wizard_request!==requestId||(!authUser.app_metadata?.solar_wizard_ready&&authUser.app_metadata?.solar_wizard_credential!==payload.credentialTag)){
     throw Error('محاولة إنشاء الحساب لا تطابق الطلب السابق');
    }
   }
   const data=await command('save_details',requestId,payload);
   if(creating){
    if(authUser.app_metadata?.solar_wizard_ready!==true){
     const updated=await admin.auth.admin.updateUserById(targetId,{ban_duration:'none',app_metadata:{solar_wizard_ready:true,solar_wizard_credential:null}});
     if(updated.error)throw updated.error;
    }
   }else if(password){
    const lookup=await admin.auth.admin.getUserById(targetId);
    if(lookup.error)throw lookup.error;
    if(lookup.data.user.app_metadata?.solar_last_password_request!==requestId){
     if((await current(targetId)).token!==data.user.token)throw Error('تغير الحساب منذ هذه المحاولة؛ ابدأ تعديل الرقم السري من بياناته الحالية');
     const updated=await admin.auth.admin.updateUserById(targetId,{password,app_metadata:{solar_last_password_request:requestId}});
     if(updated.error)throw updated.error;
    }
   }
   return data;
  }

  async function finalize(input:any,requestId:string){
   const state=await command('finalize',requestId,{user_id:input.user_id,token:input.token,role:input.role,active:input.active,
    permissions:input.permissions,warehouse:input.warehouse??null});
   if(state.user.active){
    const account=await admin.auth.admin.getUserById(state.user.id);
    if(account.error&&!unavailable(account.error))throw account.error;
    const metadata=account.data?.user?.app_metadata;
    if(metadata?.solar_wizard_request===state.user.id&&!metadata.solar_wizard_ready){
     // An earlier staging call may have lost its Auth acknowledgement. Any
     // current administrator can resume it from the directory.
     if((await current(state.user.id)).token!==state.user.token)throw Error('تغير الحساب؛ حدّث القائمة قبل التفعيل');
     const restored=await admin.auth.admin.updateUserById(state.user.id,{ban_duration:'none',
      app_metadata:{solar_wizard_ready:true,solar_wizard_credential:null}});
     if(restored.error)throw restored.error;
    }
   }
   return state;
  }
  async function remove(targetId:string,token:string,requestId:string){
   const state=await command('remove',requestId,{user_id:targetId,token});
   if(state.mode==='archived')return {mode:'archived'};
   const removed=await admin.auth.admin.deleteUser(targetId);
   if(!removed.error||unavailable(removed.error))return {mode:'deleted'};
   const lookup=await admin.auth.admin.getUserById(targetId);
   if(unavailable(lookup.error))return {mode:'deleted'};
   if(lookup.error)throw removed.error;
   const row=await current(targetId);
   if(row.active)throw Error('تغيّرت حالة الحساب؛ حدّث القائمة قبل حذفه');
   if(removed.error.code==='unexpected_failure'||removed.error.status===422||removed.error.status===409)return {mode:'archived'};
   throw removed.error;
  }
  let result:any;
  if(b.action==='save_details')result=await saveDetails(b,id);
  else if(b.action==='finalize')result=await finalize(b,id);
  else if(b.action==='remove')result=await remove(b.user_id,b.token,id);
  else if(legacy){
   const old=b.action==='create'?null:await current(b.user_id);
   if(b.action==='delete')result=await remove(old.id,old.token,id);
   else if(b.action==='toggle')result=await finalize({user_id:old.id,token:old.token,role:roleOf(old),active:!old.active,
    permissions:old.permissions,warehouse:null},id);
   else{
    const details=await saveDetails({...b,user_id:old?.id,token:old?.token},id);
    result=await finalize({user_id:details.user.id,token:details.user.token,role:b.role==='admin_staff'?'user':b.role,
     active:old?.active??true,permissions:b.permissions||{},warehouse:null},crypto.randomUUID());
   }
  }else throw Error('عملية غير معروفة');
  return reply({ok:true,...result});
 }catch(error:any){
  const status=error?.code==='42501'?403:error?.code==='40001'||error?.code==='PT409'||error?.code==='23505'?409:400;
  return reply({ok:false,error:error?.code==='23505'?'اسم المستخدم محجوز':String(error?.message||'تعذر تنفيذ العملية')},status);
 }
});
