import {tokenSessionId} from './auth-lifecycle.mjs';
// Bound the fresh session adopted after a password change. Treat logout of an
// explicitly revoked session as complete so this SDK clears its local session.
const guards=new Map();
export async function guardSessionAdoption(token,signal,operation,{passwordLogin=false}={}){
 const guard={signal,passwordLogin};guards.set(token,guard);
 try{return await operation();}finally{if(guards.get(token)===guard)guards.delete(token);}
}
// setSession acquires the shared browser lock before it makes the user
// validation request. Bound this wait in the SDK itself so a timed-out grant
// cannot acquire the lock later and install an abandoned session.
export function passwordSessionLock(sdkLock,timeoutMs=15000){
 return async(name,wait,operation)=>{
  if(wait>=0||!guards.size||![...guards.values()].some(guard=>guard.passwordLogin))return sdkLock(name,wait,operation);
  let acquired=false;
  try{return await sdkLock(name,timeoutMs,()=>{acquired=true;return operation();});}
  catch(error){
   if(!acquired&&(error?.name==='AbortError'||error?.isAcquireTimeout))
    throw Object.assign(new Error('تم التحقق من كلمة المرور. أغلق أي تبويب آخر للبرنامج على هذا الجهاز وحاول الدخول مرة ثانية.'),{code:'login_lock_timeout'});
   throw error;
  }
 };
}
let localSignOut=null;
export async function signOutDevice(auth,session,isCurrent){
 if(localSignOut)throw new Error('يوجد تسجيل خروج قيد التنفيذ.');
 localSignOut={token:session.access_token,sessionId:tokenSessionId(session.access_token),isCurrent};
 try{return await auth.signOut({scope:'local'});}finally{localSignOut=null;}
}
export function createSessionFetch(fetchImpl=(...args)=>fetch(...args),timeoutMs=15000){
 return async(input,init={})=>{
  const headers=new Headers(init.headers||input?.headers),token=(headers.get('authorization')||'').replace(/^Bearer\s+/i,''),guard=guards.get(token);
  const method=(init.method||input?.method||'GET').toUpperCase();
  if(!guard&&method!=='POST')return fetchImpl(input,init);
  let path;try{path=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url).pathname;}catch{return fetchImpl(input,init);}
  if(method==='POST'&&path.endsWith('/auth/v1/logout')){
   const logout=localSignOut;
   if(logout&&(!logout.isCurrent()||(token!==logout.token&&(!logout.sessionId||tokenSessionId(token)!==logout.sessionId)))){
    return Response.json({message:'تغيّرت جلسة الجهاز.'},{status:409});
   }
   const controller=new AbortController(),incoming=init.signal||input?.signal;
   const abort=()=>controller.abort();
   if(incoming?.aborted)abort();else incoming?.addEventListener('abort',abort,{once:true});
   const timer=logout?setTimeout(abort,timeoutMs):undefined;
   try{
    const response=await fetchImpl(input,logout?{...init,signal:controller.signal}:init);
    if([401,403].includes(response.status)){
     const body=await response.clone().json().catch(()=>null);
     if(body?.code==='session_not_found'||body?.error_code==='session_not_found')return new Response(null,{status:204,headers:{'Cache-Control':'no-store'}});
    }
    // The SDK reads non-success bodies before releasing its auth lock.
    if(logout&&!response.ok)await response.clone().arrayBuffer();
    return response;
   }finally{clearTimeout(timer);incoming?.removeEventListener('abort',abort);}
  }
  if(!guard)return fetchImpl(input,init);
  if(method!=='GET'||!path.endsWith('/auth/v1/user'))return fetchImpl(input,init);
  const controller=new AbortController(),signals=[guard.signal,init.signal||input?.signal].filter(Boolean);
  const abort=()=>controller.abort();for(const signal of signals){if(signal.aborted)abort();else signal.addEventListener('abort',abort,{once:true});}
  const timer=setTimeout(abort,timeoutMs);
  try{
   if(controller.signal.aborted)throw new DOMException('Session adoption cancelled','AbortError');
   const response=await fetchImpl(input,{...init,signal:controller.signal});
   // Bound reading the body too, before the SDK can persist this session.
   const body=await response.arrayBuffer();
   if(controller.signal.aborted)throw new DOMException('Session adoption cancelled','AbortError');
   return new Response(body,{status:response.status,statusText:response.statusText,headers:response.headers});
  }finally{clearTimeout(timer);for(const signal of signals)signal.removeEventListener('abort',abort);}
 };
}
