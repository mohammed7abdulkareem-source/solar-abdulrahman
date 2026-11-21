'use client';
import {useEffect,useId,useRef,useState} from 'react';
import AppIcon from './app-icons';
import WorkspaceDialog from './workspace-dialog';
import {customerTransferOptions,saveCustomer} from './customer-store.mjs';
import {formatMoney,currencyUnit} from './money-format.mjs';
import {partyBalanceMeaning} from './compact-party-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {warehouseDate} from './warehouse-utils.mjs';
import './customer-owner-transfer.css';

const kindLabel=kind=>kind==='system'?'منظومة':'جملة';
const receiptNumber=row=>row.receiptNo??row.id;
const holder=row=>row.ownerName||'غير مسند';

function ReceiptChoices({receipts,ownerId,selectedIds,onToggle}){
 const [search,setSearch]=useState('');
 const listId=useId();
 const query=normalizeSearch(search).replace(/^#/,'');
 const matches=receipts.filter(row=>normalizeSearch([receiptNumber(row),holder(row),kindLabel(row.kind)].join(' ')).includes(query));
 return <fieldset className="transferReceiptChoices">
  <legend>وصولات البيع والمنظومات</legend>
  {receipts.length>0?<>
   <p>حدّد الوصولات التي سيتابعها هذا المستخدم.</p>
   <div className="transferReceiptFilter">
    <label><AppIcon name="search" size={16}/><input type="search" aria-label="بحث في وصولات العميل" placeholder="رقم الوصل أو المستخدم" onKeyDown={event=>{if(event.key==='Enter')event.preventDefault();}} value={search} onChange={event=>setSearch(event.target.value)}/></label>
    <span aria-live="polite">المحدد <bdi>{selectedIds.size}</bdi> / <bdi>{receipts.length}</bdi></span>
   </div>
   <div className="transferReceiptList">{matches.map(row=>{
    const alreadyAssigned=row.ownerId===ownerId;
    const number=receiptNumber(row);
    return <label key={row.id} className="transferReceiptChoice" data-selected={selectedIds.has(row.id)} data-assigned={alreadyAssigned}>
     <input type="checkbox" aria-label={'نقل وصل #'+number} aria-describedby={listId+'-'+row.id} checked={selectedIds.has(row.id)} disabled={alreadyAssigned} onChange={()=>onToggle(row.id)}/>
     <span className="transferReceiptIdentity" id={listId+'-'+row.id}><strong>{kindLabel(row.kind)} <bdi>#{number}</bdi></strong>
      <small>{holder(row)}{row.date&&<> · {warehouseDate(row.date)}</>}{row.closed===true&&' · مغلق'}</small>
      {alreadyAssigned&&<small>بعهدة المستخدم المختار</small>}
     </span>
     {row.total!=null&&<bdi className="transferReceiptAmount">{formatMoney(row.total,row.currency)} {currencyUnit(row.currency)}</bdi>}
    </label>;
   })}{!matches.length&&<p>لا توجد وصولات تطابق البحث.</p>}</div>
  </>:<p>لا توجد وصولات بيع أو منظومات مرتبطة بهذا العميل.</p>}
 </fieldset>;
}

export default function CustomerOwnerTransfer({account,disabled,onSaved}){
 const [open,setOpen]=useState(false),[step,setStep]=useState('choose');
 const [options,setOptions]=useState(null),[ownerId,setOwnerId]=useState('');
 const [selectedIds,setSelectedIds]=useState(()=>new Set());
 const [loading,setLoading]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const attempt=useRef(null),request=useRef(0),saving=useRef(false),review=useRef(null);
 const {record,owners=[],receipts=[],receiptToken}=options||{};
 const destination=owners.find(owner=>owner.id===ownerId);
 const selectedReceipts=receipts.filter(row=>selectedIds.has(row.id));
 const sameOwner=!!destination&&record?.ownerId===ownerId;
 const canSubmit=!!destination&&(!sameOwner||selectedReceipts.length>0);
 const sourceName=owners.find(owner=>owner.id===record?.ownerId)?.name||record?.ownerName||(record?.ownerId?'المسؤول الحالي':'غير مسند');
 useEffect(()=>()=>{request.current++;},[]);
 useEffect(()=>{if(open&&step==='review')review.current?.focus({preventScroll:true});},[open,step]);

 async function load(){
  const n=++request.current;
  setOptions(null);setOwnerId('');setSelectedIds(new Set());setStep('choose');setError('');setLoading(true);
  try{
   const next=await customerTransferOptions(account.id);
   if(n===request.current)setOptions(next);
  }catch(e){if(n===request.current)setError(e.message||'تعذّر تحميل بيانات التحويل. أعد المحاولة.');}
  finally{if(n===request.current)setLoading(false);}
 }
 function start(){setOpen(true);if(!attempt.current)void load();}
 function close(){
  if(saving.current)return;
  request.current++;setOpen(false);setLoading(false);
 }
 function toggleReceipt(id){
  setSelectedIds(current=>{const next=new Set(current);if(next.has(id))next.delete(id);else next.add(id);return next;});
 }
 async function submit(event){
  event.preventDefault();
  if(!record||!canSubmit||saving.current)return;
  if(step==='choose'){setStep('review');setError('');return;}
  saving.current=true;setBusy(true);setError('');
  const n=request.current;
  try{
   const saved=await saveCustomer(attempt,'transfer_owner',{
    id:record.id,ownerId,token:record.token,receiptIds:selectedReceipts.map(row=>row.id),receiptToken
   });
   if(n!==request.current)return;
   setOpen(false);setOptions(null);setStep('choose');
   const name=saved.ownerName||destination.name,count=saved.receiptCount??selectedReceipts.length;
   const message=sameOwner?'تم إسناد الوصولات المحددة إلى '+name+' ('+count+').':'تم تحويل الزبون إلى '+name+'. عدد الوصولات المنقولة '+count+'.';
   await onSaved({...saved,message});
  }catch(e){
   if(n!==request.current)return;
   if(attempt.current){setError('تعذّر تأكيد نتيجة التحويل. أعد تأكيد التحويل بنفس البيانات.');}
   else{setError(e.message||'تعذر تحويل الزبون. حدّث بيانات التحويل.');setOptions(null);}
  }finally{saving.current=false;if(n===request.current)setBusy(false);}
 }
 return <>
  <button type="button" className="statementTransferTrigger" disabled={disabled||busy} onClick={start}><AppIcon name="exchange" size={16}/>تحويل الزبون</button>
  <WorkspaceDialog open={open} title="تحويل الزبون" className="statementTransferDialog" onClose={close}>
   <p className="statementTransferCustomer">{record?.name||account.name}</p>
   {loading&&<p role="status">جاري تحميل بيانات التحويل…</p>}
   {error&&<p className="miniAlert" role="alert">{error}</p>}
   {!loading&&!record&&<button type="button" className="uiButton secondary" onClick={load}>تحديث بيانات التحويل</button>}
   {record&&<form onSubmit={submit}>
    {step==='choose'?<>
     <div className="statementTransferSource"><span>المسؤول الحالي</span><strong>{sourceName}</strong></div>
     {owners.length?<label>المسؤول الجديد
      <select value={ownerId} onChange={event=>{setOwnerId(event.target.value);setSelectedIds(new Set());}} required>
       <option value="">اختر المستخدم</option>
       {owners.map(owner=><option key={owner.id} value={owner.id}>{owner.name}{owner.id===record.ownerId?' · المسؤول الحالي':''}</option>)}
      </select>
     </label>:<p role="status">لا يوجد مستخدم متاح للتحويل.</p>}
     {destination&&<>
      {sameOwner&&<p className="transferReceiptHint">المستخدم مسؤول عن الزبون حالياً. حدّد الوصولات التي تريد إلحاقها به.</p>}
      <ReceiptChoices key={destination.id} receipts={receipts} ownerId={ownerId} selectedIds={selectedIds} onToggle={toggleReceipt}/>
     </>}
    </>:<div className="transferReviewBody" ref={review} tabIndex={-1} aria-label="مراجعة التحويل">
     <dl className="statementTransferReview">
      <div><dt>من</dt><dd>{sourceName}</dd></div><div><dt>إلى</dt><dd>{destination?.name}</dd></div>
      <div><dt>الرصيد الحالي</dt><dd><bdi>{formatMoney(Math.abs(record.balance),account.currency)} {currencyUnit(account.currency)}</bdi><small>{partyBalanceMeaning('customer',record.balance)}</small></dd></div>
     </dl>
     {selectedReceipts.length?<section className="transferReviewReceipts"><h3>الوصولات المحددة <bdi>({selectedReceipts.length})</bdi></h3>
      <ul>{selectedReceipts.map(row=><li key={row.id}><strong>{kindLabel(row.kind)} <bdi>#{receiptNumber(row)}</bdi></strong><span>من {holder(row)} إلى {destination?.name}</span></li>)}</ul>
     </section>:<p className="transferReceiptHint">سيُنقل حساب الزبون وحده. عدد الوصولات المختارة صفر.</p>}
    </div>}
    <div className="statementTransferFooter">
     {step==='review'&&<button type="button" className="uiButton secondary" disabled={busy||!!attempt.current} onClick={()=>{setStep('choose');setError('');}}>تعديل الاختيار</button>}
     <button type="submit" className="uiButton primary" disabled={busy||!canSubmit}>{step==='choose'?'مراجعة التحويل':busy?'جاري تأكيد التحويل…':'تأكيد تحويل الزبون'}</button>
    </div>
   </form>}
  </WorkspaceDialog>
 </>;
}
