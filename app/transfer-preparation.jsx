'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import AppIcon from './app-icons';
import ReportActions from './report-actions';
import {inventoryCall,useInventoryRequest,WarehouseField} from './warehouse-data';
import {quantity,warehouseDate} from './warehouse-utils.mjs';
import {transferDocument,transferStatus} from './inventory-workspace';

export default function TransferPreparation({inventory,a4,onChanged,selectedTransfer='',onClearSelection}){
 const [query,setQuery]=useState(''),[search,setSearch]=useState(''),[state,setState]=useState(selectedTransfer?'':'pending'),[offset,setOffset]=useState(0),[result,setResult]=useState({rows:[],count:0}),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
 const send=useInventoryRequest(),generation=useRef(0);
 useEffect(()=>{if(selectedTransfer){inventory.setWarehouse('');setState('');setOffset(0);setSearch('');}},[selectedTransfer,inventory.setWarehouse]);
 useEffect(()=>setOffset(0),[inventory.warehouseId]);
 const load=useCallback(async()=>{const id=++generation.current;setLoading(true);try{
  const data=await inventoryCall('transfer_queue',{warehouseId:inventory.warehouseId?Number(inventory.warehouseId):null,search,state,offset,...(selectedTransfer?{id:selectedTransfer}:{})});
  if(id!==generation.current)return;setResult(data);setError('');
 }catch(e){if(id===generation.current){setResult({rows:[],count:0});setError(e.message||'تعذر تحميل طلبات النقل');}}finally{if(id===generation.current)setLoading(false);}},[inventory.warehouseId,search,state,offset,selectedTransfer]);
 useEffect(()=>{load();const refresh=()=>{if(document.visibilityState==='visible')load();};const timer=setInterval(refresh,10000);window.addEventListener('solar-notification',refresh);window.addEventListener('focus',refresh);return()=>{generation.current++;clearInterval(timer);window.removeEventListener('solar-notification',refresh);window.removeEventListener('focus',refresh);};},[load]);
 async function prepare(t){if(busy||!confirm('تأكيد تجهيز جميع مواد طلب النقل #'+t.receiptNo+' من '+t.fromName+' إلى '+t.toName+'؟'))return;setBusy(true);setError('');setMessage('');try{
  await send('prepare_transfer',{id:t.id,expectedRevision:t.revision});
  setMessage('تم تجهيز النقل وإضافة الكميات إلى مخزن الاستلام وإشعار صاحب الطلب.');await load();onChanged?.();
 }catch(e){setError(e.message||'تعذر تأكيد التجهيز. أعد المحاولة بنفس البيانات.');}finally{setBusy(false);}}
 return <section className="warehouseTransferQueue"><form className="inventoryCard" onSubmit={e=>{e.preventDefault();setOffset(0);if(search===query.trim())load();else setSearch(query.trim());}}>
  <div className="inventorySectionTitle"><AppIcon name="exchange" size={22}/><h3>طلبات نقل المخازن</h3></div>
  {selectedTransfer?<button type="button" className="warehouseClearSearch" onClick={()=>{setQuery('');setSearch('');setState('pending');setOffset(0);onClearSelection?.();}}>عرض طلبات النقل كاملة</button>:<>
   <p className="inventoryHint">الطلبات الخارجة من مخزنك فقط. أكد التجهيز بعد تسليم المواد.</p>
   {inventory.warehouses.length===1?<div className="sourceWarehouseChip"><AppIcon name="warehouse" size={17}/><b>المصدر: {inventory.warehouses[0].name}</b></div>:<WarehouseField inventory={inventory} allowAll label="مخزن المصدر المطلوب تجهيزه"/>}
   <div className="sourceTransferSearch"><input aria-label="بحث طلبات النقل" placeholder="رقم الطلب أو اسم المخزن أو المستخدم" value={query} onChange={e=>setQuery(e.target.value)}/><button type="submit" disabled={loading} className="inventoryPrimary">بحث / تحديث</button></div>
   <nav className="warehouseQueueTabs" aria-label="حالات تجهيز النقل">{[['pending','بانتظار التجهيز'],['posted','تم التجهيز'],['','كل الطلبات']].map(([value,label])=><button type="button" key={label} aria-pressed={state===value} onClick={()=>{setState(value);setOffset(0);}}><span>{label}</span><b>{quantity(result.statusCounts?.[value||'all']||0)}</b></button>)}</nav>
  </>}
 </form>
  {message&&<p role="status" className="workflowSuccess">{message}</p>}{error&&<p role="alert" className="workflowError">{error}</p>}
  {loading&&!result.rows.length?<p role="status" className="inventoryEmpty">جاري تحميل طلبات النقل…</p>:result.rows.map(t=><article key={t.id} className={'inventoryCard sourceTransferOrder'+(t.id===selectedTransfer?' highlighted':'')}><header><div><small>طلب نقل #{t.receiptNo}</small><h3>{t.fromName}</h3><p>إلى {t.toName}</p><small>{warehouseDate(t.date)} · طلبه: {t.actor}</small></div><span className={'inventoryStatus '+t.status}>{transferStatus(t.status)}</span></header>
   <div className="sourceTransferItems">{t.items.map((i,n)=><div key={n}><span><b>{i.name}</b><small>{[i.code,i.brand,i.category].filter(Boolean).join(' · ')}</small></span><strong>{quantity(i.qty)}</strong></div>)}</div>{t.note&&<p className="inventoryHint">{t.note}</p>}{t.preparedBy&&<p className="sourceTransferPrepared">✓ جهّزها {t.preparedBy} · {warehouseDate(t.preparedAt)}</p>}
   {t.canPrepare&&<button className="inventoryPrimary sourceTransferConfirm" disabled={busy} onClick={()=>prepare(t)}><AppIcon name="check" size={18}/>{busy?'جاري تأكيد التجهيز…':'تأكيد تجهيز النقل'}</button>}
   <ReportActions enabled html={a4(t.status==='pending'?'طلب تجهيز نقل مخزني':'وصل نقل مخزني',transferDocument(t,false),'','طلب نقل #'+t.receiptNo)} filename={'نقل-مخزني-'+t.receiptNo}/>
  </article>)}{!loading&&!result.rows.length&&<div className="inventoryEmpty">{state==='pending'?'لا توجد طلبات نقل خارجة من مخزنك بانتظار التجهيز.':'لا توجد طلبات ضمن الاختيار.'}</div>}
  <nav className="archivePagination"><button disabled={offset===0||loading} onClick={()=>setOffset(v=>Math.max(0,v-30))}>السابق</button><span>{Math.floor(offset/30)+1} / {Math.max(1,Math.ceil(result.count/30))}</span><button disabled={offset+30>=result.count||loading} onClick={()=>setOffset(v=>v+30)}>التالي</button></nav>
 </section>;
}
