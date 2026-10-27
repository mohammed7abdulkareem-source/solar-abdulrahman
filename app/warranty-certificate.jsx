'use client';
import PhoneActions from './phone-actions';
import {useCallback,useEffect,useState} from 'react';
import {useParams} from 'next/navigation';
import {supabase} from './supabase';
import {formatMoney} from './money-format.mjs';
import {termLabel} from './warranty-utils.mjs';
function Status({value}){return <div className={'certificateStatus '+(value?.active?'active':value?.covered?'expired':'')}><b>{value?.active?'ضمن الضمان':value?.covered?'انتهى الضمان':'بدون ضمان'}</b>{value?.active&&<strong>باقي {value.daysRemaining} يوم</strong>}</div>}
export default function WarrantyCertificate(){
 const {token}=useParams(),[data,setData]=useState(null),[error,setError]=useState(''),[busy,setBusy]=useState(true);
 const load=useCallback(async()=>{setBusy(true);setError('');try{if(!/^[a-f\d]{8}(?:-[a-f\d]{4}){3}-[a-f\d]{12}$/i.test(token||''))throw new Error('رمز الضمان غير صحيح.');const {data,error}=await supabase.rpc('solar_warranty_verify',{certificate_token:token});if(error)throw new Error('تعذر التحقق من الضمان. تأكد من الإنترنت وحاول مجددًا.');if(!data)throw new Error('لم نعثر على شهادة بهذا الرمز. راجع رقم الوصل مع الإدارة.');setData(data);}catch(err){setError(err.message);setData(null);}finally{setBusy(false);}},[token]);
 useEffect(()=>{load();const refresh=()=>{if(document.visibilityState==='visible')load();};window.addEventListener('focus',refresh);const timer=setInterval(refresh,60000);return()=>{window.removeEventListener('focus',refresh);clearInterval(timer);};},[load]);
 return <main className="warrantyCertificate"><header><b>عبدالرحمن سولار</b><h1>{data?.enabled?'شهادة ضمان الفاتورة':'التحقق من الفاتورة'}</h1><small>{data?.enabled?'تحقق مباشر من سجل الضمان':'بيانات الفاتورة المسجلة'}</small></header>{busy?<p role="status">جاري التحقق…</p>:error?<section className="certificateItem"><p role="alert">{error}</p><button className="uiButton" onClick={load}>إعادة المحاولة</button></section>:data&&<>
  <section className="certificateMeta"><dl><div><dt>العميل</dt><dd>{data.customer}</dd></div><div><dt>رقم الفاتورة</dt><dd>#{data.receiptNo}</dd></div><div><dt>{data.enabled?'تاريخ الوصل وبداية الضمان':'تاريخ الوصل'}</dt><dd>{data.date}</dd></div><div><dt>نوع الفاتورة</dt><dd>{data.kind==='system'?'بيع منظومة':'بيع جملة'}</dd></div>{data.total!=null&&<div><dt>إجمالي الفاتورة</dt><dd>{formatMoney(data.total)} د.ع</dd></div>}<div><dt>تاريخ التحقق</dt><dd>{data.checkedDate}</dd></div>{data.kind==='system'&&<><div><dt>عنوان التنصيب</dt><dd>{data.address||'—'}</dd></div><div><dt>مهندس التنصيب</dt><dd>{data.installer||'—'}</dd></div>{data.phone&&<div><dt>الهاتف</dt><dd><PhoneActions phone={data.phone} label={data.customer}/></dd></div>}{data.installDate&&<div><dt>موعد التنصيب</dt><dd>{data.installDate} {data.installTime?.slice(0,5)}</dd></div>}</>}</dl></section>
  {data.voided&&<p role="alert" className="accountAlert error">الفاتورة ملغاة؛ هذا المستند غير صالح.</p>}
  {data.items.map((item,index)=><article className="certificateItem" key={index}><h2>{item.name}</h2><p>{[item.brand,item.category].filter(Boolean).join(' · ')} · الكمية: {formatMoney(item.qty)}{item.price!=null?' · سعر الوحدة: '+formatMoney(item.price)+' د.ع':''}</p>{data.enabled&&<Status value={item.status}/>}{data.enabled&&item.status.covered&&<p>المدة: {termLabel(item.term)} · آخر يوم مشمول: {item.status.lastCoveredDate}</p>}</article>)}
  {data.enabled&&data.maintenanceStatus?.covered&&<section className="certificateMaintenance"><h2>ضمان الصيانة</h2><Status value={data.maintenanceStatus}/>{data.maintenanceStatus.covered&&<p>المدة: {termLabel(data.warranty.maintenance)} · آخر يوم مشمول: {data.maintenanceStatus.lastCoveredDate}</p>}</section>}
  {data.enabled&&data.warranty.notes&&<section className="certificateItem"><h2>شروط الضمان</h2><p style={{whiteSpace:'pre-wrap'}}>{data.warranty.notes}</p></section>}
  <footer>{data.enabled?<>تُحسب المدة من تاريخ الوصل، حسب تاريخ التحقق المبين أعلاه.<br/>احتفظ بالفاتورة ورمز الضمان للمراجعة.</>:'شركة عزم الشرق · فاتورة مسجّلة'}</footer>
 </>}</main>;
}
