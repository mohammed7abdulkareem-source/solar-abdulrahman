import {supabase} from './supabase';
import {releaseDevicePush} from './push-release.mjs';
export function pushSupported(){return typeof window!=='undefined'&&'serviceWorker'in navigator&&'PushManager'in window&&'Notification'in window;}
export async function setPushDeviceUser(userId,registration,expectedUserId){
 if(!('serviceWorker'in navigator))return;
 const reg=registration||(userId?await navigator.serviceWorker.ready:await navigator.serviceWorker.getRegistration());
 if(!reg?.active)return;
 await new Promise((resolve,reject)=>{
  const channel=new MessageChannel(),timeout=setTimeout(()=>{channel.port1.close();reject(new Error('تعذر تحديث إعدادات الجهاز'));},5000);
  channel.port1.onmessage=e=>{clearTimeout(timeout);channel.port1.close();e.data?.ok?resolve():reject(new Error('تعذر حفظ إعدادات الإشعارات'));};
  reg.active.postMessage({type:'SOLAR_PUSH_USER',userId:userId||null,expectedUserId},[channel.port2]);
 });
}
function publicKeyBytes(key){const raw=atob(key.replace(/-/g,'+').replace(/_/g,'/').padEnd(Math.ceil(key.length/4)*4,'='));return Uint8Array.from(raw,c=>c.charCodeAt(0));}
export async function enablePush(userId){
 if(!pushSupported())throw new Error('هذا المتصفح لا يدعم إشعارات التطبيق. افتح البرنامج من Chrome، أو ثبته على الشاشة الرئيسية في iPhone.');
 // Must run directly from the user's click before any network request.
 const permission=await Notification.requestPermission();
 if(permission!=='granted')throw new Error('اسمح بالإشعارات من إعدادات الموقع في المتصفح ثم حاول مجدداً.');
 const {data:key,error}=await supabase.rpc('solar_push_public_key');
 if(error||!key)throw new Error('تعذر تهيئة الإشعارات. حاول مجدداً.');
 await navigator.serviceWorker.register('/sw.js');
 const reg=await navigator.serviceWorker.ready;
 let sub=await reg.pushManager.getSubscription();
 if(!sub)sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:publicKeyBytes(key)});
 const saved=await supabase.rpc('solar_push_register',{subscription:sub.toJSON()});
 if(saved.error)throw new Error('لم يكتمل تسجيل الجهاز للإشعارات. حاول مجدداً.');
 await setPushDeviceUser(userId);
 localStorage.setItem('solar_push_user',userId);
 return true;
}
export async function disablePush({userId=localStorage.getItem('solar_push_user'),isCurrent,timeoutMs}={}){
 return releaseDevicePush({
  worker:navigator.serviceWorker,storage:localStorage,userId,isCurrent,timeoutMs,
  clearBinding:(reg,expected)=>setPushDeviceUser(null,reg,expected||undefined),
  async removeEndpoint(endpoint,owner,signal){
   if(!owner)return;
   const result=await supabase.from('solar_push_subscriptions').delete().eq('endpoint',endpoint).eq('user_id',owner).abortSignal(signal);
   if(result.error)throw new Error('تم إيقاف إشعارات هذا المتصفح. تعذرت مزامنة حذف الجهاز؛ أعد المحاولة عند الاتصال.');
  }
 });
}
export async function registeredOnThisDevice(userId){
 if(!pushSupported()||Notification.permission!=='granted')return false;
 const bound=localStorage.getItem('solar_push_user');
 if(bound!==userId){
  const reg=await navigator.serviceWorker.getRegistration();
  if(reg&&localStorage.getItem('solar_push_user')===bound)await setPushDeviceUser(null,reg,bound||undefined).catch(()=>{});
  return false;
 }
 const reg=await navigator.serviceWorker.ready,sub=await reg.pushManager.getSubscription();
 if(!sub)return false;
 const {data,error}=await supabase.from('solar_push_subscriptions').select('endpoint').eq('endpoint',sub.endpoint).eq('user_id',userId).maybeSingle();
 if(error||!data||localStorage.getItem('solar_push_user')!==userId)return false;
 await setPushDeviceUser(userId,reg);return true;
}
