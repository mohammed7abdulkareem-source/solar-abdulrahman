'use client';
import {useEffect,useRef,useState} from 'react';
import AppIcon from './app-icons';
import WorkspaceDialog from './workspace-dialog';
import {supabase} from './supabase';
import {customerRecord,saveCustomer} from './customer-store.mjs';
import {formatMoney,currencyUnit} from './money-format.mjs';
import {partyBalanceMeaning} from './compact-party-utils.mjs';
import './customer-owner-transfer.css';

export default function CustomerOwnerTransfer({account,disabled,onSaved}){
 const [open,setOpen]=useState(false),[step,setStep]=useState('choose');
 const [record,setRecord]=useState(null),[owners,setOwners]=useState([]),[ownerId,setOwnerId]=useState('');
 const [loading,setLoading]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const attempt=useRef(null),request=useRef(0),saving=useRef(false),review=useRef(null);
 const selected=owners.find(owner=>owner.id===ownerId);
 useEffect(()=>()=>{request.current++;},[]);
 useEffect(()=>{if(open&&step==='review')review.current?.focus({preventScroll:true});},[open,step]);

 async function load(){
  const n=++request.current;
  setRecord(null);setOwners([]);setOwnerId('');setStep('choose');setError('');setLoading(true);
  try{
   const [fresh,targets]=await Promise.all([customerRecord(account.id),supabase.rpc('solar_customer_transfer_targets')]);
   if(targets.error)throw targets.error;
   if(!fresh?.token||String(fresh.id)!==String(account.id)||!Array.isArray(targets.data)||fresh.balance==null||!Number.isFinite(Number(fresh.balance))){
    throw new Error('تعذر تحميل بيانات التحويل.');
   }
   if(n===request.current){setRecord(fresh);setOwners(targets.data.filter(owner=>owner.id!==fresh.ownerId));}
  }catch(e){if(n===request.current)setError(e.message||'تعذر تحميل المسؤولين. أعد المحاولة.');}
  finally{if(n===request.current)setLoading(false);}
 }
 function start(){setOpen(true);if(!attempt.current)void load();}
 function close(){
  if(saving.current)return;
  request.current++;setOpen(false);setLoading(false);
 }
 async function submit(event){
  event.preventDefault();
  if(!record||!selected||saving.current)return;
  if(step==='choose'){setStep('review');setError('');return;}
  saving.current=true;setBusy(true);setError('');
  const n=request.current;
  try{
   const saved=await saveCustomer(attempt,'transfer_owner',{id:record.id,ownerId:selected.id,token:record.token});
   if(n!==request.current)return;
   setOpen(false);setRecord(null);setOwners([]);setOwnerId('');setStep('choose');
   await onSaved({...saved,message:'تم تحويل الزبون إلى '+(saved?.ownerName||selected.name)+'.'});
  }catch(e){
   if(n!==request.current)return;
   if(attempt.current){setError('تعذّر تأكيد نتيجة التحويل. أعد تأكيد التحويل بنفس البيانات.');}
   else{setError(e.message||'تعذر تحويل الزبون. حدّث بيانات التحويل.');setRecord(null);}
  }finally{saving.current=false;if(n===request.current)setBusy(false);}
 }
 const sourceName=record?.ownerName||(record?.ownerId?'المسؤول الحالي':'غير مسند');
 return <>
  <button type="button" className="statementTransferTrigger" disabled={disabled||busy} onClick={start}>
   <AppIcon name="exchange" size={16}/>تحويل الزبون
  </button>
  <WorkspaceDialog open={open} title="تحويل الزبون" className="statementTransferDialog" onClose={close}>
   <p className="statementTransferCustomer">{record?.name||account.name}</p>
   {loading&&<p role="status">جاري تحميل بيانات التحويل…</p>}
   {error&&<p className="miniAlert" role="alert">{error}</p>}
   {!loading&&!record&&<button type="button" className="uiButton secondary" onClick={load}>تحديث بيانات التحويل</button>}
   {record&&<form onSubmit={submit}>
    {step==='choose'?<>
     <div className="statementTransferSource"><span>المسؤول الحالي</span><strong>{sourceName}</strong></div>
     {owners.length?<label>المسؤول الجديد
      <select value={ownerId} onChange={event=>setOwnerId(event.target.value)} required>
       <option value="">اختر المستخدم</option>
       {owners.map(owner=><option key={owner.id} value={owner.id}>{owner.name}</option>)}
      </select>
     </label>:<p role="status">لا يوجد مستخدم آخر متاح للتحويل.</p>}
    </>:<dl className="statementTransferReview" ref={review} tabIndex={-1} aria-label="مراجعة التحويل">
     <div><dt>من</dt><dd>{sourceName}</dd></div>
     <div><dt>إلى</dt><dd>{selected?.name}</dd></div>
     <div><dt>الرصيد الحالي</dt><dd><bdi>{formatMoney(Math.abs(record.balance),account.currency)} {currencyUnit(account.currency)}</bdi>
      <small>{partyBalanceMeaning('customer',record.balance)}</small></dd></div>
    </dl>}
    <div className="statementTransferFooter">
     {step==='review'&&<button type="button" className="uiButton secondary" disabled={busy||!!attempt.current} onClick={()=>{setStep('choose');setError('');}}>تغيير المستخدم</button>}
     <button type="submit" className="uiButton primary" disabled={busy||!selected}>{step==='choose'?'مراجعة التحويل':busy?'جاري تأكيد التحويل…':'تأكيد تحويل الزبون'}</button>
    </div>
   </form>}
  </WorkspaceDialog>
 </>;
}
