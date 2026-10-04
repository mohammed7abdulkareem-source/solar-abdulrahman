'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
const fmt=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2});
const raw=v=>v.replace(/,/g,'');
const display=v=>v===''?'':Number.isFinite(Number(v))?fmt(v):v;
const statuses={pending:'بانتظار الموافقة',accepted:'تم الاستلام',rejected:'مرفوض — أعيد للمرسل',cancelled:'ملغي — أعيد للمرسل'};
const errorText=e=>e.code==='P0002'?'رصيد قاصتك لا يكفي. حدّث الرصيد وراجع المبلغ والمصاريف.':e.code==='42501'?'الصلاحية غير متاحة أو مسؤول المالية غير فعّال.':e.code==='40001'?'تغيّرت حالة الطلب. حدّث القائمة قبل المحاولة.':'تعذر تأكيد العملية. حدّث القائمة قبل إعادة المحاولة؛ الطلب محفوظ برقم يمنع تكرار الخصم.';

export default function CashTransfers({profile,onChanged}){
 const [data,setData]=useState(null),[error,setError]=useState(''),[message,setMessage]=useState(''),[busy,setBusy]=useState(false),[loading,setLoading]=useState(true);
 const [recipient,setRecipient]=useState(''),[amount,setAmount]=useState(''),[expense,setExpense]=useState(''),[expenseNote,setExpenseNote]=useState(''),[note,setNote]=useState(''),[filter,setFilter]=useState('pending');
 const request=useRef(null),guard=useRef(false);
 const refresh=useCallback(async()=>{const r=await supabase.rpc('solar_cash_transfer_overview');if(r.error)throw r.error;setData(r.data);return r.data},[]);
 useEffect(()=>{let alive=true;supabase.rpc('solar_cash_transfer_overview').then(r=>{if(!alive)return;if(r.error)setError(errorText(r.error));else setData(r.data);setLoading(false)});return()=>{alive=false}},[]);
 const amountNumber=Number(amount||0),expenseNumber=Number(expense||0),balance=Number(data?.balance||0),remaining=balance-amountNumber-expenseNumber;
 async function submit(e){
  e.preventDefault();if(guard.current)return;
  if(!recipient||!Number.isFinite(amountNumber)||amountNumber<=0||!Number.isFinite(expenseNumber)||expenseNumber<0)return setError('حدد المستلم واكتب مبلغاً صحيحاً. المصاريف اختيارية.');
  if(remaining<0)return setError('المبلغ والمصاريف أكبر من رصيد قاصتك.');
  if(!confirm('إرسال '+fmt(amountNumber)+' د.ع وتسجيل مصروف '+fmt(expenseNumber)+' د.ع؟ يبقى التحويل بانتظار موافقة المستلم.'))return;
  const payload={recipient,send_amount:amountNumber,expense_amount:expenseNumber,expense_note:expenseNote.trim(),note:note.trim()},signature=JSON.stringify(payload);
  if(!request.current||request.current.signature!==signature)request.current={id:crypto.randomUUID(),signature};
  guard.current=true;setBusy(true);setError('');setMessage('');let saved=false;
  try{const r=await supabase.rpc('solar_cash_transfer_send',{request_id:request.current.id,...payload});if(r.error)throw r.error;saved=true;request.current=null;setAmount('');setExpense('');setExpenseNote('');setNote('');setMessage('تم إرسال المبلغ؛ بانتظار موافقة مسؤول المالية.');await refresh();await onChanged?.()}
  catch(e){setError(saved?'تم حفظ الطلب، لكن تعذر تحديث العرض. اضغط تحديث.':errorText(e))}finally{guard.current=false;setBusy(false)}
 }
 async function decide(row,decision){
  if(guard.current||!confirm(decision==='accepted'?'تأكيد استلام '+fmt(row.amount)+' د.ع فعلياً وإضافته لقاصتك؟':'إرجاع مبلغ التحويل للمرسل؟ المصروف المسجل يبقى مصروفاً.'))return;
  guard.current=true;setBusy(true);setError('');setMessage('');
  try{const r=await supabase.rpc('solar_cash_transfer_decide',{request_id:row.id,decision});if(r.error)throw r.error;setMessage(decision==='accepted'?'تمت الموافقة وإضافة المبلغ لقاصتك.':'أعيد مبلغ التحويل لقاصة المرسل.');await refresh();await onChanged?.()}
  catch(e){setError(errorText(e));await refresh().catch(()=>{})}finally{guard.current=false;setBusy(false)}
 }
 const rows=(data?.rows||[]).filter(r=>filter==='all'||(filter==='incoming'?r.recipient_id===profile.id:filter==='outgoing'?r.sender_id===profile.id:r.status==='pending'));
 const pending=(data?.rows||[]).filter(r=>r.status==='pending'&&r.recipient_id===profile.id).length;
 return <div className="cashTransfers"><div className="cashHero"><small>رصيد قاصتي المتاح للتسليم</small><b>{loading?'…':fmt(balance)+' د.ع'}</b><small>طلبات واردة بانتظار موافقتي: {pending}</small></div>
  <button disabled={busy||loading} onClick={async()=>{setLoading(true);setError('');try{await refresh();await onChanged?.()}catch(e){setError(errorText(e))}finally{setLoading(false)}}}>تحديث الرصيد والطلبات</button>
  {error&&<p className="workflowError" role="alert">{error}</p>}{message&&<p className="workflowSuccess" role="status">{message}</p>}
  {data?.canSend&&<form className="card form" onSubmit={submit}><h3>إرسال أموال القاصة</h3><fieldset disabled={busy}><label>مسؤول استلام القاصة<select required value={recipient} onChange={e=>setRecipient(e.target.value)}><option value="">اختر مسؤول المالية</option>{data.managers.map(u=><option key={u.id} value={u.id}>{u.name}</option>)}</select></label>{!data.managers.length&&<p>لا يوجد مستلم فعّال. اطلب من الأدمن منح صلاحية مدير المالية للشخص المسؤول.</p>}
   <label>مصروف قبل التسليم — اختياري<input inputMode="decimal" value={display(expense)} onChange={e=>setExpense(raw(e.target.value))} placeholder="0"/></label><input maxLength={1000} value={expenseNote} onChange={e=>setExpenseNote(e.target.value)} placeholder="بيان المصروف (اختياري)"/>
   <label>المبلغ المرسل<input inputMode="decimal" required value={display(amount)} onChange={e=>setAmount(raw(e.target.value))} placeholder="المبلغ بالدينار"/></label><button type="button" onClick={()=>setAmount(String(Math.max(0,balance-(Number.isFinite(expenseNumber)?expenseNumber:0))))}>إرسال كامل المتبقي بعد المصاريف</button><input maxLength={2000} value={note} onChange={e=>setNote(e.target.value)} placeholder="ملاحظات التسليم (اختياري)"/>
   <div className="paymentCalc"><div><span>يبقى في قاصتي بعد الإرسال</span><b>{fmt(remaining)} د.ع</b></div></div><small>المبلغ يخرج من قاصتك ويبقى قيد التسليم. لا يدخل قاصة المستلم إلا بعد موافقته. عند الرفض أو الإلغاء يرجع مبلغ التحويل فقط؛ المصروف يبقى مسجلاً.</small><button className="primaryWide" disabled={loading||!data.managers.length}>{busy?'جاري الحفظ…':'تأكيد إرسال الأموال'}</button></fieldset></form>}
  <div className="statusTabs">{[['pending','المعلقة'],['incoming','الواردة إليّ'],['outgoing','المرسلة مني'],['all','الكل']].map(([key,label])=><button key={key} aria-pressed={filter===key} onClick={()=>setFilter(key)}>{label}</button>)}</div>
  <small>كل الطلبات المعلقة وآخر 100 طلب منتهٍ ضمن صلاحيتك</small>
  {!loading&&!rows.length&&<div className="empty">لا توجد طلبات ضمن هذا الاختيار</div>}
  {rows.map(r=><article className="transferCard" key={r.id}><header><b>{fmt(r.amount)} د.ع</b><span className={'workflowStatus '+r.status}>{statuses[r.status]}</span></header><p>من: {r.senderName} ← إلى: {r.recipientName}</p><small>{new Date(r.created_at).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'})} • #{r.id.slice(0,8)}</small>{Number(r.expense)>0&&<p>مصروف قبل التسليم: {fmt(r.expense)} د.ع {r.expense_note&&'— '+r.expense_note}</p>}{r.notes&&<p>{r.notes}</p>}{r.decided_at&&<small>تاريخ القرار: {new Date(r.decided_at).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'})}</small>}{r.status==='pending'&&<div className="receiptCopies">{r.recipient_id===profile.id&&data.canReceive&&<><button disabled={busy} onClick={()=>decide(r,'accepted')}>موافقة واستلام الأموال</button><button disabled={busy} onClick={()=>decide(r,'rejected')}>رفض وإرجاع المبلغ</button></>}{r.sender_id===profile.id&&<button disabled={busy} onClick={()=>decide(r,'cancelled')}>إلغاء طلب التسليم</button>}</div>}</article>)}
 </div>;
}
