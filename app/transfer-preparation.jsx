'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import AppIcon from './app-icons';
import {materialQuantity} from './material-movement-utils.mjs';
import WarehouseReceiptActions from './warehouse-receipt-actions';
import {inventoryCall,useInventoryRequest,WarehouseField} from './warehouse-data';
import WarehouseQueueRow,{QueueStates} from './warehouse-queue-row';
import {quantity,warehouseDate} from './warehouse-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {transferStatus} from './inventory-workspace';

const states=[['pending','بانتظار التجهيز'],['resolved','محسومة'],['','كل الطلبات']];
const outcomes=[['posted','مجهّزة'],['cancelled','ملغاة قبل التجهيز'],['reversed','ملغاة بعد التجهيز']];

export default function TransferPreparation({inventory,a4,onChanged,refreshVersion=0,selectedTransfer='',onClearSelection}){
 const [query,setQuery]=useState(''),[search,setSearch]=useState(''),[state,setState]=useState(selectedTransfer?'':'pending'),[offset,setOffset]=useState(0);
 const [loaded,setLoaded]=useState(null),[loading,setLoading]=useState(true),[error,setError]=useState(''),[message,setMessage]=useState(''),[working,setWorking]=useState(false);
 const send=useInventoryRequest(),generation=useRef(0),actionLock=useRef(false);
 const scope=JSON.stringify([inventory.warehouseId,search,state,offset,selectedTransfer]);
 const result=loaded?.scope===scope?loaded.result:null;
 useEffect(()=>{if(selectedTransfer){inventory.setWarehouse('');setQuery('');setState('');setOffset(0);setSearch('');}},[selectedTransfer,inventory.setWarehouse]);
 useEffect(()=>setOffset(0),[inventory.warehouseId]);
 const load=useCallback(async()=>{
  const id=++generation.current;setLoading(true);
  try{
   const data=await inventoryCall('transfer_queue',{warehouseId:inventory.warehouseId?Number(inventory.warehouseId):null,search,state,offset,...(selectedTransfer?{id:selectedTransfer}:{})});
   if(id!==generation.current)return;
   if(!Array.isArray(data?.rows))throw new Error('تعذّر قراءة طلبات النقل.');
   setLoaded({scope,result:data});setError('');
  }catch(e){if(id===generation.current){setLoaded(null);setError(e.message||'تعذر تحميل طلبات النقل.');}}
  finally{if(id===generation.current)setLoading(false);}
 },[inventory.warehouseId,search,state,offset,selectedTransfer,scope]);
 useEffect(()=>{
  load();const refresh=()=>{if(document.visibilityState==='visible'&&!actionLock.current)load();};
  const timer=setInterval(refresh,10000);window.addEventListener('solar-notification',refresh);window.addEventListener('focus',refresh);
  return()=>{++generation.current;clearInterval(timer);window.removeEventListener('solar-notification',refresh);window.removeEventListener('focus',refresh);};
 },[load,refreshVersion]);
 async function prepare(t){
  if(actionLock.current||t.status!=='pending'||!t.canPrepare||!confirm('تأكيد تجهيز جميع مواد طلب النقل #'+t.receiptNo+' من '+t.fromName+' إلى '+t.toName+'؟'))return;
  actionLock.current=true;setWorking(true);setError('');setMessage('');
  try{
   await send('prepare_transfer',{id:t.id,expectedRevision:t.revision});
   setMessage('تم تجهيز النقل وإضافة الكميات إلى مخزن الاستلام وإشعار صاحب الطلب.');
   await Promise.allSettled([load(),Promise.resolve().then(onChanged)]);
  }catch(e){setError(e.message||'تعذر تأكيد التجهيز. أعد المحاولة بنفس البيانات.');}
  finally{actionLock.current=false;setWorking(false);}
 }
 function changeState(value){setState(value);setOffset(0);}
 function find(event){
  event.preventDefault();const term=normalizeSearch(query).replace(/^#/,'');setOffset(0);setSearch(term);
  if(offset===0&&term===search)load();
 }
 return <section className="warehouseTransferQueue" aria-label="قائمة نقل المخازن">
  {selectedTransfer?<button type="button" className="warehouseClearSearch" onClick={()=>{setQuery('');setSearch('');changeState('pending');onClearSelection?.();}}>عرض طلبات النقل كاملة</button>:<>
   <QueueStates label="حالات تجهيز النقل" choices={states} counts={result?.statusCounts} value={state} onChange={changeState}/>
   <form className="warehouseFilters warehouseDailySearch" onSubmit={find}>
    <div className="warehouseSearchBox"><AppIcon name="search" size={18}/><input aria-label="بحث طلبات النقل" placeholder="رقم الطلب أو المخزن أو المستخدم" value={query} onChange={e=>setQuery(e.target.value)}/></div>
    <button type="submit" disabled={loading}>بحث / تحديث</button>
    {inventory.warehouses.length===1?<span className="warehouseSingleSource"><AppIcon name="warehouse" size={17}/>المصدر: {inventory.warehouses[0].name}</span>:<WarehouseField inventory={inventory} allowAll label="مخزن المصدر المطلوب تجهيزه"/>}
   </form>
  </>}
  {message&&<p role="status" className="workflowSuccess">{message}</p>}
  {error&&<p role="alert" className="workflowError">{error} <button type="button" onClick={load}>إعادة المحاولة</button></p>}
  {result&&<div className="warehouseListHead"><h2>{state==='pending'?'طلبات بانتظار التجهيز':state==='resolved'?'طلبات النقل المحسومة':'طلبات نقل المخازن'} <small>({quantity(result.count)})</small></h2></div>}
  {state==='resolved'&&result&&<dl className="warehouseOutcomes" aria-label="تفاصيل الطلبات المحسومة">{outcomes.map(([key,label])=>
   <div key={key} data-outcome={key}><dt>{label}</dt><dd>{result.statusCounts?.[key]==null?'—':quantity(result.statusCounts[key])}</dd></div>)}</dl>}
  {loading&&!result&&<p role="status" className="warehouseEmpty">جاري تحميل طلبات النقل…</p>}
  {result?.rows.map(t=><WarehouseQueueRow key={t.id} className="sourceTransferOrder" detailsClass="sourceTransferDetails" transfer selected={String(t.id)===String(selectedTransfer)}
   state={t.status} status={transferStatus(t.status)} label={'تفاصيل طلب النقل #'+t.receiptNo} items={t.items} quantityLabel={t.status==='posted'?'المجهّز':t.status==='pending'?'المطلوب':'كمية الطلب'}
   identity={<>طلب نقل <bdi>#{t.receiptNo}</bdi></>} title={<>{t.fromName} <span className="warehouseRouteArrow">إلى</span> {t.toName}</>} context={<><span title="مقدم الطلب"><AppIcon name="user" size={14}/>{t.actor||'غير محدد'}</span><span><AppIcon name="calendar" size={14}/>{warehouseDate(t.date)}</span></>}>
   {()=><><div className="warehouseRowItems sourceTransferItems"><header className="warehouseMaterialsHeading"><h3>مواد طلب النقل</h3><span>الكمية</span></header>{t.items.map((i,n)=><div key={n} className="warehouseOrderLine"><span><b dir="auto">{i.name}</b><small>{[i.code,i.brand,i.category].filter(Boolean).join(' · ')}</small></span><strong dir="ltr">{materialQuantity(i.qty)}</strong></div>)}</div>
    {t.note&&<p>{t.note}</p>}{t.preparedBy&&<p className="sourceTransferPrepared">جهّزها {t.preparedBy} · {warehouseDate(t.preparedAt)}</p>}
    {t.status==='pending'&&t.canPrepare&&<button type="button" className="inventoryPrimary sourceTransferConfirm" disabled={working} onClick={()=>prepare(t)}><AppIcon name="check" size={17}/>{working?'جاري تأكيد التجهيز…':'تأكيد تجهيز النقل'}</button>}
    <WarehouseReceiptActions row={t} transfer a4={a4}/>
   </>}
  </WarehouseQueueRow>)}
  {result&&!result.rows.length&&<p className="warehouseEmpty">{state==='pending'?'لا توجد طلبات نقل خارجة من مخزنك بانتظار التجهيز.':state==='resolved'?'لا توجد طلبات نقل محسومة ضمن الاختيار.':'لا توجد طلبات ضمن الاختيار.'}</p>}
  {result&&(result.count>30||offset>0)&&<nav className="archivePagination" aria-label="صفحات طلبات النقل"><button disabled={offset===0||loading} onClick={()=>setOffset(v=>Math.max(0,v-30))}>السابق</button><span>{Math.floor(offset/30)+1} / {Math.max(1,Math.ceil(result.count/30))}</span><button disabled={offset+30>=result.count||loading} onClick={()=>setOffset(v=>v+30)}>التالي</button></nav>}
 </section>;
}
