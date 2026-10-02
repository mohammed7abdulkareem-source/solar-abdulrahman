import {supabase} from './supabase';
export function pushSupported(){return typeof window!=='undefined'&&'serviceWorker'in navigator&&'PushManager'in window&&'Notification'in window;}
export async function setPushDeviceUser(userId){
 if(!('serviceWorker'in navigator))return;
 const reg=await navigator.serviceWorker.ready;
 if(!reg.active)return;
 await new Promise((resolve,reject)=>{
  const channel=new MessageChannel(),timeout=setTimeout(()=>reject(new Error('تعذر تحديث إعدادات الجهاز')),5000);
  channel.port1.onmessage=e=>{clearTimeout(timeout);channel.port1.close();e.data?.ok?resolve():reject(new Error('تعذر حفظ إعدادات الإشعارات'));};
  reg.active.postMessage({type:'SOLAR_PUSH_USER',userId:userId||null},[channel.port2]);
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
export async function disablePush(){
 localStorage.removeItem('solar_push_user');
 if(!('serviceWorker'in navigator))return;
 await setPushDeviceUser(null).catch(()=>{});
 const reg=await navigator.serviceWorker.getRegistration();
 const sub=await reg?.pushManager?.getSubscription();
 let error=null;
 if(sub){
  const result=await supabase.from('solar_push_subscriptions').delete().eq('endpoint',sub.endpoint);
  error=result.error;await sub.unsubscribe();
 }
 const notices=await reg?.getNotifications();notices?.forEach(n=>n.close());
 if(error)throw new Error('تم إيقاف إشعارات هذا المتصفح. تعذرت مزامنة حذف الجهاز؛ أعد المحاولة عند الاتصال.');
}
export async function registeredOnThisDevice(userId){
 if(!pushSupported()||Notification.permission!=='granted')return false;
 if(localStorage.getItem('solar_push_user')!==userId){await setPushDeviceUser(null).catch(()=>{});return false;}
 const reg=await navigator.serviceWorker.ready,sub=await reg.pushManager.getSubscription();
 if(!sub)return false;
 const {data,error}=await supabase.from('solar_push_subscriptions').select('endpoint').eq('endpoint',sub.endpoint).eq('user_id',userId).maybeSingle();
 if(error||!data)return false;
 await setPushDeviceUser(userId);return true;
}
