'use client';
import {useEffect,useState} from 'react';
import {supabase} from './supabase';
import {salesDocument,statusLabel,formatMoney} from './sales-document.mjs';
import {deleteSale} from './delete-sale';
import {receiptQuery,receiptNumber} from './supplier-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';

export default function SalesHistory({a4,openA4,saveA4,shareA4,onFollow,onChanged}){
 const [deleting,setDeleting]=useState(null),[message,setMessage]=useState('');
 async function remove(row){if(deleting!==null)return;setDeleting(row.id);setError('');setMessage('');try{if(await deleteSale(row.id)){setMessage('تم حذف الفاتورة وإعادة المواد وتصحيح الحساب.');setOffset(0);setRefresh(n=>n+1);await onChanged?.()}}catch(e){setError(e.message)}finally{setDeleting(null)}}
 const [query,setQuery]=useState(''),[search,setSearch]=useState(''),[kind,setKind]=useState(''),[from,setFrom]=useState(''),[to,setTo]=useState(''),[status,setStatus]=useState(''),[offset,setOffset]=useState(0),[refresh,setRefresh]=useState(0);
 const [result,setResult]=useState({rows:[],count:0}),[loading,setLoading]=useState(true),[error,setError]=useState('');
 useEffect(()=>{let active=true;setLoading(true);setError('');
  supabase.rpc('solar_sales_history',{search_text:search,sale_kind:kind,date_from:from||null,date_to:to||null,job_status:status,page_offset:offset}).then(({data,error})=>{
   if(!active)return;if(error){setError('تعذر تحميل المبيعات. حاول التحديث مرة ثانية.');setResult({rows:[],count:0});}else setResult(data||{rows:[],count:0});setLoading(false);
  }).catch(()=>{if(active){setError('تعذر الاتصال. حاول مرة ثانية.');setLoading(false)}});
  return()=>{active=false};
 },[search,kind,from,to,status,offset,refresh]);
 const change=(setter,value)=>{setter(value);setOffset(0)};
 const doc=(row,customer)=>{const d=salesDocument(row,customer);return a4(d.title,d.body,d.total,d.subtitle)};
 return <section className="salesArchive">
  <form className="card form" onSubmit={e=>{e.preventDefault();const q=normalizeSearch(query);change(setSearch,/^[#\d,٬\s]+$/.test(q)?receiptQuery(q):query.trim());setRefresh(n=>n+1)}}>
   <label>بحث برقم الوصل أو اسم الزبون<input value={query} onChange={e=>setQuery(e.target.value)} placeholder="رقم الوصل / اسم الزبون"/></label>
   <div className="archiveFilters"><label>نوع البيع<select value={kind} onChange={e=>{change(setKind,e.target.value);setStatus('')}}><option value="">الجملة والمنظومات</option><option value="sale">بيع جملة</option><option value="system">بيع منظومات</option></select></label>
   <label>حالة التنصيب<select value={status} disabled={kind==='sale'} onChange={e=>change(setStatus,e.target.value)}><option value="">جميع الحالات</option>{Object.entries(statusLabel).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></label></div>
   <div className="dateRange"><label>من<input type="date" value={from} onChange={e=>change(setFrom,e.target.value)}/></label><label>إلى<input type="date" min={from||undefined} value={to} onChange={e=>change(setTo,e.target.value)}/></label></div>
   <button disabled={loading}>بحث / تحديث</button>
  </form>
  {error&&<div className="workflowError" role="alert">{error}</div>}{message&&<div className="workflowSuccess" role="status">{message}</div>}
  {loading?<div className="empty">جاري تحميل المبيعات…</div>:<><p className="archiveCount">{formatMoney(result.count)} فاتورة ضمن صلاحياتك</p>
  {!result.rows.length?<div className="empty">لا توجد مبيعات ضمن هذا الاختيار</div>:result.rows.map(row=><article className="card archiveInvoice" key={row.id}>
   <header><div><small>{row.kind==='system'?'بيع منظومة':'بيع جملة'} · #{receiptNumber(row)}</small><h3>{row.party_name||'زبون نقدي'}</h3><small>{new Date(row.created_at).toLocaleDateString('ar-IQ',{timeZone:'Asia/Baghdad'})} · {row.creatorName||'—'}</small></div><b>{formatMoney(row.total)} د.ع</b></header>
   {row.kind==='system'&&<p className="archiveStatus">{statusLabel[row.installation_status]||'غير محدد'} · المهندس: {row.installerName||'غير محدد'}</p>}
   <details><summary>تفاصيل المواد ({row.items.length})</summary>{row.items.map((item,i)=><div className="archiveLine" key={i}><span>{item.product_name}<small>{[item.brand_name,item.category].filter(Boolean).join(' · ')}</small></span><b>× {formatMoney(item.qty)}</b></div>)}</details>
   <div className="receiptCopies"><button onClick={()=>openA4(doc(row,true))}>معاينة وصل الزبون</button><button onClick={()=>openA4(doc(row,false))}>معاينة الوصل المخزني</button><button onClick={()=>saveA4(doc(row,true),'وصل-زبون-'+receiptNumber(row))}>حفظ PDF / طباعة الزبون</button><button onClick={()=>saveA4(doc(row,false),'وصل-مخزني-'+receiptNumber(row))}>حفظ PDF / طباعة المخزن</button><button onClick={()=>shareA4('وصل-زبون-'+receiptNumber(row),'فاتورة '+receiptNumber(row)+' - '+(row.party_name||'زبون نقدي'),doc(row,true))}>مشاركة PDF الزبون</button><button onClick={()=>shareA4('وصل-مخزني-'+receiptNumber(row),'وصل مخزني '+receiptNumber(row),doc(row,false))}>مشاركة PDF المخزن</button></div>
   {row.kind==='system'&&onFollow&&<button className="workflowSecondary archiveFollow" onClick={()=>onFollow(String(row.id))}>متابعة ملف التنصيب</button>}
   {row.canDelete&&<button className="dangerMini archiveDelete" disabled={deleting!==null} onClick={()=>remove(row)}>{deleting===row.id?'جاري مراجعة الحذف…':'حذف الوصل'}</button>}
  </article>)}
  <div className="archivePagination"><button disabled={offset===0} onClick={()=>setOffset(Math.max(0,offset-30))}>السابق</button><span>{Math.floor(offset/30)+1} / {Math.max(1,Math.ceil(result.count/30))}</span><button disabled={offset+30>=result.count} onClick={()=>setOffset(offset+30)}>التالي</button></div></>}
 </section>;
}
