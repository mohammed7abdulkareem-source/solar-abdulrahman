'use client';
import {useEffect,useState} from 'react';
import AppIcon from './app-icons';
import InstallationHandoff,{installationReviewer,installationStageLabel} from './installation-handoff';
import InstallationCalendar from './installation-calendar';
import PhoneActions from './phone-actions';
import MoneyInput from './money-input';
import {amountInput} from './customer-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import WarehouseBadge from './warehouse-badge';
import {receiptNumber} from './supplier-utils.mjs';
import {hasInstallationAppointment,installationDailyTask,installationLocalDay} from './installation-utils.mjs';

const filters=[['today','أعمال اليوم'],['in_progress','قيد التنفيذ'],['upcoming','القادمة'],['completed','بانتظار المراجعة'],['archive','الأرشيف'],['all','كل المهام']];
const dayFormat=new Intl.DateTimeFormat('ar-IQ',{weekday:'long',day:'numeric',month:'short',year:'numeric',timeZone:'Asia/Baghdad'});
const timestamp=new Intl.DateTimeFormat('ar-IQ',{dateStyle:'short',timeStyle:'short',timeZone:'Asia/Baghdad'});
const fmt=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2});
const blankDraft={checks:{materials:false,tested:false,handover:false},notes:'',expenses:[]};
function previousDraft(job){
 const report=job.installationReport;
 if(job.installationReview?.status!=='returned'||!report?.submittedAt)return blankDraft;
 return {checks:{...blankDraft.checks,...report.checks},notes:report.notes||'',
  expenses:(report.expenses||[]).map(row=>({description:row.description||'',amount:String(row.amount??'')}))};
}
const dayLabel=day=>dayFormat.format(new Date(day+'T12:00:00Z'));
function matches(job,filter,today){
 const status=job.installationStatus;
 if(filter==='today')return status==='in_progress'||installationDailyTask(job,today);
 if(filter==='upcoming')return status==='pending'&&hasInstallationAppointment(job)&&job.installDate>today;
 if(filter==='archive')return status==='closed';
 return filter==='all'||filter===status;
}
function queueOrder(a,b){
 const rank=job=>({in_progress:0,pending:1,completed:2,closed:3})[job.installationStatus]??4;
 const phase=rank(a)-rank(b);
 if(phase)return phase;
 if(rank(a)>=2)return String(b.installationClosedAt||b.installationCompletedAt||'').localeCompare(String(a.installationClosedAt||a.installationCompletedAt||''))||Number(b.id)-Number(a.id);
 const appointment=job=>hasInstallationAppointment(job)?job.installDate+' '+job.installTime:'9999';
 return appointment(a).localeCompare(appointment(b))||Number(a.id)-Number(b.id);
}
function appointmentLabel(job,today){
 if(!hasInstallationAppointment(job))return 'بدون موعد محدد';
 const date=dayLabel(job.installDate);
 const when=job.installDate===today?'اليوم':job.installDate<today&&['pending','in_progress'].includes(job.installationStatus)?'مرحّل من '+date:date;
 return when+' · '+job.installTime.slice(0,5);
}

export default function InstallerAgenda({jobs,installerId,selectedJob,loading,busy,error,message,onRefresh,onChange}){
 const [filter,setFilter]=useState('today'),[query,setQuery]=useState(''),[focusedId,setFocusedId]=useState(selectedJob?.id||'');
 const [calendar,setCalendar]=useState(false),[reportId,setReportId]=useState(''),[drafts,setDrafts]=useState({});
 const today=installationLocalDay(Date.now()),own=jobs.filter(job=>String(job.installerId)===String(installerId)),term=normalizeSearch(query);
 useEffect(()=>{if(selectedJob?.id){setFocusedId(selectedJob.id);setQuery('');setCalendar(false);}},[selectedJob]);
 const focused=focusedId?own.find(job=>String(job.id)===String(focusedId)):null;
 const activeFilter=focused?.installationStatus==='completed'?'completed':focused?.installationStatus==='closed'?'archive':focusedId||term?'all':filter;
 function selectFilter(value){setFilter(value);setFocusedId('');setQuery('');setCalendar(false);}
 const visible=own.filter(job=>{
  if(focusedId)return String(job.id)===String(focusedId);
  return matches(job,activeFilter,today)&&(!term||normalizeSearch([job.party,job.customerPhone,job.customerAddress,job.responsibleName,job.creatorName,receiptNumber(job),job.id].join(' ')).includes(term));
 }).sort(queueOrder);
 function draftKey(job){return job.id+':'+job.installationRevision;}
 async function act(job,action,payload){
  const ok=await onChange(job,action,payload);
  if(ok&&action==='start')setReportId(String(job.id));
  if(ok&&action==='complete'){
   setReportId('');setFocusedId(String(job.id));setQuery('');setCalendar(false);
   setDrafts(previous=>{const next={...previous};delete next[draftKey(job)];return next;});
  }
  return ok;
 }
 const resultLabel=focusedId?'المهمة المحددة':term?'نتائج البحث':filters.find(([key])=>key===filter)[1];
 return <section className="workflow installationRefresh installerAgenda" dir="rtl" data-installer-workspace="">
  <header className="installerHeading"><div><h2>مهامي الميدانية</h2><p>{dayLabel(today)}</p></div>
   <button type="button" className="installerControl" onClick={onRefresh} disabled={loading||busy} aria-label="تحديث المهام"><AppIcon name="refresh" size={17}/> تحديث</button></header>
  <nav className="installerFilters" aria-label="تصفية مهامي">{filters.map(([key,label])=><button type="button" key={key}
    data-agenda-filter={key} aria-pressed={activeFilter===key} onClick={()=>selectFilter(key)}>
    <span>{label}</span><b>{loading?'…':own.filter(job=>matches(job,key,today)).length}</b></button>)}</nav>
  <div className="installerToolbar"><label><AppIcon name="search" size={18}/><input type="search" aria-label="بحث بالتنصيبات" value={query}
    placeholder="بحث بالاسم، الهاتف أو رقم الوصل" onChange={e=>{setFocusedId('');setQuery(e.target.value);}}/></label>
   <button type="button" className="installerControl" aria-expanded={calendar} onClick={()=>setCalendar(value=>!value)}><AppIcon name="calendar" size={18}/>جدول مواعيدي</button></div>
  {calendar&&<InstallationCalendar personalInstallerId={installerId} onOpenJob={job=>{setFocusedId(String(job.id));setQuery('');setCalendar(false);}}/>}
  {error&&<div role="alert" className="workflowError">{error}</div>}{message&&<div role="status" className="workflowSuccess">{message}</div>}
  <div className="installationResultsHeading"><h3>{resultLabel}</h3>{focusedId?<button type="button" className="installerControl" onClick={()=>selectFilter('all')}>العودة لكل المهام</button>:<span aria-live="polite">{loading?'جاري التحميل…':visible.length+' مهمة'}</span>}</div>
  {loading?<p className="workflowEmpty" role="status">جاري تحميل المهام…</p>:!visible.length?<div className="workflowEmpty"><h3>{focusedId?'المهمة غير متاحة':term?'لم نعثر على مهمة مطابقة':'لا توجد مهام ضمن هذا الاختيار'}</h3>
   {activeFilter!=='all'&&<button type="button" className="installerControl" onClick={()=>selectFilter('all')}>عرض كل المهام</button>}</div>:
   <div className="installerCards">{visible.map(job=><FieldJob key={job.id} job={job} today={today} busy={busy} onChange={act}
     reportOpen={reportId===String(job.id)} toggleReport={()=>setReportId(reportId===String(job.id)?'':String(job.id))}
     draft={drafts[draftKey(job)]||previousDraft(job)} setDraft={draft=>setDrafts(previous=>({...previous,[draftKey(job)]:draft}))}/>)}</div>}
 </section>;
}

function FieldJob({job,today,busy,onChange,reportOpen,toggleReport,draft,setDraft}){
 const status=job.installationStatus,stage=installationStageLabel(job);
 const report=job.installationReport||{},items=job.items||[];
 return <article className="workflowJob installerJob" aria-label={'تنصيب '+(job.party||'منظومة')+' رقم '+receiptNumber(job)} data-job-id={job.id} data-job-status={status}>
  <header><div><small>ملف #{receiptNumber(job)}</small><h3>{job.party||'عميل منظومة'}</h3></div><span className={'workflowStatus '+status}>{stage}</span></header>
  <InstallationHandoff job={job} field/>
  <dl className="installerVisit"><div><dt>موعد التنصيب</dt><dd><AppIcon name="calendar" size={16}/><bdi>{appointmentLabel(job,today)}</bdi></dd></div>
   <div><dt>العنوان</dt><dd>{job.customerAddress||'لم يُسجّل عنوان'}</dd></div></dl>
  <div className="installerContact">{job.customerPhone?<PhoneActions phone={job.customerPhone} label={'بالزبون '+(job.party||'')}/>:<small>رقم الزبون غير متوفر</small>}
   <WarehouseBadge status={job.warehouseStatus} compact/></div>
  {status==='pending'&&<button type="button" className="workflowPrimary" disabled={busy||job.warehouseStatus!=='ready'} onClick={()=>onChange(job,'start')}>{job.warehouseStatus==='ready'?'بدء التنصيب':'بانتظار تجهيز المخزن'}</button>}
  {status==='in_progress'&&<><button type="button" className="workflowPrimary" aria-expanded={reportOpen} onClick={toggleReport}>{reportOpen?'إخفاء تقرير الإنجاز':job.installationReview?.status==='returned'?'تصحيح تقرير الإنجاز':'تقرير الإنجاز'}</button>
   {reportOpen&&<CompletionReport reviewer={installationReviewer(job)} busy={busy} draft={draft} setDraft={setDraft} onSubmit={payload=>onChange(job,'complete',payload)}/>}</>}
  <details className="installerJobDetail"><summary>تفاصيل المهمة والمواد <span>{items.length} مادة</span></summary>
   <dl className="installerVisit"><div><dt>مخزن التجهيز</dt><dd>{job.warehouseName||'غير محدد'}</dd></div></dl>
   {items.length>0?<ul className="installerMaterials">{items.map((item,i)=><li key={item.id||i}><span><span>{item.name}</span>{item.brand&&<small>{item.brand}</small>}</span><b>× <bdi>{item.qty}</bdi></b></li>)}</ul>:<p>لا توجد مواد مسجلة</p>}
   <dl className="installerTimeline">{[['installationStartedAt','بدء العمل'],['installationCompletedAt','إرسال التقرير'],['installationClosedAt','إغلاق الملف']].filter(([key])=>job[key]).map(([key,label])=><div key={key}><dt>{label}</dt><dd>{timestamp.format(new Date(job[key]))}</dd></div>)}</dl>
   {report.submittedAt&&<section className="jobReport"><h4>تقرير الإنجاز المرسل</h4><p>{report.notes}</p>{(report.expenses||[]).map((row,i)=><div key={i}><span>{row.description}</span><b>{fmt(row.amount)} د.ع</b></div>)}<div><span>إجمالي مصاريف التقرير</span><b>{fmt(report.expenseTotal)} د.ع</b></div></section>}
  </details>
 </article>;
}
function CompletionReport({busy,draft,setDraft,onSubmit,reviewer}){
 const {checks,notes,expenses}=draft;
 const [error,setError]=useState('');
 const total=expenses.reduce((s,e)=>s+(Number(amountInput(e.amount))||0),0);
 const submit=async e=>{e.preventDefault();setError('');if(!Object.values(checks).every(Boolean)||!notes.trim())return setError('أكمل الفحص واكتب ملخص التنفيذ.');const entered=expenses.filter(x=>amountInput(x.amount)!=='');if(entered.some(x=>!Number.isFinite(Number(amountInput(x.amount)))||Number(amountInput(x.amount))<0||Number(amountInput(x.amount))>1e9))return setError('أدخل مبلغاً صحيحاً للمصروف.');const actual=entered.filter(x=>Number(amountInput(x.amount))>0).map(x=>({description:x.description.trim()||'مصروف',amount:Number(amountInput(x.amount))}));if(!confirm('تأكيد انتهاء التنصيب وإرسال التقرير إلى '+reviewer+'؟'))return;await onSubmit({checks,notes:notes.trim(),expenses:actual});};
 return <form className="completionForm" aria-label="تقرير إنجاز التنصيب" onSubmit={submit}><h4>تقرير إنجاز التنصيب</h4><fieldset disabled={busy}><legend>فحص وتسليم المنظومة</legend>{[['materials','تمت مطابقة وتركيب المواد'],['tested','تم فحص التشغيل والسلامة'],['handover','تم شرح التشغيل وتسليم المنظومة للزبون']].map(([key,label])=><label className="workflowCheck" key={key}><input type="checkbox" checked={checks[key]} onChange={e=>setDraft({...draft,checks:{...checks,[key]:e.target.checked}})}/><span>{label}</span></label>)}
 <label className="workflowField">ملخص التنفيذ والملاحظات<textarea required maxLength={4000} value={notes} onChange={e=>setDraft({...draft,notes:e.target.value})} placeholder="اكتب الأعمال المنجزة ونتيجة فحص التشغيل…"/></label>
 <h4>مصاريف المهمة</h4><p className="workflowHint">أضف المصاريف الفعلية لمراجعتها من الإدارة. إذا ماكو مصاريف، اترك القائمة فارغة.</p>
 {expenses.map((x,i)=><div className="expenseLine" key={i}><input aria-label={'بيان المصروف '+(i+1)} maxLength={500} placeholder="بيان المصروف (اختياري)" value={x.description} onChange={e=>setDraft({...draft,expenses:expenses.map((v,k)=>k===i?{...v,description:e.target.value}:v)})}/><MoneyInput aria-label={'مبلغ المصروف '+(i+1)} placeholder="المبلغ د.ع (اختياري)" value={x.amount} onChange={amount=>setDraft({...draft,expenses:expenses.map((v,k)=>k===i?{...v,amount}:v)})}/><button type="button" className="expenseRemove" onClick={()=>setDraft({...draft,expenses:expenses.filter((_,k)=>k!==i)})}>حذف</button></div>)}
 <button type="button" className="workflowSecondary" disabled={expenses.length>=50} onClick={()=>setDraft({...draft,expenses:[...expenses,{description:'',amount:''}]})}>＋ إضافة مصروف</button><div className="expenseTotal"><span>إجمالي مصاريف التقرير</span><b>{fmt(total)} د.ع</b></div>
 {error&&<p role="alert" className="workflowError">{error}</p>}<button className="workflowPrimary" type="submit">{busy?'جاري الإرسال…':'إكمال التنصيب وإرسال التقرير'}</button></fieldset></form>;
}
