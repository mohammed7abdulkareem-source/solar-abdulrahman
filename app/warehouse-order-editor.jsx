'use client';
import {useEffect,useRef,useState} from 'react';
import {useWarehouseInventory} from './warehouse-data';
import {normalizeSearch} from './party-search-utils.mjs';
import {moneyInput} from './supplier-utils.mjs';
import {quantity} from './warehouse-utils.mjs';
import {warehouseCapacity,warehouseEditError,warehouseEditPayload} from './warehouse-edit-utils.mjs';
import AppIcon from './app-icons';

export default function WarehouseOrderEditor({row,onSave,onCancel,onReload,busy}){
 const inventory=useWarehouseInventory({initialWarehouseId:row.warehouseId}),products=inventory.products,booked=row.bookedItems||row.items;
 const [lines,setLines]=useState(()=>row.items.map(i=>({...i}))),[removed,setRemoved]=useState([]),[search,setSearch]=useState(''),[limit,setLimit]=useState(8),[note,setNote]=useState(row.note||''),[error,setError]=useState(''),[stale,setStale]=useState(false);
 const root=useRef(null),focus=useRef(null),lock=useRef(false);
 useEffect(()=>{if(focus.current==null)return;const input=[...root.current.querySelectorAll('[data-material-quantity]')].find(e=>e.dataset.materialQuantity===String(focus.current));input?.focus();input?.select();focus.current=null;},[lines]);
 const words=normalizeSearch(search).split(/\s+/).filter(Boolean),matches=products.filter(p=>Number(p.qty)>0&&words.every(w=>normalizeSearch([p.name,p.brand,p.category,p.code].join(' ')).includes(w)));
 function add(p){const found=lines.find(i=>String(i.productId)===String(p.id));focus.current=p.id;if(found){setLines(v=>[...v]);return;}
  const restore=removed.find(i=>String(i.productId)===String(p.id));setRemoved(v=>v.filter(i=>i!==restore));setLines(v=>[restore||{lineId:null,productId:p.id,name:p.name,brand:p.brand,category:p.category,qty:''},...v]);setSearch('');setError('');}
 async function save(e){e.preventDefault();if(lock.current||busy)return;const invalid=warehouseEditError(lines,products,booked);if(invalid){setError(invalid);return;}
  const deleted=row.items.filter(i=>i.lineId!=null&&!lines.some(x=>String(x.lineId)===String(i.lineId)));
  if(deleted.length&&!confirm('سيُحذف من الوصل: '+deleted.map(i=>i.name).join('، ')+'\nسيُحفظ الوصل بـ '+lines.length+' فقرة. تأكيد؟'))return;
  lock.current=true;setError('');try{const result=await onSave(warehouseEditPayload(lines),note);if(result?.ok===false){setError(result.error);setStale(result.stale);}}finally{lock.current=false;}
 }
 return <form ref={root} className="warehouseEditor warehouseMaterialEditor" onSubmit={save}><header><h4>تعديل جميع مواد الوصل #{row.receiptNo}</h4><small>{row.warehouseName}</small></header>
  <fieldset disabled={busy}><section className="warehouseMaterialPicker"><label>إضافة فقرة للوصل<div className="warehouseMaterialSearch"><AppIcon name="search" size={17}/><input aria-label="بحث لإضافة مادة للوصل" value={search} onChange={e=>{setSearch(e.target.value);setLimit(8);}} placeholder="اسم المادة أو الكود أو البراند…"/></div></label>
   {inventory.loading?<p role="status">جاري تحميل المواد المتوفرة…</p>:inventory.error?<p role="alert">{inventory.error}<button type="button" onClick={inventory.refresh}>إعادة التحميل</button></p>:<><div className="warehouseMaterialMatches">{matches.slice(0,limit).map(p=><button type="button" key={p.id} onClick={()=>add(p)} aria-label={'إضافة '+p.name}><span><b dir="auto">{p.name}</b><small>{[p.brand,p.category,p.code].filter(Boolean).join(' · ')} · المتوفر {quantity(p.qty)}</small></span><AppIcon name={lines.some(i=>String(i.productId)===String(p.id))?'edit':'add'} size={17}/></button>)}{!matches.length&&<p>لا توجد مواد متوفرة مطابقة في هذا المخزن.</p>}</div>{matches.length>limit&&<button type="button" onClick={()=>setLimit(n=>n+8)}>عرض مواد أكثر</button>}</>}
  </section>
  <div className="warehouseFinalHeading"><b>فقرات الوصل بعد التعديل</b><span>{lines.length} فقرة</span></div>
  <div className="warehouseFinalLines">{lines.map((i,n)=><article key={i.lineId??'new-'+i.productId}><div className="warehouseMaterialIdentity"><span className="warehouseLineIndex">{n+1}</span><div><b dir="auto">{i.name}</b><small>{[i.brand,i.category].filter(Boolean).join(' · ')}</small>{i.lineId==null&&<em>{row.kind==='sale'?'مضافة · تسعّرها الإدارة':'فقرة مضافة'}</em>}</div></div><div className="warehouseMaterialQuantity"><label>الكمية<input data-material-quantity={i.productId} aria-label={'عدد '+i.name} dir="ltr" inputMode="decimal" autoComplete="off" required value={i.qty} onChange={e=>{const qty=moneyInput(e.target.value);if(/^\d*(?:\.\d{0,3})?$/.test(qty))setLines(v=>v.map((x,index)=>index===n?{...x,qty}:x));}}/></label><small>المتاح لهذا الوصل: {quantity(warehouseCapacity(products,booked,i.productId))}</small><button type="button" aria-label={'حذف '+i.name} onClick={()=>{setRemoved(v=>[...v,i]);setLines(v=>v.filter((_,index)=>index!==n));}}><AppIcon name="trash" size={16}/>حذف</button></div></article>)}</div>
  {!!removed.length&&<div className="warehouseRemovedLines"><b>فقرات محذوفة من التعديل</b>{removed.map((i,n)=><div key={n}><span>{i.name}</span><button type="button" onClick={()=>{focus.current=i.productId;setLines(v=>[i,...v]);setRemoved(v=>v.filter(x=>x!==i));}}>تراجع عن الحذف</button></div>)}</div>}
  <label>ملاحظة التجهيز (اختياري)<textarea value={note} onChange={e=>setNote(e.target.value)} maxLength={2000}/></label>
  <div className="warehouseEditSummary"><span>قبل التعديل: {row.items.length} فقرة</span><b>بعد التعديل: {lines.length} فقرة · {quantity(lines.reduce((n,i)=>n+Number(i.qty||0),0))} مجموع الكميات</b></div>
  <p className="warehouseHint">{row.kind==='sale'?'المواد الجديدة تُرسل للإدارة لتحديد أسعارها، ثم تكمل تجهيز الوصل.':'بعد حفظ التعديلات، جهّز جميع الفقرات واضغط «تم التجهيز».'}</p>
  {error&&<p className="workflowError" role="alert">{error}</p>}{stale&&onReload&&<button type="button" onClick={async()=>{try{await onReload();}catch{setError('تعذر تحميل أحدث نسخة؛ أعد المحاولة.');}}}>إلغاء تعديلاتي وتحميل أحدث نسخة</button>}
  <div className="warehouseActions"><button disabled={busy||!inventory.ready||!lines.length}>{busy?'جاري حفظ الفقرات…':'حفظ '+lines.length+' فقرة'}</button><button type="button" onClick={onCancel} disabled={busy}>إلغاء</button></div>
  </fieldset>
 </form>;
}
