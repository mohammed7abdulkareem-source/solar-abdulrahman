const cors={
 'Access-Control-Allow-Origin':'*',
 'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
 'Access-Control-Allow-Methods':'POST, OPTIONS',
};
const messages={
 unauthorized:'جلسة الدخول غير صالحة. سجّل الدخول مجدداً.',
 inactive:'هذا الحساب موقوف أو غير متاح.',
 invalid_input:'أدخل الرقم السري القديم والجديد وتأكيده. اختر رقماً جديداً من 6 أحرف أو أرقام على الأقل، وبدون طول زائد.',
 password_mismatch:'الرقم السري الجديد وتأكيده غير متطابقين.',
 same_password:'اختر رقماً سرياً جديداً يختلف عن القديم.',
 weak_password:'الرقم السري الجديد لا يطابق شروط الأمان. اختر رقماً أطول وأكثر تنوعاً.',
 invalid_old_password:'الرقم السري القديم غير صحيح.',
 rate_limited:'المحاولات كثيرة. انتظر قليلاً ثم حاول مجدداً.',
 unavailable:'تعذر التحقق من الحساب الآن. تحقق من الاتصال وحاول مجدداً.',
 change_uncertain:'لم يتأكد رد الحفظ؛ قد يكون الرقم السري تغيّر. عند تسجيل الدخول جرّب الرقم الجديد أولاً.',
};
const reply=(data,status=200)=>Response.json(data,{status,headers:{...cors,'Cache-Control':'no-store'}});
const fail=(code,status=400)=>reply({ok:false,code,error:messages[code],uncertain:code==='change_uncertain'},status);
async function readBody(req){
 if(Number(req.headers.get('content-length'))>8192)throw new Error('body_limit');
 const reader=req.body?.getReader();if(!reader)throw new Error('body_missing');
 const chunks=[];let size=0;
 try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>8192){await reader.cancel();throw new Error('body_limit');}chunks.push(value);}}
 finally{reader.releaseLock();}
 const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
 return JSON.parse(new TextDecoder().decode(bytes));
}

// No administrative credential is used. Both verification and the update are
// performed as this same user through Auth, which applies its password policy.
export function createPasswordChangeHandler({url,anonKey,fetchImpl=fetch,timeoutMs=10000}){
 const endpoint=String(url||'').replace(/\/$/,'');
 async function call(path,{method='GET',token,body}={}){
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),timeoutMs);
  try{
   const response=await fetchImpl(endpoint+path,{method,headers:{apikey:anonKey,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},...(body?{body:JSON.stringify(body)}:{}),signal:controller.signal});
   const data=await response.json().catch(()=>null);return {ok:response.ok,status:response.status,data};
  }finally{clearTimeout(timer);}
 }
 return async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(req.method!=='POST')return reply({ok:false,error:'الطريقة غير مسموحة'},405);
  const header=req.headers.get('authorization')||'',match=header.match(/^Bearer\s+(\S+)$/i);
  if(!match)return fail('unauthorized',401);
  let body;
  try{body=await readBody(req);}catch{return fail('invalid_input');}
  const {oldPassword,newPassword,confirmPassword}=body||{};
  if(typeof oldPassword!=='string'||!oldPassword||oldPassword.length>1024||typeof newPassword!=='string'||newPassword.length<6||new TextEncoder().encode(newPassword).length>72||typeof confirmPassword!=='string')return fail('invalid_input');
  if(newPassword!==confirmPassword)return fail('password_mismatch');
  if(oldPassword===newPassword)return fail('same_password');
  let verifiedSession=null,updated=false,uncertain=false;
  try{
   const current=await call('/auth/v1/user',{token:match[1]});
   if(!current.ok||!current.data?.id||!current.data?.email)return fail(current.status>=500?'unavailable':'unauthorized',current.status>=500?503:401);
   const user=current.data;
   const profile=await call('/rest/v1/profiles?select=id,active&id=eq.'+encodeURIComponent(user.id),{token:match[1]});
   if(!profile.ok)return fail('unavailable',503);
   if(!Array.isArray(profile.data)||!profile.data.some(p=>p.id===user.id&&p.active===true))return fail('inactive',403);
   const verified=await call('/auth/v1/token?grant_type=password',{method:'POST',body:{email:user.email,password:oldPassword}});
   if(!verified.ok)return fail(verified.status===429?'rate_limited':verified.status>=500?'unavailable':'invalid_old_password',verified.status===429?429:verified.status>=500?503:403);
   verifiedSession=verified.data;
   if(verifiedSession?.user?.id!==user.id||!verifiedSession.access_token||!verifiedSession.refresh_token)return fail('unauthorized',401);
   // A new verified session also satisfies projects that require recent login.
   // Password changes retain this session and may revoke the old one, so return
   // it to the caller to adopt instead of signing it out after success.
   let result;
   try{result=await call('/auth/v1/user',{method:'PUT',token:verifiedSession.access_token,body:{password:newPassword,current_password:oldPassword}});}
   catch{uncertain=true;return fail('change_uncertain',503);}
   if(result.status>=500){uncertain=true;return fail('change_uncertain',503);}
   if(!result.ok){
    const providerCode=result.data?.error_code||result.data?.code;
    const code=result.status===429?'rate_limited':providerCode==='same_password'?'same_password':['weak_password','validation_failed'].includes(providerCode)?'weak_password':['invalid_credentials','current_password_invalid','current_password_required'].includes(providerCode)?'invalid_old_password':'unavailable';
    return fail(code,result.status===429?429:400);
   }
   if(result.data?.id!==user.id){uncertain=true;return fail('change_uncertain',503);}
   updated=true;
   return reply({ok:true,userId:user.id,session:{access_token:verifiedSession.access_token,refresh_token:verifiedSession.refresh_token,expires_in:verifiedSession.expires_in,expires_at:verifiedSession.expires_at,token_type:'bearer'}});
  }catch{return fail('unavailable',503);}
  finally{
   if(verifiedSession?.access_token&&!updated&&!uncertain){
    try{await call('/auth/v1/logout?scope=local',{method:'POST',token:verifiedSession.access_token});}catch{/* A failed temporary-session cleanup must not reveal credentials. */}
   }
  }
 };
}
