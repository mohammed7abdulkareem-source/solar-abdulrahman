// Track a session across token refreshes. This identifier is used only to
// discard stale UI work, never to authorize an API call.
export function tokenSessionId(token){
 try{
  const payload=JSON.parse(atob(token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));
  return typeof payload.session_id==='string'?payload.session_id:'';
 }catch{return '';}
}
export function sessionKey(session){
 if(!session?.user)return '';
 return session.user.id+':'+(tokenSessionId(session.access_token)||session.user.last_sign_in_at||'');
}

export const logoutStorageKey='solar_pending_device_logout';
export function pendingLogout(){
 try{return localStorage.getItem(logoutStorageKey)||'';}catch{return '';}
}
export function rememberLogout(key){try{localStorage.setItem(logoutStorageKey,key);}catch{}}
export function finishLogout(key){
 try{if(localStorage.getItem(logoutStorageKey)===key)localStorage.removeItem(logoutStorageKey);}catch{}
}

export function watchAuthSession(auth,{onIdentity,onRead,onUnavailable},fallbackMs=3500,timeoutMs=15000){
 let live=true,revision=0,readTimer;
 function receive(event,session){
  if(!live)return;
  const turn=++revision;
  clearTimeout(readTimer);
  onIdentity(session,event);
  if(session)readTimer=setTimeout(()=>{if(live&&revision===turn)onRead(session,event,()=>live&&revision===turn);},0);
 }
 // Supabase emits INITIAL_SESSION after acquiring its initialization lock.
 // Start a fallback only if we have not heard from this subscription at all.
 const {data:{subscription}}=auth.onAuthStateChange((event,session)=>{
  if(event==='INITIAL_SESSION'&&revision)return;
  receive(event,session);
 });
 const fallback=setTimeout(()=>{
  if(!live||revision)return;
  auth.getSession().then(({data,error})=>{
   if(!live||revision)return;
   if(error)onUnavailable();else receive('INITIAL_SESSION',data.session);
  }).catch(()=>{if(live&&!revision)onUnavailable();});
 },fallbackMs);
 const timeout=setTimeout(()=>{if(live&&!revision)onUnavailable();},timeoutMs);
 return {receive,stop(){live=false;revision++;clearTimeout(fallback);clearTimeout(timeout);clearTimeout(readTimer);subscription.unsubscribe();}};
}
