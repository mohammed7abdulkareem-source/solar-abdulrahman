'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import MoneyInput from './money-input';
import {canUseCash} from './cash-permissions.mjs';
import AppIcon from './app-icons';
import {supabase} from './supabase';
import {readCashAttempt,rememberCashAttempt,clearCashAttempt} from './cash-record-attempt.mjs';
const fmt=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2});
const statuses={pending:'بانتظار الموافقة',accepted:'تم الاستلام',rejected:'مرفوض — أعيد للمرسل',cancelled:'ملغي — أعيد للمرسل'};
const errorText=e=>e.code==='P0002'?'رصيد قاصتك لا يكفي. حدّث الرصيد وراجع المبلغ والمصاريف.':e.code==='42501'?'الصلاحية غير متاحة أو مسؤول المالية غير فعّال.':['40001','PT409'].includes(e.code)?'تغيّرت حالة الطلب. حدّث القائمة قبل المحاولة.':'تعذر تأكيد العملية. حدّث القائمة قبل إعادة المحاولة؛ الطلب محفوظ برقم يمنع تكرار الخصم.';

export default function CashTransfers({profile,onChanged,selectedTransfer=''}){
 const [data,setData]=useState(null),[error,setError]=useState(''),[message,setMessage]=useState(''),[busy,setBusy]=useState(false),[loading,setLoading]=useState(true);
 const [recipient,setRecipient]=useState(''),[amount,setAmount]=useState(''),[expense,setExpense]=useState(''),[expenseNote,setExpenseNote]=useState(''),[note,setNote]=useState(''),[filter,setFilter]=useState('pending'),[view,setView]=useState('send'),[expenseOpen,setExpenseOpen]=useState(false);
 const request=useRef(null),guard=useRef(false);
 useEffect(()=>{const saved=readCashAttempt(profile.id,'transfer-send');if(saved){request.current={...saved,signature:JSON.stringify(saved.payload)};const b=saved.payload;setRecipient(b.recipient);setAmount(String(b.send_amount));setExpense(String(b.expense_amount));setExpenseNote(b.expense_note||'');setNote(b.note||'');setExpenseOpen(Number(b.expense_amount)>0);setMessage('توجد محاولة تسليم سابقة؛ أكّد نفس الطلب دون تكرار الخصم.');}},[profile.id]);
 const refresh=useCallback(async()=>{const r=await supabase.rpc('solar_cash_transfer_overview');if(r.error)throw r.error;setData(r.data);return r.data},[]);
 useEffect(()=>{const update=()=>refresh().catch(()=>{});window.addEventListener('solar-notification',update);window.addEventListener('focus',update);return()=>{window.removeEventListener('solar-notification',update);window.removeEventListener('focus',update)}},[refresh]);
 useEffect(()=>{if(selectedTransfer){setFilter('all');setView('receive');}},[selectedTransfer]);
 useEffect(()=>{if(selectedTransfer&&data)document.getElementById('transfer-'+selectedTransfer)?.scrollIntoView({behavior:'smooth',block:'center'})},[selectedTransfer,data]);
 useEffect(()=>{let alive=true;supabase.rpc('solar_cash_transfer_overview').then(r=>{if(!alive)return;if(r.error)setError('تعذر تحميل القاصة. اضغط تحديث لإعادة المحاولة.');else setData(r.data);setLoading(false)});return()=>{alive=false}},[]);
 const amountNumber=Number(amount||0),expenseNumber=Number(expense||0),balance=Number(data?.balance||0),remaining=balance-amountNumber-expenseNumber;
 async function submit(e){
  e.preventDefault();if(guard.current)return;
  if(!request.current){if(!recipient||!Number.isFinite(amountNumber)||amountNumber<=0||!Number.isFinite(expenseNumber)||expenseNumber<0)return setError('حدد المستلم واكتب مبلغاً صحيحاً. المصاريف اختيارية.');
  if(remaining<0)return setError('المبلغ والمصاريف أكبر من رصيد قاصتك.');}
  if(!confirm('إرسال '+fmt(amountNumber)+' د.ع وتسجيل مصروف '+fmt(expenseNumber)+' د.ع؟ يبقى التحويل بانتظار موافقة المستلم.'))return;
  const payload={recipient,send_amount:amountNumber,expense_amount:expenseNumber,expense_note:expenseNote.trim(),note:note.trim()},signature=JSON.stringify(payload);
  if(request.current&&request.current.signature!==signature)return setError('أكّد طلب التسليم السابق بنفس بياناته.');
  if(!request.current){request.current={id:crypto.randomUUID(),signature,payload};rememberCashAttempt(profile.id,'transfer-send',request.current);}
  guard.current=true;setBusy(true);setError('');setMessage('');let saved=false;
  try{const r=await supabase.rpc('solar_cash_transfer_send',{request_id:request.current.id,...payload});if(r.error)throw r.error;saved=true;clearCashAttempt(profile.id,'transfer-send',request.current.id);request.current=null;setAmount('');setExpense('');setExpenseNote('');setExpenseOpen(false);setNote('');setMessage('تم إرسال المبلغ؛ بانتظار موافقة مسؤول المالية.');await refresh();await onChanged?.()}
  catch(e){if(e.code){clearCashAttempt(profile.id,'transfer-send',request.current?.id);request.current=null;}setError(saved?'تم حفظ الطلب، لكن تعذر تحديث العرض. اضغط تحديث.':errorText(e))}finally{guard.current=false;setBusy(false)}
 }
 async function decide(row,decision){
  if(guard.current||!confirm(decision==='accepted'?'تأكيد استلام '+fmt(row.amount)+' د.ع فعلياً وإضافته لقاصتك؟':'إرجاع مبلغ التحويل للمرسل؟ المصروف المسجل يبقى مصروفاً.'))return;
  guard.current=true;setBusy(true);setError('');setMessage('');
  try{const r=await supabase.rpc('solar_cash_transfer_decide',{request_id:row.id,decision});if(r.error)throw r.error;setMessage(decision==='accepted'?'تمت الموافقة وإضافة المبلغ لقاصتك.':'أعيد مبلغ التحويل لقاصة المرسل.');await refresh();await onChanged?.()}
  catch(e){setError(errorText(e));await refresh().catch(()=>{})}finally{guard.current=false;setBusy(false)}
 }
 const rows=(data?.rows||[]).filter(r=>filter==='all'||(filter==='incoming'?r.recipient_id===profile.id:filter==='outgoing'?r.sender_id===profile.id:r.status==='pending'));
 const pending=(data?.rows||[]).filter(r=>r.status==='pending'&&r.recipient_id===profile.id).length;
 return <div className="cashTransfers clarityTransfers"><div className="transferOverview"><div><span>المتاح في قاصتي · دينار</span><b>{loading?'…':data?fmt(balance):'—'} <small>د.ع</small></b></div><button type="button" disabled={busy||loading} onClick={async()=>{setLoading(true);setError('');try{await refresh();await onChanged?.()}catch(e){setError(errorText(e))}finally{setLoading(false)}}}><AppIcon name="refresh" size={18}/>تحديث</button></div>
  <div className="transferViewTabs">{data?.canSend&&<button type="button" aria-pressed={view==='send'} onClick={()=>setView('send')}><AppIcon name="exchange" size={20}/>تسليم مبلغ</button>}<button type="button" aria-pressed={view==='receive'||!data?.canSend} onClick={()=>{setView('receive');setFilter('incoming');}}><AppIcon name="wallet" size={20}/>استلام الأموال <b>{pending}</b></button></div>
  {error&&<p className="workflowError" role="alert">{error}</p>}{message&&<p className="workflowSuccess" role="status">{message}</p>}
  {data?.canSend&&view==='send'&&<form className="card form transferSendForm" onSubmit={submit}><h3>تسليم من قاصتي</h3><fieldset disabled={busy||!!request.current}><label>١. المستلم<select aria-label="مستلم القاصة" required value={recipient} onChange={e=>setRecipient(e.target.value)}><option value="">اختر مستلم المبلغ</option>{data.managers.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select></label>{!data.managers.length&&<p>لا يوجد مستلم فعّال بصلاحية استلام القاصة.</p>}
   <label>٢. المبلغ بالدينار<MoneyInput aria-label="مبلغ تسليم القاصة" required value={amount} onChange={setAmount} placeholder="مثال: 500,000"/></label><button type="button" className="transferFullAmount" onClick={()=>setAmount(String(Math.max(0,balance-(Number.isFinite(expenseNumber)?expenseNumber:0))))}>تسليم كامل الرصيد المتاح · {fmt(Math.max(0,balance-(Number.isFinite(expenseNumber)?expenseNumber:0)))} د.ع</button>
   {canUseCash(profile,'cashExpense')&&<button type="button" className="transferExpenseButton" aria-expanded={expenseOpen} aria-controls="handover-expense" onClick={()=>setExpenseOpen(true)}><AppIcon name="add" size={18}/>تسجيل مصروف قبل التسليم <small>اختياري</small></button>}
   {expenseOpen&&canUseCash(profile,'cashExpense')&&<div id="handover-expense" className="transferExpensePanel"><label>مبلغ المصروف · د.ع<MoneyInput aria-label="مصروف قبل التسليم" value={expense} onChange={setExpense} placeholder="0"/></label><label>بيان المصروف<input aria-label="بيان مصروف التسليم" maxLength={1000} value={expenseNote} onChange={e=>setExpenseNote(e.target.value)} placeholder="مثال: أجور نقل"/></label><button type="button" onClick={()=>{setExpense('');setExpenseNote('');setExpenseOpen(false);}}>إلغاء المصروف</button></div>}
   <label>ملاحظة · اختياري<input aria-label="ملاحظة التسليم" maxLength={2000} value={note} onChange={e=>setNote(e.target.value)} placeholder="ملاحظات التسليم"/></label>
   <div className="transferCalculation"><span>المبلغ المسلّم <b>{fmt(amountNumber)} د.ع</b></span>{expenseNumber>0&&<span>المصروف <b>{fmt(expenseNumber)} د.ع</b></span>}<span>يبقى في قاصتي <b>{fmt(remaining)} د.ع</b></span></div><p className="transferHelp">يُخصم المبلغ عند الإرسال، ويدخل قاصة المستلم بعد تأكيد استلامه. عند الرفض يرجع مبلغ التسليم؛ المصروف يبقى مسجّلًا.</p><button className="primaryWide" disabled={loading||!data.managers.length}>{busy?'جاري الحفظ…':'تأكيد تسليم المبلغ'}</button></fieldset>{request.current&&<button type="submit" className="primaryWide" disabled={busy||loading}>تأكيد طلب التسليم السابق</button>}</form>}
  <section className="transferRequests"><h2>{view==='receive'?'طلبات الاستلام':'متابعة التحويلات'}</h2>
  <div className="statusTabs">{[['pending','المعلقة'],['incoming','الواردة إليّ'],['outgoing','المرسلة مني'],['all','الكل']].map(([key,label])=><button key={key} aria-pressed={filter===key} onClick={()=>setFilter(key)}>{label}</button>)}</div>
  <small>كل الطلبات المعلقة وآخر 100 طلب منتهٍ ضمن صلاحيتك</small>
  {!loading&&!rows.length&&<div className="empty">لا توجد طلبات ضمن هذا الاختيار</div>}
  {rows.map(r=><article id={'transfer-'+r.id} className={'transferCard'+(selectedTransfer===r.id?' selectedTransfer':'')} key={r.id}><header><b>{fmt(r.amount)} د.ع</b><span className={'workflowStatus '+r.status}>{statuses[r.status]}</span></header><p>من: {r.senderName} ← إلى: {r.recipientName}</p><small>{new Date(r.created_at).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'})} • #{r.id.slice(0,8)}</small>{Number(r.expense)>0&&<p>مصروف قبل التسليم: {fmt(r.expense)} د.ع {r.expense_note&&'— '+r.expense_note}</p>}{r.notes&&<p>{r.notes}</p>}{r.decided_at&&<small>تاريخ القرار: {new Date(r.decided_at).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'})}</small>}{r.status==='pending'&&<div className="receiptCopies">{r.recipient_id===profile.id&&data.canReceive&&<><button className="transferAccept" disabled={busy} onClick={()=>decide(r,'accepted')}>تأكيد الاستلام</button><button className="transferReject" disabled={busy} onClick={()=>decide(r,'rejected')}>رفض وإرجاع المبلغ</button></>}{r.sender_id===profile.id&&<button disabled={busy} onClick={()=>decide(r,'cancelled')}>إلغاء طلب التسليم</button>}</div>}</article>)}
 </section></div>;
}
