'use client';
import {useEffect,useRef,useState} from 'react';
import {createPortal} from 'react-dom';
import {supabase} from './supabase';
import {createNoticeTracker,soundEnabled,setSoundEnabled,unlockNotificationSound,playNotificationSound} from './notification-sound.mjs';
import {enablePush,disablePush,pushSupported,registeredOnThisDevice} from './push-client';

function BellIcon(){return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/></svg>}
function PowerIcon(){return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v9M6.4 6.4a8 8 0 1 0 11.2 0"/></svg>}

export default function NotificationCenter({userId,onOpen,onTransfer,onWarehouse,onStockTransfer,onProfit,warehouse=false}){
 const [toast,setToast]=useState(null),[sound,setSound]=useState(false);
 const tracker=useRef(createNoticeTracker()),alive=useRef(true),latestLoad=useRef(0);
 const [enabled,setEnabled]=useState(false),[supported,setSupported]=useState(true),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[notices,setNotices]=useState([]),[open,setOpen]=useState(false),[error,setError]=useState(false);
 function receive(rows,initial=false,realtime=false){
  if(!alive.current)return;
  const fresh=initial?(tracker.current.baseline(rows),[]):tracker.current.receive(rows,realtime);
  if(fresh.length){const notice=fresh.find(n=>!n.read_at)||fresh[0];setToast(notice);window.dispatchEvent(new Event('solar-notification'));if(soundEnabled(userId)&&fresh.some(n=>!n.read_at))playNotificationSound();}
 }
 async function load(initial=false){
  const request=++latestLoad.current;
  const {data,error}=await supabase.from('solar_notifications').select('id,job_id,transfer_id,stock_transfer_id,event,title,body,created_at,read_at').order('created_at',{ascending:false}).limit(30);
  if(!alive.current||request!==latestLoad.current)return;
  if(!error){receive(data||[],initial);setNotices(data||[]);}
 }
 useEffect(()=>{
  alive.current=true;tracker.current=createNoticeTracker();setSupported(pushSupported());setSound(soundEnabled(userId));
  registeredOnThisDevice(userId).then(ok=>{if(alive.current)setEnabled(ok)}).catch(()=>{});load(true);
  const channel=supabase.channel('notices-'+userId).on('postgres_changes',{event:'INSERT',schema:'public',table:'solar_notifications',filter:'user_id=eq.'+userId},({new:n})=>{if(!alive.current||n.user_id!==userId)return;receive([n],false,true);setNotices(v=>[n,...v.filter(x=>x.id!==n.id)].slice(0,30));}).subscribe();
  const refresh=()=>{if(document.visibilityState==='visible')load();};
  const settings=e=>{if(e.detail?.userId!==userId)return;if(e.type==='solar-push-setting'&&typeof e.detail.enabled==='boolean')setEnabled(e.detail.enabled);setSound(soundEnabled(userId));};
  const unlock=()=>{if(soundEnabled(userId))unlockNotificationSound();};
  const timer=setInterval(refresh,10000);window.addEventListener('focus',refresh);window.addEventListener('solar-push-setting',settings);window.addEventListener('solar-sound-setting',settings);document.addEventListener('pointerdown',unlock);
  return()=>{alive.current=false;latestLoad.current++;supabase.removeChannel(channel);clearInterval(timer);window.removeEventListener('focus',refresh);window.removeEventListener('solar-push-setting',settings);window.removeEventListener('solar-sound-setting',settings);document.removeEventListener('pointerdown',unlock)};
 },[userId]);
 useEffect(()=>{if(!toast)return;const timer=setTimeout(()=>setToast(null),8000);return()=>clearTimeout(timer)},[toast]);
 useEffect(()=>{if(!open)return;const close=e=>{if(e.key==='Escape')setOpen(false)};window.addEventListener('keydown',close);return()=>window.removeEventListener('keydown',close)},[open]);
 async function action(fn){if(busy)return;setBusy(true);setMessage('');setError(false);try{await fn()}catch(e){setError(true);setMessage(e.message||'تعذر تنفيذ العملية')}finally{setBusy(false)}}
 async function togglePush(){
  if(!supported){setOpen(true);return}
  await action(async()=>{
   if(enabled){try{await disablePush()}finally{setEnabled(false);window.dispatchEvent(new CustomEvent('solar-push-setting',{detail:{userId,enabled:false}}));}setMessage('تم إيقاف إشعارات هذا الجهاز.');return}
   const audio=unlockNotificationSound();await enablePush(userId);await audio;setSoundEnabled(userId,true);setSound(true);setEnabled(true);window.dispatchEvent(new CustomEvent('solar-push-setting',{detail:{userId,enabled:true}}));setMessage('تم تشغيل إشعارات هذا الجهاز.');
  });
 }
 const unread=notices.filter(n=>!n.read_at).length;
 return <div className="notificationDock" aria-label="الإشعارات">
  <button className="notificationBell" aria-label="فتح الإشعارات" title="الإشعارات" aria-expanded={open} onClick={()=>{setOpen(true);load()}}><BellIcon/>{unread>0&&<span>{unread>9?'9+':unread}</span>}</button>
  <button className={'pushToggle '+(enabled?'enabled':'disabled')} aria-label={enabled?'إيقاف إشعارات هذا الجهاز':'تشغيل إشعارات هذا الجهاز'} title={enabled?'إيقاف الإشعارات':'تشغيل الإشعارات'} disabled={busy} onClick={togglePush}><PowerIcon/></button>
  {toast&&createPortal(<button className="notificationToast" role="status" onClick={()=>{setOpen(true);setToast(null)}}><b>{toast.title}</b><span>{toast.body}</span></button>,document.body)}
  {open&&createPortal(<div className="notificationOverlay" role="presentation" onClick={()=>setOpen(false)}><section className="notificationPanel" role="dialog" aria-modal="true" aria-labelledby="notification-title" onClick={e=>e.stopPropagation()}>
   <header><div><h2 id="notification-title">الإشعارات</h2><small className={enabled?'on':'off'}>{enabled?'الإشعارات مفعّلة على هذا الجهاز':'الإشعارات متوقفة على هذا الجهاز'}</small></div><button className="notificationClose" aria-label="إغلاق" onClick={()=>setOpen(false)}>×</button></header>
   {!supported&&<p className="pushHint">افتح التطبيق بمتصفح يدعم الإشعارات. في iPhone أضفه للشاشة الرئيسية وافتحه من الأيقونة.</p>}
   {supported&&<div className="panelPushActions"><button className={enabled?'stop':'start'} disabled={busy} onClick={togglePush}><PowerIcon/>{enabled?'إيقاف الإشعارات':'تشغيل الإشعارات'}</button>{enabled&&<button className="pushTest" disabled={busy} onClick={()=>action(async()=>{const {error}=await supabase.rpc('solar_push_test');if(error)throw new Error('تعذر إرسال التجربة. انتظر دقيقة إذا أرسلت إشعاراً للتو.');setMessage('تم طلب الإشعار التجريبي. راقب إشعارات الموبايل.');await load()})}>إرسال تجربة</button>}</div>}
   <div className="panelPushActions"><button type="button" onClick={async()=>{if(sound){setSoundEnabled(userId,false);setSound(false);}else{const ready=await unlockNotificationSound();setSoundEnabled(userId,true);setSound(true);const played=ready&&await playNotificationSound();if(!played)setMessage('تعذر تشغيل الصوت. جرّب من المتصفح وارفع صوت الجهاز.');}}}>{sound?'إيقاف صوت التنبيهات':'تشغيل صوت التنبيهات'}</button>{sound&&<button type="button" onClick={()=>playNotificationSound()}>تجربة الصوت</button>}</div>
   {warehouse&&!enabled&&<p className="pushHint">فعّل الإشعارات على جهاز مسؤول التجهيز حتى تصله الفواتير الجديدة خارج البرنامج.</p>}
   {message&&<p role={error?'alert':'status'} className={error?'pushMessage error':'pushMessage'}>{message}</p>}
   <div className="notificationList">{notices.length?notices.map(n=><button key={n.id} className={n.read_at?'read':''} onClick={async()=>{if(!n.read_at){const readAt=new Date().toISOString();const {error}=await supabase.from('solar_notifications').update({read_at:readAt}).eq('id',n.id);if(!error)setNotices(v=>v.map(x=>x.id===n.id?{...x,read_at:readAt}:x));}if(n.stock_transfer_id){setOpen(false);onStockTransfer?.(n.stock_transfer_id);}else if(n.event?.startsWith('profit_')){setOpen(false);onProfit?.();}else if(n.transfer_id){setOpen(false);onTransfer?.(n.transfer_id);}else if(n.job_id&&n.event?.startsWith('warehouse_')){setOpen(false);onWarehouse?.(String(n.job_id),n.event);}else if(n.job_id){setOpen(false);onOpen(String(n.job_id));}}}><b>{n.title}</b><span>{n.body}</span><small>{new Date(n.created_at).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'})}</small></button>):<p>لا توجد إشعارات بعد.</p>}</div>
  </section></div>,document.body)}
 </div>;
}

export function WarehouseAlerts({userId}){
 const [enabled,setEnabled]=useState(false),[sound,setSound]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 useEffect(()=>{let live=true;registeredOnThisDevice(userId).then(ok=>live&&setEnabled(ok)).catch(()=>{});setSound(soundEnabled(userId));const changed=e=>{if(e.detail?.userId!==userId)return;if(e.type==='solar-push-setting')setEnabled(!!e.detail.enabled);setSound(soundEnabled(userId));};window.addEventListener('solar-push-setting',changed);window.addEventListener('solar-sound-setting',changed);return()=>{live=false;window.removeEventListener('solar-push-setting',changed);window.removeEventListener('solar-sound-setting',changed)};},[userId]);
 async function activate(){if(busy)return;setBusy(true);setMessage('');const audio=unlockNotificationSound();try{if(!enabled)await enablePush(userId);setEnabled(true);window.dispatchEvent(new CustomEvent('solar-push-setting',{detail:{userId,enabled:true}}));await audio;setSoundEnabled(userId,true);setSound(true);const played=await playNotificationSound();setMessage(played?'تم تفعيل تنبيهات التجهيز والصوت على هذا الجهاز.':'الإشعارات مفعّلة؛ ارفع صوت الجهاز واضغط تجربة الصوت.');}catch(err){setMessage(err.message||'تعذر تفعيل تنبيهات الجهاز.');}finally{setBusy(false);}}
 return <section className="warehouseAlertSetup"><div><b>تنبيهات التجهيز على هذا الجهاز</b><small>{enabled&&sound?'الإشعارات والصوت مفعّلان':'فعّل الإشعارات والصوت حتى تصلك الفاتورة الجديدة.'}</small></div><button type="button" disabled={busy} onClick={enabled&&sound?()=>playNotificationSound():activate}>{busy?'جاري التفعيل…':enabled&&sound?'تجربة الصوت':'تفعيل الإشعارات والصوت'}</button>{message&&<p role="status">{message}</p>}</section>;
}
