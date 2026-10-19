'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import AppIcon from './app-icons';
const options=[['sale','بيع الجملة','receipt'],['system','بيع المنظومات','sun'],['purchase','الشراء','truck']];
export function useOperationStatus(){
 const [data,setData]=useState(null),[error,setError]=useState(''),sequence=useRef(0);
 const reload=useCallback(async()=>{const n=++sequence.current;try{const {data,error}=await supabase.rpc('solar_operation_status');if(error)throw error;if(n===sequence.current){setData(data);setError('');}return data;}catch(e){if(n===sequence.current)setError(e.message||'تعذر تحديث حالة البيع والشراء.');}},[]);
 useEffect(()=>{reload();const refresh=()=>{if(document.visibilityState==='visible')reload();};window.addEventListener('focus',refresh);window.addEventListener('solar-notification',refresh);window.addEventListener('solar-operation-control',refresh);const timer=setInterval(refresh,15000);return()=>{sequence.current++;clearInterval(timer);window.removeEventListener('focus',refresh);window.removeEventListener('solar-notification',refresh);window.removeEventListener('solar-operation-control',refresh);};},[reload]);
 return {data,error,reload};
}
export function useInvoiceOperation(kind){const {data,reload}=useOperationStatus();return {paused:!!data?.[kind],reload};}
export default function OperationControls(){
 const {data,error:loadError,reload}=useOperationStatus(),[busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState(''),[note,setNote]=useState(''),pending=useRef(null),lock=useRef(false);
 async function change(kind,paused){if(lock.current)return;lock.current=true;setBusy(true);setError('');setMessage('');
  try{const payload=pending.current?.payload||{kind,paused,expectedRevision:data.revision,note:note.trim()};if(!pending.current)pending.current={id:crypto.randomUUID(),payload};const {error}=await supabase.rpc('solar_operation_control',{request_id:pending.current.id,payload});if(error)throw error;pending.current=null;setMessage(paused?'تم الإيقاف وإشعار جميع المستخدمين.':'تم الاستئناف وإشعار جميع المستخدمين.');setNote('');window.dispatchEvent(new CustomEvent('solar-operation-control'));await reload();}
  catch(e){if(e.code)pending.current=null;setError(e.code?e.message:'لم يتأكد الرد؛ أعد التأكيد بنفس البيانات ولن تتكرر الإشعارات.');if(e.code==='PT409')await reload();}finally{lock.current=false;setBusy(false);}
 }
 return <section className="operationControls"><header><p>تحكم مستقل بكل قسم، ويشمل الإيقاف جميع الحسابات.</p></header>{(error||loadError)&&<p role="alert" className="workflowError">{error||loadError}</p>}{message&&<p role="status" className="workflowSuccess">{message}</p>}{pending.current&&<button className="uiButton primary" disabled={busy} onClick={()=>change(pending.current.payload.kind,pending.current.payload.paused)}>إعادة تأكيد التغيير</button>}
 <label className="operationReason">سبب التغيير · اختياري<input aria-label="سبب إيقاف أو استئناف العمل" value={note} onChange={e=>setNote(e.target.value)} maxLength={300} disabled={busy||!!pending.current} placeholder="يظهر مع الإشعار"/></label>
 <div className="operationCards">{options.map(([kind,label,icon])=><article key={kind} className={'operationCard '+(data?.[kind]?'paused':'active')}><span className="operationCardIcon"><AppIcon name={icon} size={23}/></span><div><h2>{label}</h2><span className="operationState">{data?data[kind]?'متوقف مؤقتًا':'متاح الآن':'جاري تحميل الحالة…'}</span></div><button type="button" disabled={!data||busy||!!pending.current} onClick={()=>change(kind,!data[kind])}>{data?.[kind]?'استئناف '+label:'إيقاف '+label}</button></article>)}</div><button type="button" className="uiButton" disabled={busy||!!pending.current} onClick={reload}>تحديث الحالة</button>
 </section>;
}
