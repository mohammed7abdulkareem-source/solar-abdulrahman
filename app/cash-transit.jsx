'use client';
import {useMemo,useState} from 'react';
import AppIcon from './app-icons';
import {formatMoney as money} from './money-format.mjs';
import {cashDate} from './cash-movement-utils.mjs';
import {cashPendingSnapshot} from './cash-home-utils.mjs';
import {salesAuthorizationKey} from './sales-read-scope.mjs';

export default function CashTransit({data,profile,ownerId='',ready,error='',onRetry,onOpen}){
 const [expanded,setExpanded]=useState(false),scope=salesAuthorizationKey(profile);
 const result=useMemo(()=>{if(!ready)return null;try{return {data:cashPendingSnapshot(data,profile,ownerId)};}catch(e){return {error:e.message};}},[data,ready,scope,ownerId]);
 const snapshot=result?.data,problem=error||result?.error,rows=snapshot?.rows||[],shown=expanded?rows:rows.slice(0,3);
 return <section className="cfPendingPanel" aria-label="التحويلات المعلقة" aria-busy={!ready&&!problem}>
  <header className="cfPendingHeader"><span className="cfPendingIcon"><AppIcon name="exchange" size={20}/></span><div><h2>بانتظار الاستلام</h2><p>مبالغ أُرسلت ولم يؤكد المستلم استلامها</p></div><span className="cfPendingCount">{snapshot?snapshot.count:'—'}</span></header>
  {problem?<div className="cfPendingError" role="alert"><p>تعذر تأكيد التحويلات المعلّقة.</p><button type="button" onClick={onRetry}>إعادة التحديث</button></div>:!snapshot?<p className="cfPendingLoading" role="status">جاري تأكيد التحويلات المعلّقة…</p>:<>
   <div className="cfPendingTotal"><span>إجمالي قيد التسليم</span><bdi data-testid="cash-pending-iqd">{money(snapshot.total)} <small>د.ع</small></bdi></div>
   {rows.length?<div className="cfPendingList">{shown.map(row=>{const content=<><div className="cfPendingParties"><span><small>من</small><b dir="auto">{row.senderName}</b></span><AppIcon name="arrow" size={15}/><span><small>إلى</small><b dir="auto">{row.recipientName}</b></span></div><div className="cfPendingFacts"><bdi>{money(row.amount)} <small>د.ع</small></bdi><span className="cfPendingStatus">بانتظار الاستلام</span></div><div className="cfPendingFoot"><time dateTime={row.created_at}>{cashDate(row.created_at)}</time>{onOpen&&<span>تفاصيل التحويل <AppIcon name="arrow" size={12}/></span>}</div></>;
    return onOpen?<button className="cfPendingItem" type="button" key={row.id} data-transfer-id={row.id} aria-label={'عرض تحويل '+money(row.amount)+' د.ع من '+row.senderName+' إلى '+row.recipientName} onClick={()=>onOpen(row.id)}>{content}</button>:<article className="cfPendingItem" key={row.id} data-transfer-id={row.id}>{content}</article>;
   })}</div>:<div className="cfPendingEmpty"><AppIcon name="check" size={18}/><span>لا توجد تحويلات معلّقة</span></div>}
   {rows.length>3&&<button type="button" className="cfPendingMore" aria-expanded={expanded} onClick={()=>setExpanded(value=>!value)}>{expanded?'عرض مختصر':'عرض بقية التحويلات ('+(rows.length-3)+')'}<AppIcon name="chevron" size={14}/></button>}
   <p className="cfPendingNote">المبلغ المعلّق مستقل عن النقد المتاح في القاصات.</p>
  </>}
 </section>;
}
