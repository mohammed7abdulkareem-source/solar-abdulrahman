'use client';
import {useEffect,useRef,useState} from 'react';
import {useWarehouseStatuses} from './warehouse-badge';
import SalesArchiveCard from './sales-archive-card';
import CurrencyInvoice from './currency-invoice';
import SystemInvoiceEditor from './system-invoice-editor';
import {canEditArchivedInvoice,archiveInvoiceDraft} from './invoice-edit-utils.mjs';
import {supabase} from './supabase';
import WarehousePricing from './warehouse-pricing';
import {salesDocument,statusLabel,formatMoney} from './sales-document.mjs';
import {deleteSale} from './delete-sale';
import {receiptQuery,receiptNumber} from './supplier-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {RecordNavigator,RecordViewSwitch,useRecordView} from './record-browser';
import PeriodSales from './period-sales';
import {baghdadDay,recordPage} from './record-browser-utils.mjs';

export default function SalesHistory({profile,customers=[],products=[],staff=[],onUpdateInvoice,a4,openA4,saveA4,shareA4,onFollow,onChanged}){
 const [mode,setMode]=useRecordView(profile.id,'sales',true);
 const [position,setPosition]=useState(0);
 const moved=useRef(false);
 const [editing,setEditing]=useState(null),[editItems,setEditItems]=useState([]),[editSearch,setEditSearch]=useState(''),[deleting,setDeleting]=useState(null),[message,setMessage]=useState('');
 async function remove(row){if(deleting!==null)return;setDeleting(row.id);setError('');setMessage('');try{if(await deleteSale(row.id)){setMessage('تم حذف الفاتورة وإعادة المواد وتصحيح الحساب.');setOffset(0);setPosition(0);setRefresh(n=>n+1);await onChanged?.()}}catch(e){setError(e.message)}finally{setDeleting(null)}}
 const [query,setQuery]=useState(''),[search,setSearch]=useState(''),[kind,setKind]=useState(''),[from,setFrom]=useState(''),[to,setTo]=useState(''),[status,setStatus]=useState(''),[offset,setOffset]=useState(0),[refresh,setRefresh]=useState(0);
 const [result,setResult]=useState({rows:[],count:0}),[loading,setLoading]=useState(true),[error,setError]=useState('');
 useEffect(()=>{let active=true;setError('');if(mode==='period'){setLoading(false);return()=>{active=false;};}setLoading(true);
  supabase.rpc('solar_sales_history',{search_text:search,sale_kind:kind,date_from:from||null,date_to:to||null,job_status:status,page_offset:offset}).then(({data,error})=>{
   if(!active)return;if(error){setError('تعذر تحميل المبيعات. حاول التحديث مرة ثانية.');setResult({rows:[],count:0});}else{setResult(data||{rows:[],count:0});if(offset>0&&offset>=data.count){setOffset(Math.floor(Math.max(0,data.count-1)/30)*30);setPosition(0);}}setLoading(false);
  }).catch(()=>{if(active){setError('تعذر الاتصال. حاول مرة ثانية.');setLoading(false)}});
  return()=>{active=false};
 },[search,kind,from,to,status,offset,refresh,mode]);
 const current=Math.min(position,Math.max(0,result.rows.length-1)),shown=mode==='single'?result.rows.slice(current,current+1):result.rows;
 const move=delta=>{moved.current=true;const next=recordPage(offset+current+delta,result.count);if(next.offset!==offset)setLoading(true);setOffset(next.offset);setPosition(next.index);};
 useEffect(()=>{if(!loading&&moved.current){document.querySelector('.salesArchive .saleHistoryCard')?.scrollIntoView({block:'start'});moved.current=false;}},[position,offset,loading]);
 const preparation=useWarehouseStatuses(result.rows,()=>setRefresh(n=>n+1));
 const change=(setter,value)=>{setter(value);setOffset(0);setPosition(0)};
 const doc=(row,customer)=>{const party=customers.find(c=>row.party_id!=null?String(c.id)===String(row.party_id):c.name===row.party_name);const d=salesDocument({...row,customerPhone:row.customer_phone||row.customerPhone||party?.phone},customer);return a4(d.title,d.body,d.total,d.subtitle)};
 const finishEdit=()=>{setEditing(null);setMessage('تم حفظ تعديل الفاتورة وتصحيح حسابها والمخزون.');setRefresh(n=>n+1);};
 const edit=row=>{if(!canEditArchivedInvoice(profile,row)||!onUpdateInvoice)return;const draft=archiveInvoiceDraft(row);setEditing(draft);setEditItems([]);setEditSearch('');window.scrollTo({top:0,behavior:'instant'});};
 if(editing)return editing.kind==='system'?<SystemInvoiceEditor key={editing.id} original={editing} customers={customers} staff={staff} products={products} onUpdate={onUpdateInvoice} onSaved={finishEdit} onCancel={()=>setEditing(null)} a4={a4}/>:<CurrencyInvoice key={editing.id} kind="sale" contact={{display_name:editing.creatorName,phone:editing.creatorPhone}} products={products} parties={customers} initialInvoice={editing} items={editItems} setItems={setEditItems} search={editSearch} setSearch={setEditSearch} onUpdateInvoice={async(old,changes)=>{const ok=await onUpdateInvoice(old,changes);if(ok)finishEdit();return ok;}} onCancel={()=>setEditing(null)} a4={a4} openA4={openA4} saveA4={saveA4} shareA4={shareA4}/>;
 return <section className="salesArchive"><WarehousePricing profile={profile} onChanged={()=>{setRefresh(n=>n+1);onChanged?.();}}/><p className="archiveCount">{profile?.is_admin?'الإدارة — جميع وصولات المستخدمين':'وصولاتك فقط — بيانات باقي المستخدمين محمية'}</p>
  <form className="card form" onSubmit={e=>{e.preventDefault();const q=normalizeSearch(query);change(setSearch,/^[#\d,٬\s]+$/.test(q)?receiptQuery(q):query.trim());setRefresh(n=>n+1)}}>
   <label>بحث برقم الوصل أو اسم الزبون<input value={query} onChange={e=>setQuery(e.target.value)} placeholder="رقم الوصل / اسم الزبون"/></label>
   <div className="archiveFilters"><label>نوع البيع<select value={kind} onChange={e=>{change(setKind,e.target.value);setStatus('')}}><option value="">الجملة والمنظومات</option><option value="sale">بيع جملة</option><option value="system">بيع منظومات</option></select></label>
   <label>حالة التنصيب<select value={status} disabled={kind==='sale'} onChange={e=>change(setStatus,e.target.value)}><option value="">جميع الحالات</option>{Object.entries(statusLabel).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></label></div>
   <div className="dateRange"><label>من<input type="date" value={from} onChange={e=>change(setFrom,e.target.value)}/></label><label>إلى<input type="date" min={from||undefined} value={to} onChange={e=>change(setTo,e.target.value)}/></label></div>
   <div className="recordDateShortcuts"><button type="button" onClick={()=>{change(setFrom,baghdadDay());setTo(baghdadDay());}}>اليوم</button><button type="button" onClick={()=>{change(setFrom,'');setTo('');}}>كل الفترات</button></div><button disabled={loading}>بحث / تحديث</button>
  </form>
  <RecordViewSwitch allowPeriod mode={mode} onChange={setMode} label="طريقة عرض المبيعات السابقة" disabled={loading}/>{mode==='single'&&<RecordNavigator label="التنقل بين فواتير البيع" index={offset+current} total={result.count} busy={loading||deleting!==null} onPrevious={()=>move(-1)} onNext={()=>move(1)}/>}
  {error&&<div className="workflowError" role="alert">{error}</div>}{message&&<div className="workflowSuccess" role="status">{message}</div>}
  {mode==='period'?<PeriodSales search={search} kind={kind} from={from} to={to} status={status} refresh={refresh} a4={a4}/>:loading?<div className="empty">جاري تحميل المبيعات…</div>:<><p className="archiveCount">{formatMoney(result.count)} فاتورة ضمن صلاحياتك</p>
  {!result.rows.length?<div className="empty">لا توجد مبيعات ضمن هذا الاختيار</div>:shown.map(row=><SalesArchiveCard key={row.id} row={row} profile={profile} warehouseStatus={preparation[row.id]||row.warehouse_status} doc={doc} openA4={openA4} saveA4={saveA4} shareA4={shareA4} onFollow={onFollow} onDelete={remove} deleting={deleting} onEdit={onUpdateInvoice&&canEditArchivedInvoice(profile,row)?edit:undefined} onWarrantyChanged={async()=>{setMessage('تم حفظ الضمان. رمز الوصل نفسه يعرض آخر تحديث.');setRefresh(n=>n+1);await onChanged?.();}}/>)}
  {mode==='list'&&<div className="archivePagination"><button disabled={offset===0} onClick={()=>{setPosition(0);setOffset(Math.max(0,offset-30));}}>السابق</button><span>{Math.floor(offset/30)+1} / {Math.max(1,Math.ceil(result.count/30))}</span><button disabled={offset+30>=result.count} onClick={()=>{setPosition(0);setOffset(offset+30);}}>التالي</button></div>}</>}
 </section>;
}
