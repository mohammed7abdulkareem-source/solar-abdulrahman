'use client';
import {useEffect,useState} from 'react';
import {supabase} from './supabase';
import {enablePush,disablePush,pushSupported,registeredOnThisDevice} from './push-client';
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
 async function action(fn){if(busy)return;setBusy(true);setMessage('');setError(false);try{await fn()}catch(e){setError(true);setMessage(e.message||'تعذر تنفيذ العملية')}finally{setBusy(false)}}
 const unread=notices.filter(n=>!n.read_at).length;
 return <section className="notificationCenter" aria-label="إشعارات المهام">
  <div className="notificationHeading"><div><b>إشعارات المهام</b><small>{enabled?'مفعّلة لهذا الحساب على هذا الجهاز':'فعّلها لتصلك المهام والإنجازات على الموبايل'}</small></div><button className="notificationBell" aria-expanded={open} onClick={()=>{setOpen(!open);load()}}>الإشعارات {unread>0&&<span>{unread}</span>}</button></div>
  {!supported?<p className="pushHint">افتح التطبيق بمتصفح يدعم الإشعارات. في iPhone أضفه للشاشة الرئيسية وافتحه من الأيقونة.</p>:<div className="pushActions">
   {!enabled?<button disabled={busy} onClick={()=>action(async()=>{await enablePush(userId);setEnabled(true);setMessage('تم تفعيل إشعارات هذا الجهاز. يمكنك إرسال إشعار تجريبي.');})}>تفعيل إشعارات الموبايل</button>:<>
    <button disabled={busy} onClick={()=>action(async()=>{const {error}=await supabase.rpc('solar_push_test');if(error)throw new Error('تعذر إرسال التجربة. انتظر دقيقة إذا أرسلت إشعاراً للتو.');setMessage('تم طلب الإشعار التجريبي. راقب إشعارات الموبايل.');await load()})}>إرسال إشعار تجريبي</button>
    <button className="pushSecondary" disabled={busy} onClick={()=>action(async()=>{try{await disablePush()}finally{setEnabled(false)}setMessage('تم إيقاف إشعارات هذا الجهاز.')})}>إيقاف لهذا الجهاز</button></>}
  </div>}
  {message&&<p role={error?'alert':'status'} className={error?'pushMessage error':'pushMessage'}>{message}</p>}
  {open&&<div className="notificationList">{notices.length?notices.map(n=><button key={n.id} className={n.read_at?'read':''} onClick={async()=>{if(!n.read_at){const readAt=new Date().toISOString();const {error}=await supabase.from('solar_notifications').update({read_at:readAt}).eq('id',n.id);if(!error)setNotices(v=>v.map(x=>x.id===n.id?{...x,read_at:readAt}:x));}if(n.job_id)onOpen(String(n.job_id));}}><b>{n.title}</b><span>{n.body}</span><small>{new Date(n.created_at).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'})}</small></button>):<p>لا توجد إشعارات بعد.</p>}</div>}
 </section>;
}
