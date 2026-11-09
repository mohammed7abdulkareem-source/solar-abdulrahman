'use client';
import {useEffect,useRef,useState} from 'react';
import {createPortal} from 'react-dom';
import {supabase} from './supabase';
import {createNoticeTracker,soundEnabled,setSoundEnabled,unlockNotificationSound,playNotificationSound} from './notification-sound.mjs';
import AdminAnnouncement from './admin-announcement';
import {enablePush,disablePush,pushSupported,registeredOnThisDevice} from './push-client';
import {notificationReadBoundary,applyConfirmedNotificationReads,mergeNotificationRows,markAllNotificationsRead,markNotificationIdsRead} from './notification-read-state.mjs';
import './notification-read.css';

function BellIcon(){return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/></svg>}
function PowerIcon(){return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v9M6.4 6.4a8 8 0 1 0 11.2 0"/></svg>}

export default function NotificationCenter({userId,onOpen,onTransfer,onWarehouse,onStockTransfer,onProfit,onDeleteRequest,warehouse=false,admin=false}){
 const [toast,setToast]=useState(null),[sound,setSound]=useState(false);
 const tracker=useRef(createNoticeTracker()),alive=useRef(true),latestLoad=useRef(0),panel=useRef(null);
 const [loadError,setLoadError]=useState(''),[loading,setLoading]=useState(false),[noticeOwner,setNoticeOwner]=useState(userId),[unreadTotal,setUnreadTotal]=useState(null),[readBusy,setReadBusy]=useState(false),[readMessage,setReadMessage]=useState(''),[readError,setReadError]=useState(false);
 const currentUser=useRef(userId),sessionEpoch=useRef(0),readAllLock=useRef(false),readController=useRef(null),readingIds=useRef(new Set()),confirmedReads=useRef(new Map()),arrivals=useRef(new Map()),arrivalVersion=useRef(0);currentUser.current=userId;
 const current=(owner,epoch)=>alive.current&&currentUser.current===owner&&sessionEpoch.current===epoch;
 const [enabled,setEnabled]=useState(false),[supported,setSupported]=useState(true),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[notices,setNotices]=useState([]),[open,setOpen]=useState(false),[error,setError]=useState(false);
 function receive(rows,initial=false,realtime=false){
  if(!alive.current)return;
  const fresh=initial?(tracker.current.baseline(rows),[]):tracker.current.receive(rows,realtime);
  if(fresh.length){const notice=fresh.find(n=>!n.read_at)||fresh[0];setToast(notice);window.dispatchEvent(new Event('solar-notification'));if(soundEnabled(userId)&&fresh.some(n=>!n.read_at))playNotificationSound();}
 }
 async function load(initial=false){
  if(readAllLock.current||readingIds.current.size)return;
  const request=++latestLoad.current,owner=userId,epoch=sessionEpoch.current,version=arrivalVersion.current;
  setLoading(true);
  try{
   const [list,count]=await Promise.all([
    supabase.from('solar_notifications').select('id,job_id,transfer_id,stock_transfer_id,delete_request_id,event,title,body,created_at,read_at').eq('user_id',owner).order('created_at',{ascending:false}).order('id',{ascending:false}).limit(30),
    supabase.from('solar_notifications').select('id',{count:'exact',head:true}).eq('user_id',owner).is('read_at',null)
   ]);
   if(!current(owner,epoch)||request!==latestLoad.current)return;
   if(list.error)throw list.error;
   const rows=list.data||[],newer=[...arrivals.current.values()].filter(entry=>entry.version>version).map(entry=>entry.notice);
   receive(rows,initial);
   setNotices(mergeNotificationRows(rows,newer,confirmedReads.current));
   if(count.error||!Number.isFinite(count.count))throw count.error||new Error('Unread count unavailable');
   setLoadError('');
   if(arrivalVersion.current!==version){void load();return;}
   arrivals.current.clear();setUnreadTotal(count.count);
  }catch{if(current(owner,epoch)&&request===latestLoad.current){setUnreadTotal(null);setLoadError('تعذر تحديث الإشعارات وعدد غير المقروء. تحقق من الاتصال وأعد المحاولة.');}}
  finally{if(current(owner,epoch)&&request===latestLoad.current)setLoading(false);}
 }
 function confirmReads(rows,owner,epoch){
  if(!current(owner,epoch))return;
  const changed=rows.filter(row=>!confirmedReads.current.has(row.id));
  for(const row of rows)confirmedReads.current.set(row.id,row.read_at);
  setNotices(value=>applyConfirmedNotificationReads(value,confirmedReads.current));
  setUnreadTotal(value=>value===null?null:Math.max(0,value-changed.length));
 }
 async function markAllRead(){
  const before=notificationReadBoundary(notices);
  if(readAllLock.current||loading||unreadTotal===null||unreadTotal===0||!before||noticeOwner!==userId)return;
  const owner=userId,epoch=sessionEpoch.current,controller=new AbortController();
  readAllLock.current=true;readController.current=controller;++latestLoad.current;setLoading(false);setReadBusy(true);setReadMessage('');setReadError(false);
  const timeout=setTimeout(()=>controller.abort(),45000);
  try{
   const result=await markAllNotificationsRead(supabase,{userId:owner,before,signal:controller.signal,onConfirmed:rows=>confirmReads(rows,owner,epoch)});
   if(current(owner,epoch))setReadMessage(result.updatedCount?'تم تعليم '+result.updatedCount+' إشعارًا كمقروء.':'تم التحقق؛ الإشعارات السابقة مقروءة بالفعل.');
  }catch(error){if(current(owner,epoch)){setReadError(true);setReadMessage(error.updatedCount?'تم تأكيد قراءة '+error.updatedCount+' إشعارًا ولم تكتمل البقية. أعد المحاولة.':'لم يتأكد إكمال قراءة الإشعارات. حدّث القائمة وأعد المحاولة.');}}
  finally{clearTimeout(timeout);if(current(owner,epoch)){readAllLock.current=false;readController.current=null;setReadBusy(false);void load();}}
 }
 async function markOneRead(notice){
  if(notice.read_at||readingIds.current.has(notice.id))return;
  const owner=userId,epoch=sessionEpoch.current;
  readingIds.current.add(notice.id);++latestLoad.current;setLoading(false);
  try{await markNotificationIdsRead(supabase,{userId:owner,ids:[notice.id],onConfirmed:rows=>confirmReads(rows,owner,epoch)});}
  catch{if(current(owner,epoch)){setReadError(true);setReadMessage('لم يتأكد تعليم الإشعار كمقروء. أعد المحاولة.');}}
  finally{if(current(owner,epoch)){readingIds.current.delete(notice.id);void load();}}
 }
 useEffect(()=>{
  alive.current=true;sessionEpoch.current++;readAllLock.current=false;readingIds.current=new Set();confirmedReads.current=new Map();arrivals.current=new Map();arrivalVersion.current=0;setNoticeOwner(userId);setNotices([]);setUnreadTotal(null);setReadBusy(false);setReadMessage('');setReadError(false);setToast(null);tracker.current=createNoticeTracker();setSupported(pushSupported());setSound(soundEnabled(userId));
  registeredOnThisDevice(userId).then(ok=>{if(alive.current)setEnabled(ok)}).catch(()=>{});load(true);
  const channel=supabase.channel('notices-'+userId).on('postgres_changes',{event:'INSERT',schema:'public',table:'solar_notifications',filter:'user_id=eq.'+userId},({new:n})=>{if(!alive.current||currentUser.current!==userId||n.user_id!==userId)return;arrivals.current.set(n.id,{notice:n,version:++arrivalVersion.current});receive([n],false,true);setNotices(v=>mergeNotificationRows(v,[n],confirmedReads.current));setUnreadTotal(null);void load();}).subscribe();
  const refresh=()=>{if(document.visibilityState==='visible')load();};
  const settings=e=>{if(e.detail?.userId!==userId)return;if(e.type==='solar-push-setting'&&typeof e.detail.enabled==='boolean')setEnabled(e.detail.enabled);setSound(soundEnabled(userId));};
  const unlock=()=>{if(soundEnabled(userId))unlockNotificationSound();};
  const timer=setInterval(refresh,10000);window.addEventListener('focus',refresh);window.addEventListener('solar-push-setting',settings);window.addEventListener('solar-sound-setting',settings);document.addEventListener('pointerdown',unlock);
  return()=>{alive.current=false;latestLoad.current++;sessionEpoch.current++;readController.current?.abort();supabase.removeChannel(channel);clearInterval(timer);window.removeEventListener('focus',refresh);window.removeEventListener('solar-push-setting',settings);window.removeEventListener('solar-sound-setting',settings);document.removeEventListener('pointerdown',unlock)};
 },[userId]);
 useEffect(()=>{if(!toast)return;const timer=setTimeout(()=>setToast(null),8000);return()=>clearTimeout(timer)},[toast]);
 useEffect(()=>{if(!open)return;const previous=document.activeElement,overflow=document.body.style.overflow;document.body.style.overflow='hidden';panel.current?.querySelector('button')?.focus();const close=e=>{if(e.key==='Escape')setOpen(false);if(e.key==='Tab'){const nodes=[...(panel.current?.querySelectorAll('button:not(:disabled),input:not(:disabled),textarea:not(:disabled),select:not(:disabled),a[href]')||[])].filter(n=>n.getClientRects().length),first=nodes[0],last=nodes.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}};window.addEventListener('keydown',close);return()=>{document.body.style.overflow=overflow;window.removeEventListener('keydown',close);if(previous?.isConnected)previous.focus({preventScroll:true});};},[open]);
 async function action(fn){if(busy)return;setBusy(true);setMessage('');setError(false);try{await fn()}catch(e){setError(true);setMessage(e.message||'تعذر تنفيذ العملية')}finally{setBusy(false)}}
 async function togglePush(){
  if(!supported){setOpen(true);return}
  await action(async()=>{
   if(enabled){try{await disablePush()}finally{setEnabled(false);window.dispatchEvent(new CustomEvent('solar-push-setting',{detail:{userId,enabled:false}}));}setMessage('تم إيقاف إشعارات هذا الجهاز.');return}
   const audio=unlockNotificationSound();await enablePush(userId);await audio;setSoundEnabled(userId,true);setSound(true);setEnabled(true);window.dispatchEvent(new CustomEvent('solar-push-setting',{detail:{userId,enabled:true}}));setMessage('تم تشغيل إشعارات هذا الجهاز.');
  });
 }
 const visibleNotices=noticeOwner===userId?notices:[],visibleUnreadTotal=noticeOwner===userId?unreadTotal:null,unread=noticeOwner===userId?(visibleUnreadTotal??visibleNotices.filter(n=>!n.read_at).length):0;
 return <div className="notificationDock" aria-label="الإشعارات">
  <button className="notificationBell" aria-label="فتح الإشعارات" title="الإشعارات" aria-expanded={open} onClick={()=>{setOpen(true);load()}}><BellIcon/>{unread>0&&<span>{unread>9?'9+':unread}</span>}</button>
  <button className={'pushToggle '+(enabled?'enabled':'disabled')} aria-label={enabled?'إيقاف إشعارات هذا الجهاز':'تشغيل إشعارات هذا الجهاز'} title={enabled?'إيقاف الإشعارات':'تشغيل الإشعارات'} disabled={busy} onClick={togglePush}><PowerIcon/></button>
  {toast&&noticeOwner===userId&&createPortal(<button className="notificationToast" role="status" onClick={()=>{setOpen(true);setToast(null)}}><b>{toast.title}</b><span>{toast.body}</span></button>,document.body)}
  {open&&createPortal(<div className="notificationOverlay" role="presentation" onClick={()=>setOpen(false)}><section ref={panel} className="notificationPanel" role="dialog" aria-modal="true" aria-labelledby="notification-title" onClick={e=>e.stopPropagation()}>
   <header><div><h2 id="notification-title">الإشعارات</h2><small className={enabled?'on':'off'}>{enabled?'الإشعارات مفعّلة على هذا الجهاز':'الإشعارات متوقفة على هذا الجهاز'}</small></div><button className="notificationClose" aria-label="إغلاق" onClick={()=>setOpen(false)}>×</button></header>
   {!supported&&<p className="pushHint">افتح التطبيق بمتصفح يدعم الإشعارات. في iPhone أضفه للشاشة الرئيسية وافتحه من الأيقونة.</p>}
   {supported&&<div className="panelPushActions"><button className={enabled?'stop':'start'} disabled={busy} onClick={togglePush}><PowerIcon/>{enabled?'إيقاف الإشعارات':'تشغيل الإشعارات'}</button>{enabled&&<button className="pushTest" disabled={busy} onClick={()=>action(async()=>{const {error}=await supabase.rpc('solar_push_test');if(error)throw new Error('تعذر إرسال التجربة. انتظر دقيقة إذا أرسلت إشعاراً للتو.');setMessage('تم طلب الإشعار التجريبي. راقب إشعارات الموبايل.');await load()})}>إرسال تجربة</button>}</div>}
   <div className="panelPushActions"><button type="button" onClick={async()=>{if(sound){setSoundEnabled(userId,false);setSound(false);}else{const ready=await unlockNotificationSound();setSoundEnabled(userId,true);setSound(true);const played=ready&&await playNotificationSound();if(!played)setMessage('تعذر تشغيل الصوت. جرّب من المتصفح وارفع صوت الجهاز.');}}}>{sound?'إيقاف صوت التنبيهات':'تشغيل صوت التنبيهات'}</button>{sound&&<button type="button" onClick={()=>playNotificationSound()}>تجربة الصوت</button>}</div>
   {warehouse&&!enabled&&<p className="pushHint">فعّل الإشعارات على جهاز مسؤول التجهيز حتى تصله الفواتير الجديدة خارج البرنامج.</p>}
   {message&&<p role={error?'alert':'status'} className={error?'pushMessage error':'pushMessage'}>{message}</p>}
   {admin&&<AdminAnnouncement onSent={()=>load()}/>}
   <div className="notificationReadActions"><span data-testid="notification-unread-count" aria-live="polite">{visibleUnreadTotal===null?'عدد غير المقروء غير مؤكد':visibleUnreadTotal+' غير مقروء'}</span><button type="button" disabled={readBusy||loading||visibleUnreadTotal===null||visibleUnreadTotal===0||!visibleNotices.length} onClick={markAllRead}>{readBusy?'جاري تعليم الإشعارات…':'الكل مقروء'}</button></div>
   {readMessage&&noticeOwner===userId&&<p role={readError?'alert':'status'} className={'notificationReadMessage'+(readError?' error':'')}>{readMessage}</p>}
   <div className="notificationList" aria-busy={loading||readBusy}>{loadError&&<p role="alert">{loadError}<button type="button" disabled={loading} onClick={()=>load()}>إعادة المحاولة</button></p>}{loading&&!visibleNotices.length&&<p role="status">جاري تحميل الإشعارات…</p>}{visibleNotices.length?visibleNotices.map(n=><button key={n.id} className={n.read_at?'read':''} onClick={async()=>{const owner=userId,epoch=sessionEpoch.current;await markOneRead(n);if(!current(owner,epoch))return;if(n.delete_request_id){setOpen(false);onDeleteRequest?.(n.delete_request_id);}else if(n.stock_transfer_id){setOpen(false);onStockTransfer?.(n.stock_transfer_id);}else if(n.event?.startsWith('profit_')){setOpen(false);onProfit?.();}else if(n.transfer_id){setOpen(false);onTransfer?.(n.transfer_id);}else if(n.job_id&&n.event?.startsWith('warehouse_')){setOpen(false);onWarehouse?.(String(n.job_id),n.event);}else if(n.job_id){setOpen(false);onOpen(String(n.job_id));}}}><b>{n.title}</b><span>{n.body}</span><small>{new Date(n.created_at).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'})}</small></button>):!loading&&!loadError?<p>لا توجد إشعارات بعد.</p>:null}</div>
  </section></div>,document.body)}
 </div>;
}

export function WarehouseAlerts({userId}){
 const [enabled,setEnabled]=useState(false),[sound,setSound]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 useEffect(()=>{let live=true;registeredOnThisDevice(userId).then(ok=>live&&setEnabled(ok)).catch(()=>{});setSound(soundEnabled(userId));const changed=e=>{if(e.detail?.userId!==userId)return;if(e.type==='solar-push-setting')setEnabled(!!e.detail.enabled);setSound(soundEnabled(userId));};window.addEventListener('solar-push-setting',changed);window.addEventListener('solar-sound-setting',changed);return()=>{live=false;window.removeEventListener('solar-push-setting',changed);window.removeEventListener('solar-sound-setting',changed)};},[userId]);
 async function activate(){if(busy)return;setBusy(true);setMessage('');const audio=unlockNotificationSound();try{if(!enabled)await enablePush(userId);setEnabled(true);window.dispatchEvent(new CustomEvent('solar-push-setting',{detail:{userId,enabled:true}}));await audio;setSoundEnabled(userId,true);setSound(true);const played=await playNotificationSound();setMessage(played?'تم تفعيل تنبيهات التجهيز والصوت على هذا الجهاز.':'الإشعارات مفعّلة؛ ارفع صوت الجهاز واضغط تجربة الصوت.');}catch(err){setMessage(err.message||'تعذر تفعيل تنبيهات الجهاز.');}finally{setBusy(false);}}
 return <section className="warehouseAlertSetup"><div><b>تنبيهات التجهيز على هذا الجهاز</b><small>{enabled&&sound?'الإشعارات والصوت مفعّلان':'فعّل الإشعارات والصوت حتى تصلك الفاتورة الجديدة.'}</small></div><button type="button" disabled={busy} onClick={enabled&&sound?()=>playNotificationSound():activate}>{busy?'جاري التفعيل…':enabled&&sound?'تجربة الصوت':'تفعيل الإشعارات والصوت'}</button>{message&&<p role="status">{message}</p>}</section>;
}
