'use client';
import {useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import {RecordNavigator,RecordViewSwitch,useRecordView} from './record-browser';
import {baghdadDay,canReadPaymentKind,paymentKinds,recordPage} from './record-browser-utils.mjs';
import {money,receiptQuery,supplierDocument} from './supplier-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {systemPaymentDocument} from './system-payment-utils.mjs';
import {currencyLabel} from './fx-utils.mjs';
import ReportActions from './report-actions';
import PhoneActions from './phone-actions';
import AppIcon from './app-icons';

function PaymentReceipt({row,a4}){
 const [data,setData]=useState(null),[error,setError]=useState(''),[retry,setRetry]=useState(0);
 useEffect(()=>{let live=true;const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),12000);setData(null);setError('');
  supabase.rpc('solar_payment_history',{action:'get',payload:{id:row.id}}).abortSignal(controller.signal).then(({data,error})=>{if(error)throw error;if(!data?.receipt)throw new Error('الوصل غير متاح');if(live)setData(data);}).catch(e=>{if(live)setError(e.code?e.message:'تعذر تحميل الوصل. أعد المحاولة.');}).finally(()=>clearTimeout(timer));
  return()=>{live=false;clearTimeout(timer);controller.abort();};
 },[row.id,retry]);
 if(error)return <p className="workflowError" role="alert">{error}<button type="button" onClick={()=>setRetry(n=>n+1)}>إعادة المحاولة</button></p>;
 if(!data)return <p role="status">جاري تحميل الوصل الأصلي…</p>;
 const receipt=data.receipt,doc=data.type==='supplier'?supplierDocument(receipt):systemPaymentDocument(receipt);
 return <div className="paymentArchiveDetail" aria-label="تفاصيل وصل التسديد">{data.type==='customer'&&<dl className="paymentArchiveBalances"><div><dt>الحساب السابق</dt><dd><bdi>{money(receipt.oldBalance)} د.ع</bdi></dd></div><div><dt>الحساب بعد التسديد</dt><dd><bdi>{money(receipt.remaining)} د.ع</bdi></dd></div>{receipt.invoice&&<div><dt>المنظومة المرتبطة</dt><dd>#{receipt.invoice.receiptNo}</dd></div>}</dl>}<ReportActions enabled html={a4(doc.title,doc.body,doc.total,doc.subtitle)} filename={'تسديد-'+row.kind+'-'+row.receiptNo}/></div>;
}
export default function PaymentHistory({profile,a4,onChanged}){
 const [mode,setMode]=useRecordView(profile.id,'payments'),[query,setQuery]=useState(''),[search,setSearch]=useState(''),[kind,setKind]=useState(''),[from,setFrom]=useState(''),[to,setTo]=useState(''),[offset,setOffset]=useState(0),[position,setPosition]=useState(0),[refresh,setRefresh]=useState(0),[expanded,setExpanded]=useState(null);
 const [result,setResult]=useState({rows:[],count:0}),[loading,setLoading]=useState(true),[error,setError]=useState('');
 const moved=useRef(false);
 const invalid=!!from&&!!to&&from>to;
 useEffect(()=>{let live=true;const controller=new AbortController();setLoading(true);setError('');setExpanded(null);
  if(invalid){setResult({rows:[],count:0});setLoading(false);return()=>{live=false;};}
  supabase.rpc('solar_payment_history',{action:'list',payload:{query:search,kind,from:from||null,to:to||null,offset}}).abortSignal(controller.signal).then(({data,error})=>{if(!live)return;if(error)throw error;setResult(data);if(offset>0&&offset>=data.count){setOffset(Math.floor(Math.max(0,data.count-1)/30)*30);setPosition(0);}}).catch(e=>{if(live){setError(e.message||'تعذر تحميل التسديدات.');setResult({rows:[],count:0});}}).finally(()=>{if(live)setLoading(false);});
  return()=>{live=false;controller.abort();};
 },[search,kind,from,to,offset,refresh,invalid]);
 const current=Math.min(position,Math.max(0,result.rows.length-1)),rows=mode==='single'?result.rows.slice(current,current+1):result.rows;
 const change=(setter,value)=>{setter(value);setOffset(0);setPosition(0);setExpanded(null);};
 const move=delta=>{moved.current=true;const next=recordPage(offset+current+delta,result.count);if(next.offset!==offset)setLoading(true);setOffset(next.offset);setPosition(next.index);setExpanded(null);};
 useEffect(()=>{if(!loading&&moved.current){document.querySelector('.paymentHistoryArchive .paymentArchiveCard')?.scrollIntoView({block:'start'});moved.current=false;}},[position,offset,loading]);
 return <section className="paymentHistoryArchive"><p className="archiveCount">{profile.is_admin?'الإدارة — تسديدات جميع المستخدمين':'تسديداتك فقط — ضمن صلاحياتك'}</p><form className="card form" onSubmit={e=>{e.preventDefault();const q=normalizeSearch(query);change(setSearch,/^[#\d,٬\s]+$/.test(q)?receiptQuery(q):query.trim());setRefresh(n=>n+1);}}><label>بحث برقم الوصل أو الاسم<input aria-label="بحث التسديدات السابقة" value={query} onChange={e=>setQuery(e.target.value)} placeholder="رقم الوصل / الزبون أو المورد"/></label><label>نوع التسديد<select aria-label="نوع التسديد السابق" value={kind} onChange={e=>change(setKind,e.target.value)}><option value="">جميع الأنواع المسموحة</option>{paymentKinds.filter(([id])=>canReadPaymentKind(profile,id)).map(([id,label])=><option key={id} value={id}>{label}</option>)}</select></label><div className="dateRange"><label>من<input aria-label="بداية فترة التسديدات" type="date" value={from} max={to||undefined} onChange={e=>change(setFrom,e.target.value)}/></label><label>إلى<input aria-label="نهاية فترة التسديدات" type="date" value={to} min={from||undefined} onChange={e=>change(setTo,e.target.value)}/></label></div><div className="recordDateShortcuts"><button type="button" aria-pressed={from===baghdadDay()&&to===baghdadDay()} onClick={()=>{change(setFrom,baghdadDay());setTo(baghdadDay());}}>اليوم</button><button type="button" aria-pressed={!from&&!to} onClick={()=>{change(setFrom,'');setTo('');}}>كل الفترات</button></div>{invalid&&<p className="workflowError" role="alert">تاريخ البداية يجب أن يسبق تاريخ النهاية.</p>}<button disabled={loading||invalid}>بحث / تحديث</button></form>
  <RecordViewSwitch label="طريقة عرض التسديدات السابقة" mode={mode} onChange={setMode} disabled={loading}/>{mode==='single'&&<RecordNavigator label="التنقل بين التسديدات" index={offset+current} total={result.count} busy={loading} onPrevious={()=>move(-1)} onNext={()=>move(1)}/>}
  {error&&<p className="workflowError" role="alert">{error}</p>}{loading?<p role="status" className="empty">جاري تحميل التسديدات…</p>:<><p className="paymentHistoryTotal">{result.count} وصل تسديد ضمن الاختيارات</p>{rows.map(row=>{const isSupplier=row.kind==='supplier_payment',open=mode==='single'||expanded===row.id;return <article className={'paymentArchiveCard'+(isSupplier?' supplier':'')} key={row.id}><header><span className="paymentArchiveKind"><AppIcon name="receipt" size={16}/>{paymentKinds.find(([id])=>id===row.kind)?.[1]}</span><bdi>#{row.receiptNo}</bdi></header><h3>{row.party}</h3><div className="paymentArchiveMeta"><span>{new Date(row.date).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'})}</span><span>{row.creatorName}</span></div><div className="paymentArchiveTotal"><span>{isSupplier?'المدفوع للمورد':'المستلم من الزبون'}</span><strong><bdi>{money(row.amount,row.currency)}</bdi> <small>{currencyLabel(row.currency)}</small></strong></div>{row.notes&&<p className="paymentArchiveNotes">{row.notes}</p>}{row.creatorPhone&&<div className="paymentArchiveContact"><span>مسؤول الوصل</span><PhoneActions phone={row.creatorPhone} label={row.creatorName}/></div>}{mode==='list'&&<button type="button" className="paymentArchiveOpen" aria-expanded={open} onClick={()=>setExpanded(open?null:row.id)}><AppIcon name="chevron" size={15}/>{open?'إغلاق الوصل':'تفاصيل الوصل والمعاينة'}</button>}{open&&<PaymentReceipt row={row} a4={a4}/>}</article>})}{!rows.length&&!error&&<p className="empty">لا توجد تسديدات ضمن هذا الاختيار.</p>}{mode==='list'&&(offset>0||result.count>30)&&<div className="archivePagination"><button type="button" disabled={!offset} onClick={()=>{setPosition(0);setOffset(n=>Math.max(0,n-30));}}>السابق</button><span>{Math.floor(offset/30)+1} / {Math.max(1,Math.ceil(result.count/30))}</span><button type="button" disabled={offset+30>=result.count} onClick={()=>{setPosition(0);setOffset(n=>n+30);}}>التالي</button></div>}</>}
 </section>;
}
