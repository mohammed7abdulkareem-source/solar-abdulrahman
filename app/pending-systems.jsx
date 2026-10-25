'use client';
import {useEffect,useState} from 'react';
import {supabase} from './supabase';
import AppIcon from './app-icons';
import ReportActions from './report-actions';
import {formatMoney as money} from './money-format.mjs';
import {statusLabel} from './sales-document.mjs';
import {pendingSystemsDocument} from './pending-systems-report.mjs';
export default function PendingSystems({ownerId=null,from='',to='',revision,a4}){
 const [loaded,setLoaded]=useState(null),[loading,setLoading]=useState(true),[error,setError]=useState(''),[retry,setRetry]=useState(0),[expanded,setExpanded]=useState(false);
 const key=JSON.stringify([ownerId,from,to]);
 useEffect(()=>{let live=true;const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),12000);setLoading(true);setError('');
  supabase.rpc('solar_pending_systems',{owner_id:ownerId,date_from:from||null,date_to:to||null}).abortSignal(controller.signal).then(({data,error})=>{if(error)throw error;if(live)setLoaded({key,data});}).catch(()=>{if(live)setError('تعذر تحميل المنظومات غير المغلقة.');}).finally(()=>{clearTimeout(timer);if(live)setLoading(false);});
  return()=>{live=false;clearTimeout(timer);controller.abort();};
 },[ownerId,from,to,revision,retry,key]);
 const ready=loaded?.key===key&&!loading&&!error,data=ready?loaded.data:null,s=data?.summary;
 const doc=data&&expanded?pendingSystemsDocument(data):null;
 return <section className="pendingSystems" aria-label="المنظومات غير المغلقة"><header><div><h2>المنظومات غير المغلقة</h2><p>{s?s.count+' ملف غير مغلق':'كشف المبالغ والأرباح غير النهائية'}</p></div><button type="button" disabled={loading} onClick={()=>setRetry(n=>n+1)} aria-label="تحديث كشف المنظومات غير المغلقة"><AppIcon name="refresh" size={16}/></button></header>
  {error?<p className="workflowError" role="alert">{error}</p>:!ready?<p role="status">جاري تحميل الكشف…</p>:<><div className="pendingSystemTotals"><div><span>المقبوض المرتبط بالوصولات</span><strong><bdi>{money(s.collected)}</bdi> <small>د.ع</small></strong></div><div><span>الربح غير النهائي</span><strong><bdi>{money(s.provisionalProfit)}</bdi> <small>د.ع</small></strong></div></div>
  <p className="pendingSystemNote">المقبوضات تشمل ما سُلّم للإدارة. الربح يعتمد الكلفة والمصاريف المعتمدة المحفوظة، ويتأكد بعد غلق الملفات.{(from||to)&&' الفترة حسب تاريخ بيع المنظومة.'}</p>
  {data.unallocated.length>0&&<div className="pendingUnallocated"><b>تسديدات تحتاج ربط بوصولاتها: {money(s.unallocatedCollections)} د.ع</b><p>لعملاء لديهم منظومات مفتوحة؛ تبقى منفصلة عن المقبوض المرتبط حتى يتم ربطها بالفاتورة الصحيحة.</p></div>}
  <details open={expanded} onToggle={e=>setExpanded(e.currentTarget.open)}><summary>تفاصيل المنظومات والتسديدات</summary><div className="pendingSystemRows">{data.rows.map(r=><article key={r.id}><div><b>{r.customer}</b><small>وصل #{r.receiptNo} · {r.creatorName} · {statusLabel[r.status]||'غير مغلق'}</small></div><dl><div><dt>المقبوض المرتبط</dt><dd>{money(r.collected)} د.ع</dd></div><div><dt>الربح غير النهائي</dt><dd>{money(r.provisionalProfit)} د.ع</dd></div><div><dt>مصاريف مدفوعة</dt><dd>{money(r.paidExpenses)} د.ع</dd></div></dl></article>)}</div>{data.unallocated.map(r=><p className="pendingUnallocatedRow" key={r.customerId}>{r.customer} · {r.receiptCount} تسديدات غير موزعة <b>{money(r.amount)} د.ع</b></p>)}{doc&&<ReportActions enabled html={a4(doc.title,doc.body,doc.total,doc.subtitle)} filename="المنظومات-غير-المغلقة"/>}</details></>}
 </section>;
}
