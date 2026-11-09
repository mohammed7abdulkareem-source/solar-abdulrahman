'use client';
import {useCallback,useEffect,useRef,useState}from'react';
import {supabase}from'./supabase';
import {saveRequest}from'./save-request.mjs';
import MoneyInput from'./money-input';
import ReportActions from'./report-actions';
import {formatMoney as money,currencyUnit as unit}from'./money-format.mjs';
import {readCashAttempt,rememberCashAttempt,clearCashAttempt}from'./cash-record-attempt.mjs';
import {cashHandoverDocument}from'./cash-handover-document.mjs';
import {unlockNotificationSound,playNotificationSound}from'./notification-sound.mjs';
import {CASH_HANDOVER_BALANCE_MAX_AGE,cashHandoverBalanceKey,cashHandoverBalance,cashHandoverOwnerBalance,cashHandoverFullAmount}from'./cash-handover-balance.mjs';
import './cash-handover.css';
export default function CashHandover({profile,initialRecipient='',onClose,onSaved,a4}){
 const[owners,setOwners]=useState(null),[sender,setSender]=useState(profile.id),[recipient,setRecipient]=useState(initialRecipient===profile.id?'':initialRecipient),[currency,setCurrency]=useState('IQD'),[amount,setAmount]=useState(''),[note,setNote]=useState(''),[error,setError]=useState(''),[busy,setBusy]=useState(false),[retry,setRetry]=useState(0),[review,setReview]=useState(''),[receipt,setReceipt]=useState(null),[restored,setRestored]=useState(false);const pending=useRef(null),lock=useRef(false);
 const[balanceSnapshot,setBalanceSnapshot]=useState(null),[balanceStatus,setBalanceStatus]=useState('loading'),[balanceError,setBalanceError]=useState(''),[filling,setFilling]=useState(false);
 const balanceRequest=useRef(0),balanceController=useRef(null),fillPending=useRef(false),balanceKey=cashHandoverBalanceKey(profile.id,sender,currency),directoryReady=owners!==null;
 const activeBalanceKey=useRef(balanceKey);activeBalanceKey.current=balanceKey;
 useEffect(()=>{let live=true;setError('');supabase.rpc('solar_cash_record',{action:'get'}).then(({data,error})=>{if(!live)return;if(error){setError(error.message);return;}setOwners(data.owners||[]);const old=readCashAttempt(profile.id,null);pending.current=old;setRestored(!!old);if(old){setSender(old.payload.senderId);setRecipient(old.payload.recipientId);setAmount(String(old.payload.amount));setCurrency(old.payload.currency);setNote(old.payload.note);}}).catch(()=>{if(live)setError('تعذر تحميل قاصات المستخدمين.');});return()=>{live=false};},[profile.id,retry]);
 const refreshBalance=useCallback(async(fill=false)=>{
  if(lock.current||pending.current||(!fill&&fillPending.current))return;
  const generation=++balanceRequest.current;fillPending.current=fill;setFilling(fill);
  balanceController.current?.abort();
  const controller=new AbortController();balanceController.current=controller;
  setBalanceSnapshot(null);setBalanceStatus('loading');setBalanceError('');
  const timer=setTimeout(()=>controller.abort(),15000);
  try{
   if(navigator.onLine===false)throw new Error('الاتصال غير متاح. أعد تحديث رصيد القاصة عند عودة الاتصال.');
   const{data,error}=await supabase.rpc('solar_cash_record',{action:'get'}).abortSignal(controller.signal);
   if(generation!==balanceRequest.current||activeBalanceKey.current!==balanceKey)return;
   if(error)throw error;
   const next={key:balanceKey,readAt:Date.now(),owners:data?.owners};
   const available=cashHandoverBalance(next,balanceKey,sender,currency);
   if(available===null)throw new Error('رصيد القاصة المختارة غير متاح. حدّث الرصيد أو اختر قاصة أخرى.');
   setOwners(data.owners);setBalanceSnapshot(next);setBalanceStatus('ready');
   if(fill){const full=cashHandoverFullAmount(available);setReview('');if(full!==null)setAmount(full);else setBalanceError('لا يوجد مبلغ موجب متاح للتسليم بالكامل ضمن حدود العملية.');}
  }catch(e){if(generation===balanceRequest.current&&activeBalanceKey.current===balanceKey){setBalanceSnapshot(null);setBalanceStatus('error');setBalanceError(controller.signal.aborted?'تعذر تحديث الرصيد في الوقت الحالي. حاول مجددًا.':e.message||'تعذر تحديث رصيد القاصة. حاول مجددًا.');}}
  finally{clearTimeout(timer);if(generation===balanceRequest.current){fillPending.current=false;setFilling(false);}}
 },[balanceKey,sender,currency]);
 useEffect(()=>{
  if(!directoryReady||receipt)return;
  if(pending.current){setBalanceSnapshot(null);setBalanceStatus('uncertain');return;}
  const invalidate=()=>{++balanceRequest.current;balanceController.current?.abort();fillPending.current=false;setFilling(false);setBalanceSnapshot(null);setBalanceStatus('loading');};
  const refreshVisible=()=>{if(!document.hidden)void refreshBalance();};
  const visibility=()=>{if(document.hidden)invalidate();else refreshVisible();};
  const offline=()=>{invalidate();setBalanceStatus('error');setBalanceError('الاتصال غير متاح. أعد تحديث رصيد القاصة عند عودة الاتصال.');};
  void refreshBalance();
  const timer=setInterval(refreshVisible,CASH_HANDOVER_BALANCE_MAX_AGE);
  window.addEventListener('focus',refreshVisible);window.addEventListener('online',refreshVisible);window.addEventListener('offline',offline);document.addEventListener('visibilitychange',visibility);
  return()=>{clearInterval(timer);++balanceRequest.current;balanceController.current?.abort();fillPending.current=false;setFilling(false);window.removeEventListener('focus',refreshVisible);window.removeEventListener('online',refreshVisible);window.removeEventListener('offline',offline);document.removeEventListener('visibilitychange',visibility);};
 },[directoryReady,receipt,restored,refreshBalance]);
 const sourceBalance=cashHandoverBalance(balanceSnapshot,balanceKey,sender,currency),recipientBalance=sourceBalance===null?null:cashHandoverOwnerBalance(balanceSnapshot.owners,recipient,currency),fullAmount=cashHandoverFullAmount(sourceBalance);
 const from=owners?.find(o=>o.id===sender),to=owners?.find(o=>o.id===recipient),value=Number(amount),payload={senderId:sender,recipientId:recipient,currency,amount:value,note},signature=JSON.stringify(payload),valid=from&&to&&sender!==recipient&&sourceBalance!==null&&Number.isFinite(value)&&value>0&&value<=1e12&&note.trim()&&(currency!=='USD'||value<=sourceBalance),reviewed=review===signature;
 async function submit(e){
  e.preventDefault();if(lock.current||(!pending.current&&!valid))return;
  if(!pending.current&&cashHandoverBalance(balanceSnapshot,balanceKey,sender,currency)===null){void refreshBalance();return;}
  if(!pending.current&&!reviewed){setReview(signature);return;}
  lock.current=true;setBusy(true);setError('');++balanceRequest.current;balanceController.current?.abort();setBalanceSnapshot(null);setBalanceStatus('uncertain');void unlockNotificationSound();
  let confirmed=false;
  try{
   if(!pending.current){pending.current={id:crypto.randomUUID(),payload};rememberCashAttempt(profile.id,null,pending.current);}
   const attempt=pending.current,{data,error}=await saveRequest(signal=>supabase.rpc('solar_cash_record',{action:'transfer',request_id:attempt.id,payload:attempt.payload}).abortSignal(signal));
   if(error)throw error;
   clearCashAttempt(profile.id,null,attempt.id);pending.current=null;setRestored(false);setReceipt(data);confirmed=true;void playNotificationSound();
   if(onSaved)void Promise.resolve().then(()=>onSaved(data)).catch(()=>{});
  }catch(e){
   if(e.code&&/^[0-9A-Z]{5}$/.test(e.code)){clearCashAttempt(profile.id,null,pending.current?.id);pending.current=null;setRestored(false);}
   setError(e.message||'لم يتأكد رد التسليم؛ أعد تأكيد نفس الطلب ولن يتكرر المبلغ.');
  }finally{lock.current=false;setBusy(false);if(!confirmed&&!pending.current)void refreshBalance();}
 }

 return <section className="cashHandover" aria-label="تسليم مباشر لمستخدم"><header><div><h2>تسليم مبلغ لمستخدم</h2><p>من القاصة الدافعة إلى قاصة المستلم مباشرة.</p></div><button type="button" disabled={busy||!!pending.current} onClick={onClose}>رجوع إلى الصندوق</button></header>{error&&<p role="alert" className="workflowError">{error}</p>}{!owners&&!error&&<p role="status">جاري تحميل القاصات…</p>}{error&&!owners&&<button type="button" onClick={()=>setRetry(n=>n+1)}>إعادة التحميل</button>}
 {receipt?<section className="cashHandoverSaved"><p role="status">تم تسليم المبلغ وإضافته إلى قاصة المستلم.</p><h3>{receipt.senderName} ← {receipt.recipientName}</h3><strong>{money(receipt.amount,receipt.currency)} {unit(receipt.currency)}</strong><ReportActions enabled html={a4('وصل تسليم مبلغ لمستخدم',cashHandoverDocument(receipt),money(receipt.amount,receipt.currency)+' '+unit(receipt.currency))} filename={'تسليم-مبلغ-'+receipt.receiptNo}/><button type="button" onClick={onClose}>العودة إلى الصندوق</button></section>:owners&&<form onSubmit={submit}><fieldset disabled={busy||!!pending.current}><div className="cashCorrectionFields"><label>القاصة الدافعة<select aria-label="القاصة الدافعة للتسليم" value={sender} onChange={e=>{setSender(e.target.value);setReview('');}} required>{owners.map(o=><option key={o.id} value={o.id}>{o.name}</option>)}</select></label><label>المستخدم المستلم<select aria-label="المستخدم المستلم للتسليم" value={recipient} onChange={e=>setRecipient(e.target.value)} required><option value="">اختر المستخدم</option>{owners.filter(o=>o.id!==sender).map(o=><option key={o.id} value={o.id}>{o.name}</option>)}</select></label><label>عملة التسليم<select aria-label="عملة التسليم المباشر" value={currency} onChange={e=>{setCurrency(e.target.value);setReview('');}}><option value="IQD">دينار عراقي · IQD</option><option value="USD">دولار · USD</option></select></label><label>المبلغ المسلّم<MoneyInput aria-label="مبلغ التسليم المباشر" disabled={filling} currency={currency} value={amount} onChange={setAmount} required/></label></div>
 <section className="cashHandoverBalance" aria-label="رصيد القاصة الدافعة" aria-busy={balanceStatus==='loading'}>
  <div className="cashHandoverBalanceHeading"><div><span>الرصيد الحالي للقاصة الدافعة</span><b>{from?.name||'القاصة المختارة'} · {currency==='USD'?'الدولار الأمريكي':'الدينار العراقي'} · {currency}</b></div>
   {sourceBalance!==null&&<strong data-testid="cash-handover-source-balance" data-currency={currency} className={'cashHandoverBalanceAmount'+(sourceBalance<0?' negative':'')}><bdi>{money(sourceBalance,currency)} {unit(currency)}</bdi></strong>}
  </div>
  {sourceBalance===null&&<p role="status">{pending.current||balanceStatus==='uncertain'?'الرصيد غير مؤكد حتى تأكيد طلب التسليم السابق.':balanceStatus==='error'?'رصيد القاصة غير متاح حاليًا.':'جاري تحديث رصيد القاصة…'}</p>}
  <div className="cashHandoverBalanceActions"><button type="button" className="cashHandoverFill" disabled={busy||!!pending.current||balanceStatus!=='ready'||fullAmount===null} onClick={()=>void refreshBalance(true)}>كامل مبلغ القاصة</button><button type="button" disabled={busy||!!pending.current||balanceStatus==='loading'} onClick={()=>void refreshBalance()}>تحديث رصيد القاصة</button></div>
  {balanceError&&<p role="alert" className="cashHandoverBalanceError">{balanceError}</p>}
  {sourceBalance!==null&&<p>{sourceBalance<=0?'لا يوجد رصيد موجب لتعبئة كامل مبلغ القاصة.':'زر كامل مبلغ القاصة يحدّث الرصيد ثم يعبّئ المبلغ بالعملة المختارة.'}</p>}
 </section>
 <label>بيان التسليم<textarea aria-label="بيان التسليم المباشر" value={note} maxLength={2000} onChange={e=>setNote(e.target.value)} required/></label></fieldset>
 {!restored&&from&&to&&sourceBalance!==null&&recipientBalance!==null&&value>0&&<div className="cashCorrectionPreview" aria-label="أرصدة القاصتين بعد التسليم"><div><span>يبقى في قاصة {from.name}</span><b>{money(sourceBalance-value,currency)} {unit(currency)}</b></div><div><span>قاصة {to.name} بعد الاستلام</span><b>{money(recipientBalance+value,currency)} {unit(currency)}</b></div></div>}{restored&&<p className="accountAlert">تأكيد محاولة التسليم السابقة؛ المبلغ لن يُسجّل مرتين.</p>}<button type="submit" className="primary" disabled={busy||(!pending.current&&!valid)}>{busy?'جاري تسجيل التسليم…':pending.current?'تأكيد طلب التسليم السابق':reviewed?'تأكيد التسليم وإضافة المبلغ لقاصته':'معاينة التسليم'}</button></form>}</section>;
}
