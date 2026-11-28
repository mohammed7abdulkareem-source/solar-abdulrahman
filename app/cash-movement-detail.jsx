'use client';
import PhoneActions from './phone-actions';
import CashRecordEditor from './cash-record-editor';
import {useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import AppIcon from './app-icons';
import {cashKind} from './cash-utils.mjs';
import {cashDate,cashMovementBody,paymentMode,transferStatus} from './cash-movement-utils.mjs';
import {formatMoney as money,currencyUnit as unit} from './money-format.mjs';
import ReportActions from './report-actions';
import {CashFigure} from './cash-ledger-rows';
import {cashTransferFacts} from './cash-ledger-display.mjs';
import {canAccessSupplier,canRequestReceiptDeletion} from './access-utils.mjs';
import {requestReceiptDeletion} from './receipt-deletion.mjs';

export default function CashMovementDetail({movementId,profile,a4,onClose,onChanged}){
 const panel=useRef(null),deleteLock=useRef(false),[editing,setEditing]=useState(false),[deleting,setDeleting]=useState(false),[deleteError,setDeleteError]=useState(''),[deleteMessage,setDeleteMessage]=useState('');
 useEffect(()=>{panel.current?.scrollIntoView({block:'start',behavior:'smooth'});},[]);
 const [data,setData]=useState(null),[error,setError]=useState(''),[retry,setRetry]=useState(0);
 useEffect(()=>{let live=true;const controller=new AbortController();setData(null);setError('');
  const timer=setTimeout(()=>controller.abort(),10000);
  supabase.rpc('solar_cash_movement_detail',{movement_id:movementId}).abortSignal(controller.signal).then(({data,error})=>{if(error)throw error;if(['supplier_payment','purchase'].includes(data?.kind)&&!canAccessSupplier(profile,data))throw new Error('هذه الحركة غير متاحة.');if(live){setData(data);if(data.deletion?.pendingRequestId)setDeleteError('');}}).catch(e=>{if(live)setError(e.code?e.message:'تعذر تحميل تفاصيل الحركة. أعد المحاولة.');}).finally(()=>clearTimeout(timer));
  return()=>{live=false;clearTimeout(timer);controller.abort();};
 },[movementId,retry,profile]);
 const canRequest=canRequestReceiptDeletion(profile,data?.kind,data);
 const transferFields=data?cashTransferFacts(data.kind,data.transfer,true):[];
 const label=data?.reconciliation?.mode==='zero'?'تصفير القاصة':cashKind(data?.kind);
 async function requestDeletion(){if(!canRequest||deleteLock.current||!data?.deletion?.canRequest)return;deleteLock.current=true;setDeleting(true);setDeleteError('');setDeleteMessage('');try{
  const r=await requestReceiptDeletion(data.deletion.invoiceId,undefined,profile);if(r){setDeleteMessage('أُرسل طلب الحذف إلى الإدارة. تبقى الحركة محسوبة حتى الموافقة.');setRetry(n=>n+1);}
 }catch(e){setDeleteError(e.code?e.message:'لم يتأكد إرسال الطلب؛ حدّث تفاصيل الحركة قبل المحاولة مجددًا.');setRetry(n=>n+1);}finally{deleteLock.current=false;setDeleting(false);}}
 if(editing)return <CashRecordEditor movementId={movementId} profile={profile} onCancel={()=>setEditing(false)} onSaved={()=>{setEditing(false);setData(null);setRetry(n=>n+1);onChanged?.();}}/>;
 return <section ref={panel} className="cashMovementPanel" aria-label="تفاصيل حركة الصندوق"><header><h3>تفاصيل الحركة</h3><button type="button" aria-label="إغلاق تفاصيل الحركة" onClick={onClose}><AppIcon name="close" size={17}/></button></header>
  {error?<div className="accountAlert error" role="alert">{error}<button type="button" className="uiButton secondary" onClick={()=>setRetry(n=>n+1)}>إعادة المحاولة</button></div>:!data?<p role="status">جاري تحميل تفاصيل الحركة…</p>:<>
   <div className="cashMovementIdentity"><b>{label}</b><small><time dateTime={data.date}><bdi dir="ltr">{cashDate(data.date)}</bdi></time>{data.receiptNo!=null&&<> · وصل <bdi dir="ltr">#{data.receiptNo}</bdi></>}</small></div>
   <div className="cashMovementBalances" aria-label="حساب الحركة">
    <div><span>رصيد القاصة قبل الحركة</span><b><CashFigure value={data.before} currency={data.currency}/></b></div>
    <div><span>{data.delta>0?'داخل إلى القاصة':data.delta<0?'خارج من القاصة':'دون حركة نقدية'}</span><b className={data.delta<0?'cashMovementOut':'cashMovementIn'}><CashFigure value={data.delta} currency={data.currency} signed/></b></div>
    <div className="cfDetailAfter"><span>{data.kind==='transfer_transit'?'رصيد قيد التسليم بعد الحركة':'رصيد القاصة بعد الحركة'}</span><b><CashFigure value={data.ownerBalance??data.after} currency={data.currency}/></b></div>
   </div>
   <dl className="cashMovementFacts"><div><dt>القاصة</dt><dd>{data.ownerName}</dd></div>{data.actorName&&<div><dt>المسجل</dt><dd>{data.actorName}</dd></div>}{data.actorPhone&&<div><dt>هاتف المسجل</dt><dd><PhoneActions phone={data.actorPhone} label={data.actorName||'المسجل'}/></dd></div>}{data.party&&<div><dt>الجهة</dt><dd>{data.party}</dd></div>}{data.document?.warehouse&&<div><dt>المخزن</dt><dd>{data.document.warehouse}</dd></div>}{data.document?.paymentMode&&<div><dt>طريقة الدفع</dt><dd>{paymentMode(data.document.paymentMode)}</dd></div>}{data.document?.receiptNo&&<div><dt>{data.document.deleted?'الوصل المحذوف':'الوصل المرتبط'}</dt><dd>#{data.document.receiptNo}</dd></div>}</dl>
   {transferFields.length>0&&<section className="cashMovementTransfer"><h4>أطراف التحويل</h4>
    <dl className="cashMovementFacts">
     {transferFields.map(({label,value})=><div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}
     {data.transfer?.amount!=null&&<div><dt>المبلغ المسلّم</dt><dd><CashFigure value={data.transfer.amount} currency={data.transfer.currency||data.currency}/></dd></div>}
     {data.transfer?.status&&<div><dt>حالة التحويل</dt><dd>{transferStatus(data.transfer.status)}</dd></div>}
     {data.transfer?.decidedAt&&<div><dt>تاريخ القرار</dt><dd><bdi dir="ltr">{cashDate(data.transfer.decidedAt)}</bdi></dd></div>}
     {data.transfer?.expense>0&&<div><dt>مصروف التسليم</dt><dd><CashFigure value={data.transfer.expense} currency="IQD"/>{data.transfer.expenseNote&&' · '+data.transfer.expenseNote}</dd></div>}
    </dl>{data.transfer?.note&&data.transfer.note!==data.note&&<p>{data.transfer.note}</p>}
   </section>}
   {data.exchange&&<div className="cashMovementExchange"><h4>{data.exchange.mode==='buy_usd'?'شراء دولار':'بيع دولار'}</h4><p><bdi>{money(data.exchange.amount,'USD')} $</bdi> · صرف <bdi>{money(data.exchange.rate)} د.ع</bdi> لكل دولار</p></div>}
   {data.reconciliation&&<div className="cashMovementReconcile"><h4>{data.reconciliation.mode==='zero'?'تفاصيل التصفير':'تفاصيل تعديل الرصيد'}</h4><dl className="cashMovementFacts">{['IQD','USD'].map(c=><div key={c}><dt>{c==='IQD'?'الدينار':'الدولار'}</dt><dd><bdi>{money(data.reconciliation['before'+c],c)} {unit(c)}</bdi> ← <bdi>{money(data.reconciliation['after'+c],c)} {unit(c)}</bdi></dd></div>)}</dl><p>بواسطة {data.reconciliation.actorName}</p></div>}
   {data.items?.length>0&&<div className="cashMovementItems"><h4>مواد الوصل · {data.items.length}</h4>{data.items.map((item,i)=><article key={i}><b>{i+1}. {item.name}</b><small>{item.brand} {item.category}</small><div><span>الكمية <b>{money(item.qty)}</b></span><span>سعر الوحدة <b><bdi>{money(item.price)} د.ع</bdi></b></span><span>المجموع <b><bdi>{money(item.total)} د.ع</bdi></b></span></div></article>)}</div>}
   {data.note&&<p className="cashMovementNote"><b>البيان</b>{data.note}</p>}
   <div className="cashMovementRecordActions">{data.edit?.canEdit&&<button type="button" className="uiButton cashMovementEditButton" disabled={deleting} onClick={()=>setEditing(true)}><AppIcon name="edit" size={16}/>{data.edit.type==='settlement'?'تعديل تسوية الأرباح':'تعديل الحركة'}</button>}
   {canRequest&&data.deletion?.canRequest&&<button type="button" className="uiButton cashMovementDeleteButton" disabled={deleting||!!data.deletion.blockedReason||!!data.deletion.pendingRequestId} onClick={requestDeletion}><AppIcon name="trash" size={16}/>{deleting?'جاري إرسال الطلب…':data.deletion.pendingRequestId?'طلب الحذف بانتظار الموافقة':'طلب حذف الحركة'}</button>}</div>
   {canRequest&&data.deletion?.blockedReason&&<p className="formHint">{data.deletion.blockedReason}</p>}{canRequest&&data.deletion?.pendingRequestId&&<p className="cashMovementDeleteNotice">الحذف يحتاج موافقة الإدارة. <a href={'/?section=deletionRequests&deleteRequest='+data.deletion.pendingRequestId}>متابعة طلب الحذف</a></p>}
   <ReportActions enabled html={a4('تفاصيل حركة الصندوق',cashMovementBody(data,label),'',data.ownerName)} filename="تفاصيل-حركة-الصندوق"/>
  </>}
  {deleteError&&<p role="alert" className="workflowError">{deleteError}</p>}{deleteMessage&&<p role="status" className="cashMovementDeleteNotice">{deleteMessage}</p>}
 </section>;
}
