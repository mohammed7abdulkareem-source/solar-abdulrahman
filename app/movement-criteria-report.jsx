'use client';
import {useEffect,useRef,useState} from 'react';
import AppIcon from './app-icons';
import CustomerPicker from './customer-picker';
import MaterialMovementPicker from './material-movement-picker';
import {inventoryCall} from './warehouse-data';
import {baghdadDay} from './record-browser-utils.mjs';
import MovementReportResults from './movement-report-results';

const initial={warehouse:'',product:'',customer:'',direction:'all',query:'',from:'',to:''};
const periods=[['today','اليوم'],['week','٧ أيام'],['month','هذا الشهر'],['all','كل الفترات']];
const directions={all:'جميع الاتجاهات',in:'دخول',out:'خروج'};
function movementPayload(filters){
 return {productId:filters.product?Number(filters.product):null,warehouseId:filters.warehouse?Number(filters.warehouse):null,
  from:filters.from||null,to:filters.to||null};
}
function datesFor(preset){
 if(preset==='all')return {from:'',to:''};
 const today=baghdadDay();
 if(preset==='month')return {from:today.slice(0,8)+'01',to:today};
 const date=new Date(today+'T12:00:00Z');
 if(preset==='week')date.setUTCDate(date.getUTCDate()-6);
 return {from:date.toISOString().slice(0,10),to:today};
}
export default function MovementCriteriaReport({mode,inventory,a4}){
 const isCustomer=mode==='customer';
 const form=useRef(null),editing=useRef(false);
 const [draft,setDraft]=useState(initial),[applied,setApplied]=useState(null),[search,setSearch]=useState(''),[preset,setPreset]=useState('all');
 const [directory,setDirectory]=useState(null),[retry,setRetry]=useState(0);
 const invalid=!!(draft.from&&draft.to&&draft.from>draft.to);
 const directoryKey=isCustomer&&draft.product&&!invalid?JSON.stringify(movementPayload(draft)):'';
 useEffect(()=>{if(!applied&&editing.current){editing.current=false;form.current?.focus();}},[applied]);
 const knownDirectory=directoryKey&&directory?.key===directoryKey?directory:null;
 const product=inventory.products.find(p=>String(p.id)===draft.product);
 const customer=knownDirectory?.rows?.find(c=>c.id===draft.customer);
 const selectedWarehouse=inventory.warehouses.find(w=>String(w.id)===draft.warehouse);
 useEffect(()=>{
  if(!directoryKey)return;
  let live=true;
  inventoryCall('movement_customers',JSON.parse(directoryKey)).then(rows=>{
   if(!live)return;
   if(!Array.isArray(rows)||rows.some(row=>!row.name||!row.key))throw new Error('تعذر التحقق من دليل العملاء.');
   setDirectory({key:directoryKey,rows:rows.map(row=>({id:row.key,name:row.name,hint:row.hint||''}))});
  }).catch(err=>{if(live)setDirectory({key:directoryKey,error:err.message||'تعذر تحميل العملاء.'});});
  return()=>{live=false;};
 },[directoryKey,retry]);
 const changeScope=fields=>setDraft(current=>({...current,...fields,customer:''}));
 const canSubmit=!invalid&&inventory.ready&&(!isCustomer||!!(product&&customer));
 function submit(event){
  event.preventDefault();if(!canSubmit)return;
  setApplied({...draft,payload:{...movementPayload(draft),...(isCustomer?{customerKey:customer.id}:{})},directionLabel:directions[draft.direction],
   productLabel:product?[product.name,product.brand,product.code].filter(Boolean).join(' · '):'',
   customerLabel:customer?[customer.name,customer.hint].filter(Boolean).join(' · '):'',
   warehouseLabel:selectedWarehouse?.name||'جميع المخازن المسموحة'});
 }
 if(applied)return <MovementReportResults mode={mode} filters={applied} a4={a4} onEdit={()=>{editing.current=true;setApplied(null);}}/>;
 return <form ref={form} tabIndex={-1} className="movementFilters movementReportCriteria" aria-label="معايير الكشف" onSubmit={submit}>
  {isCustomer&&<>
   <MaterialMovementPicker products={inventory.products} selectedId={draft.product} query={search} onQuery={text=>{setSearch(text);changeScope({product:''});}}
    onSelect={p=>{if(inventory.ready){changeScope({product:String(p.id)});setSearch('');}}} onClear={()=>{setSearch('');changeScope({product:''});}} loading={inventory.loading}/>
   {draft.product&&!invalid&&<div className="movementReportCustomer">{knownDirectory?.error?<div role="alert">{knownDirectory.error} <button type="button" onClick={()=>{setDirectory(null);setRetry(n=>n+1);}}>إعادة المحاولة</button></div>:
    knownDirectory?.rows?.length===0?<p role="status">لا توجد حركات عميل مسجّل لهذه المادة ضمن المخزن والفترة المحددين.</p>:
    <CustomerPicker key={directoryKey} rows={knownDirectory?.rows||[]} loading={!knownDirectory} value={draft.customer}
     onChange={customer=>setDraft(current=>({...current,customer}))} placeholder="اكتب اسم العميل…"/>}{customer?.hint&&<small>{customer.hint}</small>}</div>}
  </>}
  <div className="movementReportFilterGrid">
   <label>المخزن<select aria-label="مخزن حركة المواد" value={draft.warehouse} onChange={e=>changeScope({warehouse:e.target.value})}>
    <option value="">جميع المخازن المسموحة</option>{inventory.warehouses.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select></label>
   {!isCustomer&&<label>اتجاه الحركة<select aria-label="اتجاه الحركة" value={draft.direction} onChange={e=>setDraft({...draft,direction:e.target.value})}>
    {Object.entries(directions).map(([key,text])=><option key={key} value={key}>{text}</option>)}</select></label>}
  </div>
  <div className="movementReportDates">
   <div className="movementChips movementPeriods" aria-label="الفترة السريعة">{periods.map(([key,label])=><button key={key} type="button" aria-pressed={preset===key} onClick={()=>{setPreset(key);changeScope(datesFor(key));}}>{label}</button>)}</div>
   <div className="movementDates"><label>من تاريخ<input aria-label="من تاريخ" type="date" value={draft.from} max={draft.to||undefined} onChange={e=>{setPreset('');changeScope({from:e.target.value});}}/></label>
    <label>إلى تاريخ<input aria-label="إلى تاريخ" type="date" value={draft.to} min={draft.from||undefined} onChange={e=>{setPreset('');changeScope({to:e.target.value});}}/></label></div>
  </div>
  {!isCustomer&&<label className="movementSearch">بحث بالمستند أو الطرف <div><AppIcon name="search" size={18}/><input aria-label="بحث المستند أو الطرف" value={draft.query}
   onChange={e=>setDraft({...draft,query:e.target.value})} placeholder="رقم الوصل أو اسم الطرف أو المادة"/></div></label>}
  {invalid&&<p className="movementError" role="alert">تاريخ النهاية يسبق تاريخ البداية.</p>}
  {inventory.error&&<p className="movementError" role="alert">{inventory.error} <button type="button" onClick={inventory.refresh}>إعادة التحميل</button></p>}
  <button type="submit" className="movementSubmit" disabled={!canSubmit}><AppIcon name="document" size={18}/>عرض الكشف</button>
 </form>;
}
