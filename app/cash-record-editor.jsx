'use client';
import {useEffect,useRef,useState}from'react';
import {supabase}from'./supabase';
import {saveRequest}from'./save-request.mjs';
import MoneyInput from'./money-input';
import {formatMoney as money,currencyUnit as unit}from'./money-format.mjs';
import {readCashAttempt,rememberCashAttempt,clearCashAttempt}from'./cash-record-attempt.mjs';
import {unlockNotificationSound,playNotificationSound}from'./notification-sound.mjs';

export default function CashRecordEditor({movementId,profile,onSaved,onCancel}){
 const[ctx,setCtx]=useState(null),[amount,setAmount]=useState(''),[note,setNote]=useState(''),[rate,setRate]=useState('1'),[supplierId,setSupplierId]=useState(''),[error,setError]=useState(''),[busy,setBusy]=useState(false),[retry,setRetry]=useState(0),[review,setReview]=useState(''),[restored,setRestored]=useState(false);
 const pending=useRef(null),lock=useRef(false),actor=profile?.id;
 useEffect(()=>{let live=true;setCtx(null);setError('');supabase.rpc('solar_cash_record',{action:'get',movement_id:movementId}).then(({data,error})=>{
  if(!live)return;if(error){setError(error.message);return;}if(!data.canEdit){setError('هذه الحركة تحتاج التعديل من قسمها المختص أو من الإدارة.');return;}
  const saved=readCashAttempt(actor,movementId);pending.current=saved;setRestored(!!saved);setCtx(data);setAmount(String(saved?.payload?.amount??data.amount));setNote(saved?.payload?.note??data.note??'');setRate(String(saved?.payload?.rate??data.rate??1));setSupplierId(String(saved?.payload?.supplierId??data.supplierId??''));setReview('');
 }).catch(()=>{if(live)setError('تعذر تحميل بيانات التعديل.');});return()=>{live=false};},[movementId,actor,retry]);
 const settlement=ctx?.type==='settlement',transfer=ctx?.type==='transfer',value=Number(amount),remaining=settlement?Number(ctx.profit)-value:0,supplier=ctx?.suppliers?.find(s=>String(s.id)===supplierId);
 const supplierRate=supplier&&String(ctx.supplierId)===supplierId&&ctx.supplierCurrency===supplier.currency?Number(ctx.supplierRate||1):Number(supplier?.rate||1),supplierAmount=remaining>0?(supplier?.currency==='USD'?Math.round(remaining/supplierRate*100)/100:remaining):0;
 const payload={amount:value,note,rate:Number(rate),expectedToken:ctx?.token,...(settlement&&remaining>0?{supplierId:Number(supplierId),supplierToken:supplier?.token}:{})},signature=JSON.stringify(payload),reviewed=signature===review;
 const out=ctx&&['expense','capital_withdraw','distribution'].includes(ctx.mode),balance=ctx?.currency==='USD'?Number(ctx?.usdBalance):Number(ctx?.cashBalance),after=balance+(out?-1:1)*(value-Number(ctx?.amount));
 const valid=ctx&&Number.isFinite(value)&&value>0&&value<=1e12&&note.trim()&&(!settlement||(Number.isInteger(value)&&value<=Number(ctx.profit)&&(remaining===0||!!supplier)));
 async function save(e){e.preventDefault();if(lock.current||!ctx)return;if(!pending.current&&!valid){setError('راجع المبلغ والبيان والمورد قبل الحفظ.');return;}if(!pending.current&&!reviewed){setReview(signature);setError('');return;}
  lock.current=true;setBusy(true);setError('');void unlockNotificationSound();try{
   if(!pending.current){pending.current={id:crypto.randomUUID(),movementId:ctx.movementId||movementId,payload};rememberCashAttempt(actor,movementId,pending.current);}
   const attempt=pending.current,{data,error}=await saveRequest(signal=>supabase.rpc('solar_cash_record',{action:'update',movement_id:attempt.movementId,request_id:attempt.id,payload:attempt.payload}).abortSignal(signal));if(error)throw error;
   clearCashAttempt(actor,movementId,attempt.id);pending.current=null;setRestored(false);void playNotificationSound();onSaved?.(data);
  }catch(e){if(e.code&&/^[0-9A-Z]{5}$/.test(e.code)){clearCashAttempt(actor,movementId,pending.current?.id);pending.current=null;setRestored(false);}setError(e.message||'لم يتأكد الحفظ؛ أعد تأكيد نفس الطلب ولن يتكرر التعديل.');}finally{lock.current=false;setBusy(false);}
 }
 return <section className="cashRecordEditor" aria-label={settlement?'تعديل تسوية الأرباح المعتمدة':'تعديل حركة القاصة'}><header><h3>{settlement?'تعديل تسوية الأرباح المعتمدة':transfer?'تعديل المبلغ المسلّم':'تعديل حركة القاصة'}</h3><button type="button" disabled={busy||!!pending.current} onClick={onCancel}>إلغاء التعديل</button></header>
 {!ctx&&!error&&<p role="status">جاري تحميل القيد والأرصدة…</p>}{ctx&&<form onSubmit={save}><fieldset disabled={busy||!!pending.current}><p>{settlement?'صاحب التسوية: ':transfer?'القاصة الدافعة: ':'القاصة: '}<b>{ctx.ownerName||ctx.senderName}</b>{transfer&&<> ← <b>{ctx.recipientName}</b></>}</p>
 {settlement&&<p>ربح الفترة المعتمد: <b>{money(ctx.profit)} د.ع</b></p>}<div className="cashCorrectionFields"><label>{settlement?'حصة المستخدم بعد التعديل':'المبلغ الصحيح'} · {unit(ctx.currency)}<MoneyInput aria-label="مبلغ تعديل القاصة" currency={ctx.currency} value={amount} onChange={setAmount} required/></label>{ctx.currency==='USD'&&!transfer&&<label>الصرف المثبت<MoneyInput aria-label="صرف تعديل القاصة" value={rate} onChange={setRate} disabled={!ctx.canRate}/></label>}</div>
 {settlement&&remaining>0&&<label>المورد لبقية الأرباح<select aria-label="مورد تعديل التسوية" value={supplierId} onChange={e=>setSupplierId(e.target.value)} required><option value="">اختر المورد</option>{ctx.suppliers.map(s=><option key={s.id} value={s.id}>{s.name} · {s.currency}</option>)}</select></label>}
 <label>بيان التعديل<textarea aria-label="بيان تعديل القاصة" value={note} onChange={e=>setNote(e.target.value)} maxLength={2000} required/></label></fieldset>
 {!restored&&valid&&<div className="cashCorrectionPreview" aria-label="معاينة أثر التعديل">{settlement?<><div><span>رصيد قاصة المستخدم الآن</span><b>{money(ctx.cashBalance)} د.ع</b></div><div><span>رصيدها بعد تصحيح الحصة</span><b>{money(Number(ctx.cashBalance)+Number(ctx.amount)-value)} د.ع</b></div><div><span>بقية الربح للمورد</span><b>{money(remaining)} د.ع</b></div>{supplier&&remaining>0&&<div><span>الإضافة المصححة إلى {supplier.name}</span><b>{money(supplierAmount,supplier.currency)} {unit(supplier.currency)}</b></div>}<small>يبقى ربح الفترة المعتمد كما هو، ويُصحّح توزيع الحصة وبقية المورد بنفس الحفظ.</small></>:transfer?<><div><span>رصيد القاصة الدافعة بعد التعديل</span><b>{money(Number(ctx.senderBalance)+Number(ctx.amount)-value,ctx.currency)} {unit(ctx.currency)}</b></div><div><span>رصيد قاصة المستلم بعد التعديل</span><b>{money(Number(ctx.recipientBalance)-Number(ctx.amount)+value,ctx.currency)} {unit(ctx.currency)}</b></div></>:<><div><span>الرصيد الحالي</span><b>{money(balance,ctx.currency)} {unit(ctx.currency)}</b></div><div><span>الرصيد بعد التعديل</span><b>{money(after,ctx.currency)} {unit(ctx.currency)}</b></div></>}</div>}
 {restored&&<p className="accountAlert">تأكيد محاولة التعديل السابقة؛ لن يُسجّل فرق المبلغ مرتين.</p>}<div className="cashCorrectionActions">{reviewed&&!pending.current&&<button type="button" disabled={busy} onClick={()=>setReview('')}>رجوع للمراجعة</button>}<button type="submit" className="primary" disabled={busy||(!pending.current&&!valid)}>{busy?'جاري الحفظ…':pending.current?'تأكيد طلب التعديل السابق':reviewed?'حفظ التعديل وتحديث الأرصدة':'معاينة التعديل'}</button></div></form>}
 {error&&<p role="alert" className="workflowError">{error}</p>}{error&&!pending.current&&<button type="button" disabled={busy} onClick={()=>setRetry(n=>n+1)}>تحميل القيم الحالية</button>}</section>;
}
