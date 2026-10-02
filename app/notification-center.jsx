'use client';
import {useEffect,useState} from 'react';
import {createPortal} from 'react-dom';
import {supabase} from './supabase';
import {enablePush,disablePush,pushSupported,registeredOnThisDevice} from './push-client';

function BellIcon(){return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/></svg>}
function PowerIcon(){return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v9M6.4 6.4a8 8 0 1 0 11.2 0"/></svg>}

export default function NotificationCenter({userId,onOpen}){
 const [enabled,setEnabled]=useState(false),[supported,setSupported]=useState(true),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[notices,setNotices]=useState([]),[open,setOpen]=useState(false),[error,setError]=useState(false);
 async function load(){
  const {data,error}=await supabase.from('solar_notifications').select('id,job_id,event,title,body,created_at,read_at').order('created_at',{ascending:false}).limit(30);
  if(!error)setNotices(data||[]);
 }
 useEffect(()=>{
  let live=true;setSupported(pushSupported());registeredOnThisDevice(userId).then(ok=>{if(live)setEnabled(ok)}).catch(()=>{});
  load();
  const refresh=()=>{if(document.visibilityState==='visible')load();};
  const timer=setInterval(refresh,30000);window.addEventListener('focus',refresh);
  return()=>{live=false;clearInterval(timer);window.removeEventListener('focus',refresh)};
 },[userId]);
 useEffect(()=>{if(!open)return;const close=e=>{if(e.key==='Escape')setOpen(false)};window.addEventListener('keydown',close);return()=>window.removeEventListener('keydown',close)},[open]);
 async function action(fn){if(busy)return;setBusy(true);setMessage('');setError(false);try{await fn()}catch(e){setError(true);setMessage(e.message||'تعذر تنفيذ العملية')}finally{setBusy(false)}}
 async function togglePush(){
  if(!supported){setOpen(true);return}
  await action(async()=>{
   if(enabled){try{await disablePush()}finally{setEnabled(false)}setMessage('تم إيقاف إشعارات هذا الجهاز.');return}
   await enablePush(userId);setEnabled(true);setMessage('تم تشغيل إشعارات هذا الجهاز.');
  });
 }
 const unread=notices.filter(n=>!n.read_at).length;
 return <div className="notificationDock" aria-label="إشعارات المهام">
  <button className="notificationBell" aria-label="فتح إشعارات المهام" title="إشعارات المهام" aria-expanded={open} onClick={()=>{setOpen(true);load()}}><BellIcon/>{unread>0&&<span>{unread>9?'9+':unread}</span>}</button>
  <button className={'pushToggle '+(enabled?'enabled':'disabled')} aria-label={enabled?'إيقاف إشعارات هذا الجهاز':'تشغيل إشعارات هذا الجهاز'} title={enabled?'إيقاف الإشعارات':'تشغيل الإشعارات'} disabled={busy} onClick={togglePush}><PowerIcon/></button>
  {open&&createPortal(<div className="notificationOverlay" role="presentation" onClick={()=>setOpen(false)}><section className="notificationPanel" role="dialog" aria-modal="true" aria-labelledby="notification-title" onClick={e=>e.stopPropagation()}>
   <header><div><h2 id="notification-title">إشعارات المهام</h2><small className={enabled?'on':'off'}>{enabled?'الإشعارات مفعّلة على هذا الجهاز':'الإشعارات متوقفة على هذا الجهاز'}</small></div><button className="notificationClose" aria-label="إغلاق" onClick={()=>setOpen(false)}>×</button></header>
   {!supported&&<p className="pushHint">افتح التطبيق بمتصفح يدعم الإشعارات. في iPhone أضفه للشاشة الرئيسية وافتحه من الأيقونة.</p>}
   {supported&&<div className="panelPushActions"><button className={enabled?'stop':'start'} disabled={busy} onClick={togglePush}><PowerIcon/>{enabled?'إيقاف الإشعارات':'تشغيل الإشعارات'}</button>{enabled&&<button className="pushTest" disabled={busy} onClick={()=>action(async()=>{const {error}=await supabase.rpc('solar_push_test');if(error)throw new Error('تعذر إرسال التجربة. انتظر دقيقة إذا أرسلت إشعاراً للتو.');setMessage('تم طلب الإشعار التجريبي. راقب إشعارات الموبايل.');await load()})}>إرسال تجربة</button>}</div>}
   {message&&<p role={error?'alert':'status'} className={error?'pushMessage error':'pushMessage'}>{message}</p>}
   <div className="notificationList">{notices.length?notices.map(n=><button key={n.id} className={n.read_at?'read':''} onClick={async()=>{if(!n.read_at){const readAt=new Date().toISOString();const {error}=await supabase.from('solar_notifications').update({read_at:readAt}).eq('id',n.id);if(!error)setNotices(v=>v.map(x=>x.id===n.id?{...x,read_at:readAt}:x));}if(n.job_id){setOpen(false);onOpen(String(n.job_id));}}}><b>{n.title}</b><span>{n.body}</span><small>{new Date(n.created_at).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'})}</small></button>):<p>لا توجد إشعارات بعد.</p>}</div>
  </section></div>,document.body)}
 </div>;
}
