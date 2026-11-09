import {supabase} from './supabase';
import {guardSessionAdoption} from './auth-session-fetch.mjs';

function failure(message,code,uncertain=false){return Object.assign(new Error(message),{code,uncertain});}
export async function changeOwnPassword({oldPassword,newPassword,confirmPassword,userId}){
 const adoption=new AbortController();
 const {data:{subscription}}=supabase.auth.onAuthStateChange((event,session)=>{
  if(event==='SIGNED_OUT'||(session?.user?.id&&session.user.id!==userId))adoption.abort();
 });
 try{return await change({oldPassword,newPassword,confirmPassword,userId},adoption);}
 finally{subscription.unsubscribe();}
}
async function change({oldPassword,newPassword,confirmPassword,userId},adoption){
 let result,timer;
 try{
  // This installed functions client does not forward AbortSignal. Bound the
  // wait explicitly; a late response must not adopt a session after timeout.
  result=await Promise.race([
   supabase.functions.invoke('solar-change-password',{body:{oldPassword,newPassword,confirmPassword}}),
   new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('timeout')),45000);}),
  ]);
 }catch{
  throw failure('لم يتأكد رد الحفظ؛ قد يكون الرقم السري تغيّر. عند تسجيل الدخول جرّب الرقم الجديد أولاً.','change_uncertain',true);
 }finally{clearTimeout(timer);}
 if(result.error){
  let response;
  try{response=await result.error.context?.json();}catch{}
  if(response?.error)throw failure(response.error,response.code||'unavailable',response.uncertain===true);
  throw failure('لم يتأكد رد الحفظ؛ قد يكون الرقم السري تغيّر. عند تسجيل الدخول جرّب الرقم الجديد أولاً.','change_uncertain',true);
 }
 const data=result.data;
 if(!data?.ok||data.userId!==userId||!data.session?.access_token||!data.session?.refresh_token)throw failure('لم يتأكد رد الحفظ؛ أعد تسجيل الدخول بالرقم الجديد للتحقق.','change_uncertain',true);
 // The server has confirmed the change. A session-storage/network failure must
 // not be presented as a failed password change or trigger another update.
 try{
  const {data:current}=await supabase.auth.getSession();
  if(adoption.signal.aborted||current?.session?.user?.id!==userId)return {ok:true,sessionRestored:false};
  const {data:restored,error}=await guardSessionAdoption(data.session.access_token,adoption.signal,()=>supabase.auth.setSession({access_token:data.session.access_token,refresh_token:data.session.refresh_token}));
  return {ok:true,sessionRestored:!error&&restored?.user?.id===userId};
 }catch{return {ok:true,sessionRestored:false};}
}
