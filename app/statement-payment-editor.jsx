'use client';
import {useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import {saveRequest} from './save-request.mjs';
import {canOpenPage} from './access-utils.mjs';
import {deletionResultMessage,requestReceiptDeletion} from './receipt-deletion.mjs';
import {readCashAttempt,rememberCashAttempt,clearCashAttempt} from './cash-record-attempt.mjs';
import {money,receiptNumber} from './supplier-utils.mjs';
import MoneyInput from './money-input';

export default function StatementPaymentEditor({profile,movement,action='update',onBack,onChanged}){
 const system=movement.kind==='system_payment',deleting=action==='delete';
 const rpc=system?'solar_statement_system_payment':'solar_customer_payment_manage';
 const allowed=!movement.receiptRestricted&&['customer_payment','system_payment'].includes(movement.kind)
  &&canOpenPage(profile,system?'systemPayment':'customerPayment')&&(!deleting||canOpenPage(profile,'deletionRequests'));
 const id=movement.id,actor=profile?.id,attemptKey='statement-payment-'+id;
 const [context,setContext]=useState(null),[amount,setAmount]=useState(''),[notes,setNotes]=useState('');
 const [error,setError]=useState(''),[loading,setLoading]=useState(false),[busy,setBusy]=useState(false),[reload,setReload]=useState(0);
 const [pending,setPending]=useState(null),locked=useRef(false);
 useEffect(()=>{
  let active=true;
  if(!allowed||deleting)return;
  setError('');setLoading(true);setContext(null);
  const saved=readCashAttempt(actor,attemptKey);setPending(saved);
  (async()=>{
   try{
    const {data,error}=await supabase.rpc(rpc,{action:'get',payload:{id}});
    if(error)throw error;
    if(active){setContext(data);setAmount(String(saved?.payload?.amount??Math.abs(data.total)));setNotes(saved?.payload?.notes??data.notes??'');}
   }catch(e){if(active)setError(e.message||'تعذر فتح التسديد.');}
   finally{if(active)setLoading(false);}
  })();
  return()=>{active=false;};
 },[rpc,id,actor,attemptKey,allowed,deleting,reload]);
 const value=Number(amount),newTotal=context?.cash?value:-value;
 const remaining=Number(context?.balance)+Number(context?.total)-newTotal;
 const cashAfter=Number(context?.cashBalance)+(context?.cash?newTotal-Number(context?.total):0);
 const lowCash=context?.cash&&cashAfter<0&&(system?newTotal<Number(context.total):true);
 const overpayment=context?.cash&&newTotal>Number(context.total)&&remaining<0;
 const valid=context&&amount.trim()!==''&&Number.isFinite(value)&&value>0&&value<=1e12&&!lowCash&&!overpayment
  &&(!system||context.cash||notes.trim()!=='');
 async function submit(e){
  e.preventDefault();if(locked.current||!allowed||(!deleting&&!pending&&!valid))return;
  locked.current=true;setBusy(true);setError('');
  let saved=pending;
  try{
   if(deleting){
    const result=await requestReceiptDeletion(id,undefined,profile);
    if(result)await onChanged?.({...result,message:deletionResultMessage(result)});
    return;
   }
   if(!saved){
    saved={id:crypto.randomUUID(),payload:{id,expectedToken:context.token,amount:value,notes}};
    rememberCashAttempt(actor,attemptKey,saved);setPending(saved);
   }
   const {data,error}=await saveRequest(signal=>supabase.rpc(rpc,{action:'update',request_id:saved.id,payload:saved.payload}).abortSignal(signal));
   if(error)throw error;
   clearCashAttempt(actor,attemptKey,saved.id);setPending(null);
   await onChanged?.({...data,message:'تم تعديل التسديد وتحديث كشف الحساب.'});
  }catch(e){
   if(!deleting&&/^[0-9A-Z]{5}$/.test(e.code||'')){
    clearCashAttempt(actor,attemptKey,saved?.id);setPending(null);
   }
   if(e.code==='42501'){
    setContext(null);setAmount('');setNotes('');
    await onChanged?.({message:e.message||'لم يعد هذا التسديد متاحاً ضمن صلاحياتك.'});
   }
   setError(e.message||'تعذر تأكيد العملية. أعد المحاولة بنفس البيانات.');
  }finally{locked.current=false;setBusy(false);}
 }
 return <section className="accountWorkspace" aria-label={deleting?'حذف التسديد':'تعديل التسديد'}>
  <form className="receiptEditPanel" onSubmit={submit}>
   <header><div><h2>{deleting?'حذف التسديد':'تعديل التسديد'} #{receiptNumber(movement)}</h2>
    <p>{system?'تسديد منظومة':'تسديد جملة'}{context?.party&&' · '+context.party}</p></div>
    <button type="button" className="uiButton secondary" disabled={busy} onClick={onBack}>رجوع إلى الكشف</button></header>
   {!allowed?<p role="alert" className="accountAlert error">هذا الإجراء غير متاح ضمن صلاحياتك.</p>:deleting?
    <><p className="receiptDeleteNotice">قيمة الوصل <b>{money(Math.abs(Number(movement.total)))} د.ع</b>. يُراجع الأدمن الطلب قبل تصحيح الرصيد.</p>
     <button type="submit" className="uiButton wide receiptDeleteConfirm" disabled={busy}>{busy?'جاري الإرسال…':'إرسال طلب حذف التسديد'}</button></>:
    <>{loading&&<p role="status">جاري تحميل التسديد…</p>}
     {context&&<fieldset disabled={busy||!!pending}>
      <label>{context.cash?'مبلغ التسديد':'المبلغ المضاف على الحساب'} · د.ع<MoneyInput aria-label="مبلغ تعديل التسديد" value={amount} onChange={setAmount} required/></label>
      <label>ملاحظات الوصل<textarea aria-label="ملاحظات تعديل التسديد" value={notes} onChange={e=>setNotes(e.target.value)} maxLength={2000} required={system&&!context.cash}/></label>
      {amount&&<div className="receiptChangePreview"><div><span>رصيد العميل بعد التعديل</span><b>{money(remaining)} د.ع</b></div>
       {context.cash&&<div><span>قاصة {context.cashOwnerName} بعد التعديل</span><b>{money(cashAfter)} د.ع</b></div>}</div>}
      {lowCash&&<p className="accountAlert error">رصيد القاصة لا يكفي لعكس فرق التسديد.</p>}
      {overpayment&&<p className="accountAlert error">المبلغ أكبر من رصيد العميل المتاح للتسديد.</p>}
     </fieldset>}
     {(context||pending)&&<button type="submit" className="uiButton primary wide" disabled={busy||(!pending&&!valid)}>{busy?'جاري الحفظ…':pending?'إعادة تأكيد التعديل':'حفظ تعديل التسديد'}</button>}
    </>}
   {error&&<div className="accountAlert error" role="alert">{error}{!deleting&&!pending&&<button type="button" className="uiButton secondary" disabled={busy||loading} onClick={()=>setReload(n=>n+1)}>تحديث بيانات التسديد</button>}</div>}
  </form>
 </section>;
}
