'use client';
import {useEffect,useState} from 'react';
import {supabase} from './supabase';
import {quantity} from './warehouse-utils.mjs';
import {periodKindLabel,periodSalesDocument} from './period-sales-report.mjs';
import ReportActions from './report-actions';

export default function PeriodSales({search,kind,from,to,status,refresh,a4}){
 const [loaded,setLoaded]=useState(null),[error,setError]=useState(''),[retry,setRetry]=useState(0);
 const key=JSON.stringify([search,kind,from,to,status,refresh,retry]),invalid=!!from&&!!to&&from>to;
 useEffect(()=>{let live=true;const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),15000);setLoaded(null);setError('');
  if(invalid){clearTimeout(timer);return()=>{live=false;};}
  supabase.rpc('solar_sales_period',{search_text:search,sale_kind:kind,date_from:from||null,date_to:to||null,job_status:status}).abortSignal(controller.signal).then(({data,error})=>{if(error)throw error;if(live)setLoaded({key,data});}).catch(e=>{if(live)setError(e.code?e.message:'تعذر تحميل مبيعات الفترة. أعد المحاولة.');}).finally(()=>clearTimeout(timer));
  return()=>{live=false;clearTimeout(timer);controller.abort();};
 },[key,search,kind,from,to,status,invalid]);
 if(invalid)return <p role="alert" className="workflowError">تاريخ البداية يجب أن يسبق تاريخ النهاية.</p>;
 if(error)return <p role="alert" className="workflowError">{error}<button type="button" onClick={()=>setRetry(n=>n+1)}>إعادة تحميل التقرير</button></p>;
 if(loaded?.key!==key)return <p className="empty" role="status">جاري جمع مواد مبيعات الفترة…</p>;
 const data=loaded.data,rows=data.rows||[],summary=data.summary,doc=periodSalesDocument(data);
 return <section className="periodSales" aria-label="تقرير مبيعات الفترة"><header><div><h2>مبيعات الفترة</h2><p>{periodKindLabel(kind)} · جميع الفواتير المطابقة للفترة والبحث</p></div></header>
  <div className="periodSalesSummary">{[['عدد المواد',summary.materialCount],['العدد المبيوع',summary.quantitySold],['عدد الفواتير',summary.invoiceCount]].map(([label,value])=><div key={label}><span>{label}</span><strong><bdi>{quantity(value)}</bdi></strong></div>)}</div>
  {rows.length?<><div className="periodMaterialsTable"><table><colgroup><col className="periodIndexCol"/><col/><col className="periodQtyCol"/><col className="periodQtyCol"/></colgroup><thead><tr><th>ت</th><th>المادة</th><th>العدد المبيوع</th><th>المتبقي الحالي</th></tr></thead><tbody>{rows.map((row,index)=><tr key={JSON.stringify(row.key)}><td>{index+1}</td><td><b dir="auto">{row.name}</b><small>{[row.code&&'كود '+row.code,row.brand,row.category].filter(Boolean).join(' · ')}</small></td><td><bdi>{quantity(row.quantitySold)}</bdi></td><td><bdi>{row.remainingQty==null?'—':quantity(row.remainingQty)}</bdi></td></tr>)}</tbody></table></div><p className="periodSalesStockNote">المتبقي هو المتاح حاليًا بالمخازن المسموحة، وليس رصيد نهاية الفترة.{rows.some(row=>row.remainingQty==null)&&' الرمز — يعني أن الرصيد الحالي غير متاح.'}</p><ReportActions enabled html={a4(doc.title,doc.body,doc.total,doc.subtitle)} filename={'مبيعات-الفترة-'+(from||'البداية')+'-'+(to||'آخر-فاتورة')}/></>:<p className="empty">لا توجد مواد مبيوعة ضمن الفترة والاختيارات.</p>}
 </section>;
}
