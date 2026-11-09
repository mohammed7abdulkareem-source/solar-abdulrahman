// Bound the fresh session adopted after a password change. Treat logout of an
// explicitly revoked session as complete so this SDK clears its local session.
const guards=new Map();
export async function guardSessionAdoption(token,signal,operation){
 const guard={signal};guards.set(token,guard);
 try{return await operation();}finally{if(guards.get(token)===guard)guards.delete(token);}
}
export function createSessionFetch(fetchImpl=(...args)=>fetch(...args),timeoutMs=15000){
 return async(input,init={})=>{
  const headers=new Headers(init.headers||input?.headers),token=(headers.get('authorization')||'').replace(/^Bearer\s+/i,''),guard=guards.get(token);
  const method=(init.method||input?.method||'GET').toUpperCase();
  if(!guard&&method!=='POST')return fetchImpl(input,init);
  let path;try{path=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url).pathname;}catch{return fetchImpl(input,init);}
  if(method==='POST'&&path.endsWith('/auth/v1/logout')){
   const response=await fetchImpl(input,init);
   if([401,403].includes(response.status)){
    const body=await response.clone().json().catch(()=>null);
    // The installed auth-js turns this into AuthSessionMissingError and
    // returns before _removeSession, retaining the revoked local credentials.
    if(body?.code==='session_not_found'||body?.error_code==='session_not_found')return new Response(null,{status:204,headers:{'Cache-Control':'no-store'}});
   }
   return response;
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
