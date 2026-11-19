'use client';
import PhoneActions from './phone-actions';
import AppIcon from './app-icons';
import {materialQuantity} from './material-movement-utils.mjs';
import {salesAuthorizationKey} from './sales-read-scope.mjs';
import WarehouseQueueRow,{QueueStates} from './warehouse-queue-row';
import './warehouse-queue.css';
import {useCallback,useEffect,useRef,useState} from 'react';
import {inventoryCall,useWarehouseInventory,WarehouseField} from './warehouse-data';
import TransferPreparation from './transfer-preparation';
import WarehouseOrderEditor from './warehouse-order-editor';
import WarehousePricing from './warehouse-pricing';
import {WarehouseAlerts} from './notification-center';
import {supabase} from './supabase';
import {downloadPdf} from './pdf-share.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {quantity,filteredStock,warehouseDate,quantityDocument,warehouseDocument} from './warehouse-utils.mjs';

function useStock(){const [rows,setRows]=useState([]),[error,setError]=useState(''),[loading,setLoading]=useState(true);const refresh=useCallback(async()=>{setLoading(true);const {data,error}=await supabase.rpc('solar_stock_quantities');setError(error?'تعذر تحميل أرصدة المواد. أعد المحاولة.':'');if(!error)setRows(data||[]);setLoading(false)},[]);useEffect(()=>{refresh()},[refresh]);return {rows,error,loading,refresh};}
function DocumentActions({title,html,openA4,shareA4,disabled=false}){const [busy,setBusy]=useState(false),[error,setError]=useState('');async function run(fn){if(busy)return;setBusy(true);setError('');try{await fn()}catch{setError('تعذر تجهيز الملف. حاول مرة أخرى.')}finally{setBusy(false)}}return <><div className="warehouseActions"><button disabled={busy||disabled} onClick={()=>openA4(html())}>معاينة</button><button disabled={busy||disabled} onClick={()=>run(()=>downloadPdf(title,html()))}>{busy?'تجهيز الملف…':'حفظ PDF'}</button><button disabled={busy||disabled} onClick={()=>run(()=>shareA4(title,'',html()))}>مشاركة PDF</button></div>{error&&<p role="alert" className="workflowError">{error}</p>}</>;}

export function InventoryQuantities({a4,openA4,shareA4}){
 const {rows,error,loading,refresh}=useStock(),[query,setQuery]=useState(''),[brand,setBrand]=useState(''),[category,setCategory]=useState(''),[available,setAvailable]=useState(true);
 const shown=filteredStock(rows,query,brand,category,available),total=shown.reduce((sum,p)=>sum+Number(p.qty||0),0);
 const html=()=>a4('أرصدة المواد — بدون أسعار',quantityDocument(shown),'إجمالي الكميات: '+quantity(total),'عدد المواد: '+quantity(shown.length)+' • '+new Date().toLocaleDateString('ar-IQ'));
 return <section className="warehouseWorkspace"><DocumentActions title="أرصدة-المواد" html={html} openA4={openA4} shareA4={shareA4} disabled={loading||!!error}/><div className="card warehouseFilters"><h3>أرصدة المواد الكلية</h3><input aria-label="بحث المادة" value={query} onChange={e=>setQuery(e.target.value)} placeholder="بحث باسم المادة أو الكود…"/><div className="warehousePair"><label>البراند<select value={brand} onChange={e=>setBrand(e.target.value)}><option value="">كل البراندات</option>{[...new Set(rows.map(p=>p.brand).filter(Boolean))].map(b=><option key={b}>{b}</option>)}</select></label><label>الصنف<select value={category} onChange={e=>setCategory(e.target.value)}><option value="">كل الأصناف</option>{[...new Set(rows.map(p=>p.category).filter(Boolean))].map(c=><option key={c}>{c}</option>)}</select></label></div><label className="warehouseCheck"><input type="checkbox" checked={available} onChange={e=>setAvailable(e.target.checked)}/>المتوفر فقط</label><button onClick={refresh} disabled={loading}>تحديث الأرصدة</button></div>{error&&<p role="alert" className="workflowError">{error}</p>}<div className="warehouseSummary"><span>{quantity(shown.length)} مادة</span><b>{quantity(total)} إجمالي الكميات</b></div>{loading?<p className="empty">جاري تحميل الأرصدة…</p>:<div className="warehouseStockList">{shown.map(p=><article className="card warehouseStock" key={p.id}><div><b>{p.name}</b><small>{p.code} • {[p.brand,p.category].filter(Boolean).join(' • ')}</small></div><div><small>الرصيد</small><strong>{quantity(p.qty)}</strong></div></article>)}{!shown.length&&<p className="empty">لا توجد مواد ضمن البحث</p>}</div>}</section>;
}

export {default as StockMovements} from './stock-movements';

export default function WarehouseWorkspace(props){
 return <DailyWarehouseWorkspace key={salesAuthorizationKey(props.profile)} {...props}/>;
}
function DailyWarehouseWorkspace({profile,a4,openA4,shareA4,onChanged,selectedInvoice='',onClearSelection,selectedTransfer='',onClearTransfer}){
 const stock=useWarehouseInventory({aggregate:true}),[query,setQuery]=useState(''),[search,setSearch]=useState(selectedInvoice?'@id:'+selectedInvoice:''),[state,setState]=useState(selectedInvoice?'':'pending'),[offset,setOffset]=useState(0),[result,setResult]=useState({rows:[],count:0}),[loading,setLoading]=useState(true),[error,setError]=useState(''),[message,setMessage]=useState(''),[busy,setBusy]=useState(false),[editing,setEditing]=useState(null);
 useEffect(()=>{if(selectedInvoice){stock.setWarehouse('');setState('');setQuery('');setSearch('@id:'+selectedInvoice);setOffset(0)}},[selectedInvoice]);
 const canPrepare=profile?.user_type==='warehouse'||profile?.is_admin;
 const [pane,setPane]=useState(selectedTransfer?'transfers':'invoices');
 const queueSeeded=useRef(!!selectedTransfer||!!selectedInvoice),actionLock=useRef(false);
 const [loadedScope,setLoadedScope]=useState(null);
 const scope=JSON.stringify([stock.warehouseId,search,state,offset]);
 useEffect(()=>{if(selectedTransfer){queueSeeded.current=true;setPane('transfers');}},[selectedTransfer]);
 useEffect(()=>{if(selectedInvoice){queueSeeded.current=true;setPane('invoices');}},[selectedInvoice]);
 useEffect(()=>{
  if(queueSeeded.current||!stock.ready||loadedScope!==scope||error)return;
  queueSeeded.current=true;
  if(canPrepare&&stock.pendingTransferCount>0&&result.statusCounts?.pending===0)setPane('transfers');
 },[stock.ready,stock.pendingTransferCount,loadedScope,scope,error,canPrepare,result.statusCounts]);
 function choosePane(value){queueSeeded.current=true;setPane(value);}
 const loadId=useRef(0);
 const load=useCallback(async()=>{
  const id=++loadId.current;setLoading(true);
  try{
   const data=await inventoryCall('orders',{warehouseId:stock.warehouseId?Number(stock.warehouseId):null,search,state,offset});
   if(id!==loadId.current)return;
   if(!Array.isArray(data?.rows))throw new Error('تعذّر قراءة قائمة التجهيز.');
   setError('');setResult(data);setLoadedScope(scope);
  }catch{if(id===loadId.current){setError('تعذر تحميل فواتير التجهيز. أعد المحاولة.');setLoadedScope(null);}}
  finally{if(id===loadId.current)setLoading(false);}
 },[search,state,offset,stock.warehouseId,scope]);
 useEffect(()=>{setOffset(0)},[stock.warehouseId]);
 useEffect(()=>{
  load();
  const refresh=()=>{if(document.visibilityState==='visible'&&!actionLock.current)load();};
  window.addEventListener('solar-notification',refresh);window.addEventListener('focus',refresh);
  const timer=setInterval(refresh,10000);
  return()=>{++loadId.current;window.removeEventListener('solar-notification',refresh);window.removeEventListener('focus',refresh);clearInterval(timer);};
 },[load]);
 async function action(row,action,lines=null,note=row.note||''){
  if(actionLock.current)return;
  actionLock.current=true;setBusy(true);setMessage('');setError('');
  try{
   const {error}=await supabase.rpc('solar_warehouse_action',{invoice_id:row.id,expected_token:row.token,action,lines,note});
   if(error)throw error;
   setMessage(action==='ready'?'تم التجهيز وإشعار صاحب الفاتورة.':action==='save'?(row.kind==='sale'&&lines?.some(i=>i.lineId==null)?'تم إرسال جميع فقرات التعديل للإدارة لتسعير المواد الجديدة.':'تم حفظ المواد وتصحيح الرصيد وإشعار صاحب الفاتورة.'):'أعيدت الفاتورة لقائمة التجهيز.');
   setEditing(null);
   await Promise.allSettled([load(),stock.refresh(),Promise.resolve().then(onChanged)]);
   return {ok:true};
  }catch(e){const message=e.message||'تعذر تنفيذ العملية';setError(message);return {ok:false,error:message,stale:e.code==='PT409'};}
  finally{actionLock.current=false;setBusy(false);}
 }
 const showRows=loadedScope===scope, rows=showRows?result.rows:[];
 function chooseState(value){
  setState(value);setOffset(0);setEditing(null);
  if(selectedInvoice){setSearch('');setQuery('');onClearSelection?.();}
 }
 function reviewFirst(row){
  const card=document.getElementById('warehouse-order-'+row.id);
  const list=card?.querySelector('.warehousePickList');if(list)list.open=true;
  card?.focus({preventScroll:true});card?.scrollIntoView({block:'start',behavior:'smooth'});
 }
 const first=rows.find(row=>row.status==='pending'&&!row.pricingPending);
 const refresh=()=>{void load();void stock.refresh();};
 return <section className="dailyWarehouse" aria-label="تجهيز المخزن" data-testid="warehouse-daily-queue">
  <header className="warehouseDayHead"><span className="warehouseQueueMark"><AppIcon name="warehouse" size={22}/></span><div><h1>قائمة تجهيز المخزن</h1><small>{new Intl.DateTimeFormat('ar-IQ',{timeZone:'Asia/Baghdad',weekday:'long',day:'numeric',month:'long'}).format(new Date())}</small></div>
   <button type="button" className="warehouseDayRefresh" disabled={busy||loading} aria-label="تحديث قائمة التجهيز" onClick={refresh}><AppIcon name="refresh" size={18}/>تحديث</button></header>
  {canPrepare&&<nav className="warehouseWorkTabs" aria-label="نوع تجهيز المخزن">
   <button type="button" aria-pressed={pane==='invoices'} onClick={()=>choosePane('invoices')}><AppIcon name="receipt" size={17}/>فواتير البيع</button>
   <button type="button" aria-pressed={pane==='transfers'} onClick={()=>choosePane('transfers')}><AppIcon name="truck" size={17}/>طلبات نقل المخازن {Number(stock.pendingTransferCount)>0&&<b>{stock.pendingTransferCount}</b>}</button>
  </nav>}
  {pane==='transfers'&&canPrepare?<TransferPreparation inventory={stock} a4={a4} selectedTransfer={selectedTransfer} onClearSelection={onClearTransfer} onChanged={()=>{stock.refresh();onChanged?.();}}/>:
  <section className="warehouseWorkspace warehouseDailyOrders">
   <QueueStates label="قوائم التجهيز" choices={[[ 'pending','بانتظار التجهيز'],['ready','تم التجهيز'],['','كل الفواتير']]} counts={showRows?result.statusCounts:null} value={state} onChange={chooseState}/>
   <form className="card warehouseFilters warehouseDailySearch" onSubmit={event=>{
    event.preventDefault();const term=normalizeSearch(query).replace(/^#/,'');if(offset===0&&term===search)load();else{setOffset(0);setSearch(term);}
    if(selectedInvoice)onClearSelection?.();
   }}>
    <div className="warehouseSearchBox"><AppIcon name="search" size={18}/><input value={query} onChange={event=>setQuery(event.target.value)} placeholder="رقم الوصل أو اسم الزبون" aria-label="بحث فواتير التجهيز"/></div>
    <button type="submit" disabled={loading}>بحث / تحديث</button>
    <WarehouseField inventory={stock} allowAll label="مخزن التجهيز"/>
    {(search||selectedInvoice)&&<button type="button" className="warehouseClearSearch" onClick={()=>{setQuery('');setSearch('');setState('pending');setOffset(0);onClearSelection?.();}}>عرض قائمة التجهيز كاملة</button>}
   </form>
   {message&&<p role="status" className="workflowSuccess">{message}</p>}
   {error&&<p role="alert" className="workflowError">{error}</p>}
   {showRows&&<div className="warehouseListHead"><h2>{state==='ready'?'الوصولات المجهّزة':state==='pending'?'وصولات بانتظار التجهيز':'وصولات التجهيز'} <small>({quantity(result.count)})</small></h2>
    {first&&state==='pending'&&<button type="button" onClick={()=>reviewFirst(first)}>مراجعة وصل <bdi>#{first.receiptNo}</bdi></button>}</div>}
   {loading&&!showRows&&<p role="status" className="empty">جاري تحميل الفواتير…</p>}
   {rows.map(row=>{
    const ready=row.status==='ready', pricing=!!row.pricingPending;
    const selected=String(row.id)===String(selectedInvoice);
    return <WarehouseQueueRow key={row.id} id={'warehouse-order-'+row.id} className="warehouseOrder" detailsClass="warehousePickList" selected={selected}
     state={ready?'ready':pricing?'pricing':'pending'} status={ready?'تم التجهيز':pricing?'بانتظار التسعير':'بانتظار التجهيز'}
     label={'تفاصيل وصل #'+row.receiptNo} identity={<>{row.kind==='system'?'منظومة':'جملة'} · وصل <bdi>#{row.receiptNo}</bdi></>}
     title={row.party||'زبون نقدي'} context={<>مخزن التجهيز: {row.warehouseName||'غير محدد'} · {warehouseDate(row.date)}</>}
     items={row.items} quantityLabel={ready?'المجهّز':'المطلوب'} quantityTestId={ready?'warehouse-prepared-quantity':'warehouse-required-quantity'}>
     {()=><><div className="warehouseRowItems"><h3>مواد الوصل</h3>
      {row.items.map(item=><div className="warehouseOrderLine" key={item.lineId??'pending-'+item.productId}><span><b dir="auto">{item.name}</b><small>{[item.brand,item.category].filter(Boolean).join(' · ')}</small></span><strong>{materialQuantity(item.qty)}</strong></div>)}
     </div><PhoneActions phone={row.phone} label={row.party||'الزبون'}/>{row.address&&<p>{row.address}</p>}
     {pricing&&<p className="warehousePricingBadge">تعديلات المواد بانتظار تسعير الإدارة</p>}
     {row.preparedBy&&<p>جهّزها: {row.preparedBy} • {warehouseDate(row.preparedAt)}</p>}{row.note&&<p>{row.note}</p>}
     {editing?.id===row.id?<WarehouseOrderEditor key={editing.token} row={editing} onReload={async()=>{
      const fresh=await inventoryCall('orders',{warehouseId:editing.warehouseId,search:'@id:'+editing.id,state:''});
      if(fresh.rows?.[0]){const latest=fresh.rows[0];setEditing(latest);setResult(current=>({...current,rows:current.rows.map(item=>String(item.id)===String(latest.id)?latest:item)}));}
     }} onSave={(lines,note)=>action(editing,'save',lines,note)} onCancel={()=>setEditing(null)} busy={busy}/>:
     <div className="warehouseActions warehousePrepareActions">
      {!ready&&<button type="button" className="warehouseConfirmReady" disabled={busy||pricing} onClick={()=>{if(confirm('تأكيد تجهيز جميع مواد الوصل #'+row.receiptNo+'؟'))void action(row,'ready');}}>تم التجهيز ✓</button>}
      <button type="button" disabled={busy||!row.canEdit} onClick={()=>setEditing(row)}>تعديل المواد</button>
      {ready&&<button type="button" disabled={busy||!row.canEdit} onClick={()=>action(row,'reopen')}>إعادة للتجهيز</button>}
     </div>}
     {!row.canEdit&&<small>ملف التنصيب قيد التنفيذ أو مكتمل؛ تعديل المواد مقفل.</small>}
     <DocumentActions title={'وصل-مخزني-'+row.receiptNo} html={()=>a4('وصل تجهيز مخزني',warehouseDocument(row),'',warehouseDate(row.date))} openA4={openA4} shareA4={shareA4}/>
     </>}
    </WarehouseQueueRow>;
   })}
   {showRows&&!loading&&!rows.length&&<section className="warehouseEmpty"><p>{search?'لا توجد فواتير مطابقة للبحث.':state==='pending'?'لا توجد فواتير بانتظار التجهيز.':state==='ready'?'لا توجد فواتير مجهّزة.':'لا توجد فواتير تجهيز.'}</p>
    {state==='pending'&&Number(result.statusCounts?.ready)>0&&<button type="button" onClick={()=>chooseState('ready')}>عرض {quantity(result.statusCounts.ready)} فاتورة مجهّزة</button>}</section>}
   {showRows&&(result.count>30||offset>0)&&<div className="archivePagination"><button disabled={offset===0||loading} onClick={()=>setOffset(Math.max(0,offset-30))}>السابق</button><span>{Math.floor(offset/30)+1} / {Math.max(1,Math.ceil(result.count/30))}</span><button disabled={offset+30>=result.count||loading} onClick={()=>setOffset(offset+30)}>التالي</button></div>}
  </section>}
  <WarehousePricing profile={profile} onChanged={()=>{load();stock.refresh();onChanged?.();}}/>
  {profile?.id&&<WarehouseAlerts userId={profile.id}/>}
 </section>;
}
