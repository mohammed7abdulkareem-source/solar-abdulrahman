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

export default function CashMovementDetail({movementId,profile,a4,onClose,onChanged}){
 const panel=useRef(null),[editing,setEditing]=useState(false);
 useEffect(()=>{panel.current?.scrollIntoView({block:'start',behavior:'smooth'});},[]);
 const [data,setData]=useState(null),[error,setError]=useState(''),[retry,setRetry]=useState(0);
 useEffect(()=>{let live=true;const controller=new AbortController();setData(null);setError('');
  const timer=setTimeout(()=>controller.abort(),10000);
  supabase.rpc('solar_cash_movement_detail',{movement_id:movementId}).abortSignal(controller.signal).then(({data,error})=>{if(error)throw error;if(live)setData(data);}).catch(e=>{if(live)setError(e.code?e.message:'تعذر تحميل تفاصيل الحركة. أعد المحاولة.');}).finally(()=>clearTimeout(timer));
  return()=>{live=false;clearTimeout(timer);controller.abort();};
 },[movementId,retry]);
 const label=data?.reconciliation?.mode==='zero'?'تصفير القاصة':cashKind(data?.kind);
 if(editing)return <CashRecordEditor movementId={movementId} profile={profile} onCancel={()=>setEditing(false)} onSaved={()=>{setEditing(false);setData(null);setRetry(n=>n+1);onChanged?.();}}/>;
 return <section ref={panel} className="cashMovementPanel" aria-label="تفاصيل حركة الصندوق"><header><h3>تفاصيل الحركة</h3><button type="button" aria-label="إغلاق تفاصيل الحركة" onClick={onClose}><AppIcon name="close" size={17}/></button></header>
  {error?<div className="accountAlert error" role="alert">{error}<button type="button" className="uiButton secondary" onClick={()=>setRetry(n=>n+1)}>إعادة المحاولة</button></div>:!data?<p role="status">جاري تحميل تفاصيل الحركة…</p>:<>
   <div className="cashMovementIdentity"><b>{label}</b><small>{cashDate(data.date)}{data.receiptNo&&' · وصل #'+data.receiptNo}</small></div>
   <div className="cashMovementBalances"><div><span>رصيد القاصة قبل الحركة</span><b><bdi>{money(data.before,data.currency)} {unit(data.currency)}</bdi></b></div><div><span>{data.delta>0?'داخل إلى القاصة':data.delta<0?'خارج من القاصة':'بدون تغيير نقدي'}</span><b className={data.delta>=0?'cashMovementIn':'cashMovementOut'}><bdi>{data.delta>0?'+':data.delta<0?'−':''}{money(data.amount,data.currency)} {unit(data.currency)}</bdi></b></div><div><span>رصيد القاصة بعد الحركة</span><b><bdi>{money(data.after,data.currency)} {unit(data.currency)}</bdi></b></div></div>
   <dl className="cashMovementFacts"><div><dt>القاصة</dt><dd>{data.ownerName}</dd></div>{data.actorName&&<div><dt>المسجل</dt><dd>{data.actorName}</dd></div>}{data.actorPhone&&<div><dt>هاتف المسجل</dt><dd><PhoneActions phone={data.actorPhone} label={data.actorName||'المسجل'}/></dd></div>}{data.party&&<div><dt>الجهة</dt><dd>{data.party}</dd></div>}{data.document?.warehouse&&<div><dt>المخزن</dt><dd>{data.document.warehouse}</dd></div>}{data.document?.paymentMode&&<div><dt>طريقة الدفع</dt><dd>{paymentMode(data.document.paymentMode)}</dd></div>}{data.document?.receiptNo&&<div><dt>{data.document.deleted?'الوصل المحذوف':'الوصل المرتبط'}</dt><dd>#{data.document.receiptNo}</dd></div>}</dl>
   {data.transfer&&<div className="cashMovementTransfer"><h4>تفاصيل تسليم القاصة</h4><dl className="cashMovementFacts"><div><dt>من</dt><dd>{data.transfer.sender}</dd></div><div><dt>إلى</dt><dd>{data.transfer.recipient}</dd></div><div><dt>المبلغ المسلّم</dt><dd><bdi>{money(data.transfer.amount,data.transfer.currency||'IQD')} {unit(data.transfer.currency||'IQD')}</bdi></dd></div><div><dt>الحالة</dt><dd>{transferStatus(data.transfer.status)}</dd></div>{data.transfer.expense>0&&<div><dt>مصروف التسليم</dt><dd><bdi>{money(data.transfer.expense)} د.ع</bdi>{data.transfer.expenseNote&&' · '+data.transfer.expenseNote}</dd></div>}{data.transfer.decidedBy&&<div><dt>القرار بواسطة</dt><dd>{data.transfer.decidedBy}{data.transfer.decidedAt&&' · '+cashDate(data.transfer.decidedAt)}</dd></div>}</dl>{data.transfer.note&&<p>{data.transfer.note}</p>}</div>}
   {data.exchange&&<div className="cashMovementExchange"><h4>{data.exchange.mode==='buy_usd'?'شراء دولار':'بيع دولار'}</h4><p><bdi>{money(data.exchange.amount,'USD')} $</bdi> · صرف <bdi>{money(data.exchange.rate)} د.ع</bdi> لكل دولار</p></div>}
   {data.reconciliation&&<div className="cashMovementReconcile"><h4>{data.reconciliation.mode==='zero'?'تفاصيل التصفير':'تفاصيل تعديل الرصيد'}</h4><dl className="cashMovementFacts">{['IQD','USD'].map(c=><div key={c}><dt>{c==='IQD'?'الدينار':'الدولار'}</dt><dd><bdi>{money(data.reconciliation['before'+c],c)} {unit(c)}</bdi> ← <bdi>{money(data.reconciliation['after'+c],c)} {unit(c)}</bdi></dd></div>)}</dl><p>بواسطة {data.reconciliation.actorName}</p></div>}
   {data.items.length>0&&<div className="cashMovementItems"><h4>مواد الوصل · {data.items.length}</h4>{data.items.map((item,i)=><article key={i}><b>{i+1}. {item.name}</b><small>{item.brand} {item.category}</small><div><span>الكمية <b>{money(item.qty)}</b></span><span>سعر الوحدة <b><bdi>{money(item.price)} د.ع</bdi></b></span><span>المجموع <b><bdi>{money(item.total)} د.ع</bdi></b></span></div></article>)}</div>}
   <p className="cashMovementNote"><b>البيان</b>{data.note||'لا يوجد بيان إضافي.'}</p>
   {data.edit?.canEdit&&<button type="button" className="uiButton cashMovementEditButton" onClick={()=>setEditing(true)}><AppIcon name="edit" size={16}/>{data.edit.type==='settlement'?'تعديل تسوية الأرباح':'تعديل الحركة'}</button>}
   <ReportActions enabled html={a4('تفاصيل حركة الصندوق',cashMovementBody(data,label),money(data.amount,data.currency)+' '+unit(data.currency),data.ownerName)} filename="تفاصيل-حركة-الصندوق"/>
  </>}
 </section>;
}
