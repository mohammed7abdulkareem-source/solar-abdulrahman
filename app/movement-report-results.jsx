'use client';
import {useEffect,useMemo,useRef,useState} from 'react';
import AppIcon from './app-icons';
import ReportActions from './report-actions';
import {inventoryCall} from './warehouse-data';
import {normalizeSearch} from './party-search-utils.mjs';
import {materialQuantity as quantity,materialVisibleTotals} from './material-movement-utils.mjs';
import {escapeHtml,movementDocument,movementLabel,warehouseDate} from './warehouse-utils.mjs';

export default function MovementReportResults({mode,filters,a4,onEdit}){
 const [data,setData]=useState(null),[error,setError]=useState(''),[retry,setRetry]=useState(0),[page,setPage]=useState(0);
 const customer=mode==='customer',heading=useRef(null);
 useEffect(()=>{heading.current?.focus();},[]);
 useEffect(()=>{
  let live=true;
  inventoryCall('movements',filters.payload).then(rows=>{
   if(!live)return;
   if(!Array.isArray(rows)||rows.some(r=>filters.warehouse&&String(r.warehouseId)!==filters.warehouse||
     customer&&(String(r.productId)!==filters.product||r.customerKey!==filters.customer||!['sale','system'].includes(r.kind))))
    throw new Error('تعذر التحقق من تطابق النتائج مع معايير الكشف.');
   setData(rows);
  }).catch(err=>{if(live)setError(err.message||'تعذر تحميل الحركات.');});
  return()=>{live=false;};
 },[filters,customer,retry]);
 const shown=useMemo(()=>{
  if(!data)return [];
  const words=normalizeSearch(filters.query).replace(/#/g,'').split(/\s+/).filter(Boolean);
  return data.filter(r=>{
   if(filters.direction==='in'&&!(Number(r.inQty)>0)||filters.direction==='out'&&!(Number(r.outQty)>0))return false;
   const text=normalizeSearch([r.name,r.brand,r.category,r.warehouseName,r.receiptNo,r.party,r.note,movementLabel[r.kind]].filter(Boolean).join(' '));
   return words.every(word=>text.includes(word));
  });
 },[data,filters]);
 const period=filters.from||filters.to?(filters.from||'البداية')+' — '+(filters.to||'اليوم'):'كل الفترات';
 const title=customer?'كشف حركة مادة وعميل':'سجل جميع حركات المواد';
 const totals=useMemo(()=>customer?materialVisibleTotals(shown):{
  in:shown.filter(row=>Number(row.inQty)>0).length,
  out:shown.filter(row=>Number(row.outQty)>0).length
 },[shown,customer]);
 const html=useMemo(()=>{
  if(!data)return '';
  const context=[filters.productLabel,filters.customerLabel,filters.warehouseLabel,period,customer?'':filters.directionLabel,filters.query].filter(Boolean);
  const body='<div class="meta">'+context.map(text=>'<div>'+escapeHtml(text)+'</div>').join('')+'</div>'+
   movementDocument(shown,{formatQuantity:quantity,totals,countMovements:!customer});
  return a4(title,body,'','كشف كميات');
 },[data,a4,shown,title,filters,period,customer,totals]);
 const pageSize=30,pages=Math.max(1,Math.ceil(shown.length/pageSize)),visible=shown.slice(page*pageSize,(page+1)*pageSize);
 function refresh(){setData(null);setError('');setPage(0);setRetry(n=>n+1);}
 return <section className="movementReportResults movementResults" aria-label="حركات المواد" aria-busy={!data&&!error}>
  <header className="movementReportSummary"><div><h2 ref={heading} tabIndex={-1}>{customer?filters.productLabel:filters.warehouseLabel}</h2><p>{customer?filters.customerLabel+' · ':''}{period}</p></div>
   <button type="button" className="movementReportEdit" onClick={onEdit}><AppIcon name="settings" size={16}/>تعديل معايير الكشف</button></header>
  <div className="movementReportContext">{customer&&<span>{filters.warehouseLabel}</span>}{!customer&&<span>{filters.directionLabel}</span>}{filters.query&&<span>البحث · {filters.query}</span>}</div>
  {error?<div className="movementError" role="alert">{error} <button type="button" onClick={refresh}>إعادة المحاولة</button></div>:
   !data?<div className="movementEmpty" role="status">جاري تحميل كشف الحركة…</div>:<>
    <div className="movementTotals"><div>عدد الحركات<b>{quantity(shown.length)}</b></div><div><span className="movementDot out"/>{customer?'الكمية الخارجة للعميل':'حركات الخروج'}<b>{quantity(totals.out)}</b></div>
     <div><span className="movementDot in"/>{customer?'الكمية الراجعة من العميل':'حركات الدخول'}<b>{quantity(totals.in)}</b></div></div>
    <div className="movementReportActions"><ReportActions enabled showPrint html={html} filename={customer?title+'-'+filters.productLabel+'-'+filters.customerLabel:title}/></div>
    {!shown.length?<div className="movementEmpty" role="status"><AppIcon name="search"/><b>لا توجد حركات مطابقة لمعايير الكشف</b></div>:
     <div className="movementTable"><div className="movementTableHead"><span>المادة / المخزن</span><span>المستند / التاريخ</span><span>دخول</span><span>خروج</span><span>رصيد المخزن بعد الحركة</span></div>
      {visible.map(r=><article className="movementEntry" key={r.id} data-movement-id={r.id} data-product-id={r.productId}>
       <div className="movementMaterial"><b dir="auto">{r.name}</b><small>{[r.warehouseName,r.brand,r.category].filter(Boolean).join(' · ')}</small>{r.party&&<span>{r.party}</span>}</div>
       <div className="movementDoc"><span className={'movementBadge '+(r.kind==='stock_adjustment'?'adjust':Number(r.inQty)>0?'in':'out')}>{movementLabel[r.kind]||r.kind}{r.receiptNo!=null&&<bdi> #{r.receiptNo}</bdi>}</span><time dateTime={r.date}>{warehouseDate(r.date)}</time></div>
       <div className="movementAmount"><small>دخول</small><b>{quantity(r.inQty)}</b></div><div className="movementAmount"><small>خروج</small><b>{quantity(r.outQty)}</b></div>
       <div className="movementAmount movementBalance"><small>رصيد المخزن بعد الحركة</small><b>{quantity(r.balance)}</b></div>
       {r.note&&<p className="movementNote">{r.note}</p>}
      </article>)}
     </div>}
    {pages>1&&<nav className="movementPagination" aria-label="صفحات الحركات"><button type="button" disabled={!page} onClick={()=>setPage(n=>n-1)}>السابق</button><span>{page+1} / {pages}</span><button type="button" disabled={page+1>=pages} onClick={()=>setPage(n=>n+1)}>التالي</button></nav>}
    <footer className="movementReportFooter"><p>الرصيد بعد كل حركة يخص المادة في مخزنها. يشمل التصدير جميع صفحات الكشف.</p><button className="movementRefresh" type="button" onClick={refresh}><AppIcon name="refresh" size={16}/>تحديث الكشف</button></footer>
   </>}
 </section>;
}
