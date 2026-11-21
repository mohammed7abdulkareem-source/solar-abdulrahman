'use client';
import PhoneActions from './phone-actions';
import MoneyInput from './money-input';
import {amountInput} from './customer-utils.mjs';
import {createPortal} from 'react-dom';
import AppIcon from './app-icons';
import WarehouseBadge from './warehouse-badge';
import {useCallback,useEffect,useRef,useState} from 'react';
import InstallationCalendar from './installation-calendar';
import InstallerAgenda from './installation-agenda';
import InstallationHandoff,{installationReviewer,installationStageLabel} from './installation-handoff';
import {normalizeSearch} from './party-search-utils.mjs';
import {installationStages as stages,installationLocalDay,installationMatchesStatus,installationFlexibleTask,hasInstallationAppointment} from './installation-utils.mjs';
import {saveRequest} from './save-request.mjs';
import {unlockNotificationSound,playNotificationSound} from './notification-sound.mjs';
import {supabase} from './supabase';
import {receiptNumber} from './supplier-utils.mjs';
import {approvedExpenseValue,installationPaidExpense,installationExpenseDifference} from './expense-review.mjs';
import {installationCost} from './review-utils.mjs';
import {receiptProfitFigures} from './profit-material-document.mjs';
import './installation-financials.css';
const fmt=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2});
const dateText=value=>value?new Date(value).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad',dateStyle:'short',timeStyle:'short'}):'';
export default function InstallationWorkflow({profile,onChanged,selectedJob=null}){
 return <InstallationQueue key={[profile?.id,profile?.user_type,profile?.is_admin,profile?.permissions?.installations,profile?.permissions?.system].join('|')} profile={profile} onChanged={onChanged} selectedJob={selectedJob}/>;
}
function InstallationQueue({profile,onChanged,selectedJob}){
 const [jobs,setJobs]=useState([]),[loading,setLoading]=useState(true),[error,setError]=useState(''),[status,setStatus]=useState(selectedJob?'all':'open'),[query,setQuery]=useState(''),[busy,setBusy]=useState(null),[message,setMessage]=useState(''),[toast,setToast]=useState(false);
 const engineer=profile?.user_type==='installer';
 useEffect(()=>{if(!toast)return;const timer=setTimeout(()=>setToast(false),6500);return()=>clearTimeout(timer);},[toast]);
 const request=useRef({seq:0,controller:null}),actionBusy=useRef(false),resultsHeading=useRef(null);
 const [showCalendar,setShowCalendar]=useState(!selectedJob),[focusedId,setFocusedId]=useState(String(selectedJob?.id??''));
 const refresh=useCallback(async()=>{
  request.current.controller?.abort();const controller=new AbortController(),seq=++request.current.seq;request.current.controller=controller;const timer=setTimeout(()=>controller.abort(),12000);
  try{const {data,error}=await supabase.rpc('solar_installation_jobs').abortSignal(controller.signal);if(seq!==request.current.seq)return;if(error)throw error;setJobs(data||[]);return data||[];}finally{clearTimeout(timer);if(seq===request.current.seq)request.current.controller=null;}
 },[]);
 useEffect(()=>{if(selectedJob?.id){setFocusedId(String(selectedJob.id));setQuery('');setStatus('all');setShowCalendar(false);}},[selectedJob]);
 useEffect(()=>{let live=true;refresh().catch(()=>{if(live)setError('تعذر تحميل المهام. اضغط تحديث للمحاولة مجدداً.');}).finally(()=>{if(live)setLoading(false);});return()=>{live=false;request.current.seq++;request.current.controller?.abort();};},[refresh]);
 async function change(job,action,payload={}){
  if(actionBusy.current)return false;actionBusy.current=true;setBusy(job.id);setError('');setMessage('');void unlockNotificationSound();
  try{
   const {error}=await saveRequest(signal=>supabase.rpc('solar_installation_action',{job_id:job.id,expected_revision:job.installationRevision,action,payload}).abortSignal(signal));
   if(error)throw error;
   setMessage({start:'تم بدء التنصيب وتحديث المرحلة للجميع.',complete:'تم إرسال تقرير الوصل #'+receiptNumber(job)+' للمراجعة.',return_report:'أُعيد تقرير الوصل #'+receiptNumber(job)+' إلى '+(job.installerName||'مهندس التنصيب')+' للتصحيح.',close:'تم إغلاق الملف وتحديث المرحلة عند المهندس.',reopen:'تمت إعادة فتح الملف للمراجعة.',clear_expenses:'تم إلغاء المصاريف وإرجاع المدفوع إلى قاصة صاحبه وتحديث الربح.'}[action]);
   if(action==='close')setToast(true);
   if(!engineer&&['return_report','close','reopen'].includes(action)){setFocusedId(String(job.id));setStatus('all');setQuery('');setShowCalendar(false);}
   void playNotificationSound();
   const updated=await refresh().catch(()=>setError('تم حفظ الخطوة. تعذر تحديث القائمة؛ اضغط تحديث لرؤية آخر حالة.'));
   const submitted=action==='complete'&&updated?.find(row=>row.id===job.id&&row.installationStatus==='completed');
   if(submitted)setMessage('تم إرسال تقرير الوصل #'+receiptNumber(submitted)+' إلى '+installationReviewer(submitted)+' للمراجعة.');
   if(onChanged)void Promise.resolve().then(onChanged).catch(()=>{});
   return true;
  }catch(e){setError(['40001','PT409'].includes(e.code)?'تغيّرت حالة الملف. تم تحديث المهام؛ راجعها وأعد المحاولة.':e.message?.includes('لم يصل تأكيد')?'لم يصل تأكيد العملية. حدّث المهام للتحقق من المرحلة قبل إعادة المحاولة.':'تعذر تنفيذ العملية. حدّث المهام وتأكد من الصلاحية والمرحلة الحالية.');await refresh().catch(()=>{});return false;}
  finally{actionBusy.current=false;setBusy(null);}
 }
 useEffect(()=>{const update=()=>{if(document.visibilityState==='visible'&&!actionBusy.current&&!request.current.controller)refresh().catch(()=>{});};const timer=setInterval(update,5000);window.addEventListener('solar-notification',update);window.addEventListener('focus',update);document.addEventListener('visibilitychange',update);return()=>{clearInterval(timer);window.removeEventListener('solar-notification',update);window.removeEventListener('focus',update);document.removeEventListener('visibilitychange',update);};},[refresh]);
 async function reload(){
  setLoading(true);setError('');
  try{await refresh();}catch{setError('تعذر التحديث. تحقق من الاتصال.');}finally{setLoading(false);}
 }
 if(engineer)return <InstallerAgenda jobs={jobs} installerId={profile.id} selectedJob={selectedJob}
  loading={loading} busy={busy!==null} error={error} message={message} onRefresh={reload} onChange={change}/>;
 const today=installationLocalDay(Date.now());
 const summaries=[['today','أعمال اليوم'],['in_progress','قيد التنفيذ'],['completed','بانتظار المراجعة'],['closed','مكتملة ومغلقة']].map(([key,label])=>({key,label,count:jobs.filter(j=>installationMatchesStatus(j,key,today)).length}));
 const resultsTitle=focusedId?'ملف التنصيب المحدد':summaries.find(s=>s.key===status)?.label||stages.find(([key])=>key===status)?.[1]||(status==='all'?'جميع التنصيبات':'التنصيبات المفتوحة');
 function selectSummary(key){setStatus(key);setQuery('');setFocusedId('');setShowCalendar(false);requestAnimationFrame(()=>{resultsHeading.current?.focus({preventScroll:true});resultsHeading.current?.scrollIntoView({block:'start',behavior:window.matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'});});}
 const term=normalizeSearch(query);
 const visible=jobs.filter(j=>focusedId?String(j.id)===focusedId:installationMatchesStatus(j,status,today)&&(!term||normalizeSearch([j.party,j.customerPhone,j.customerAddress,j.installerName,j.responsibleName,j.creatorName,j.receiptNo,j.id].join(' ')).includes(term)));
 return <div className="workflow installationRefresh">
  {toast&&createPortal(<div className="installationActionToast" role="status"><AppIcon name="check" size={22}/><div><b>تم الغلق</b><span>تم اعتماد المصاريف وإغلاق ملف التنصيب بنجاح.</span></div><button type="button" aria-label="إغلاق تنبيه الغلق" onClick={()=>setToast(false)}>×</button></div>,document.body)}
  <div className="workflowHero"><div><small>متابعة التنفيذ خطوة بخطوة</small><h2>إدارة التنصيبات</h2><p>جدول مشترك ومراحل موحّدة مع مهندس التنصيب</p></div><span aria-hidden="true"><AppIcon name="tools" size={26}/></span></div>
  <div className="workflowStats" role="group" aria-label="ملخص حالات التنصيب">{summaries.map(({key,label,count})=><button type="button" key={key} aria-pressed={status===key} disabled={loading} onClick={()=>selectSummary(key)}><b>{loading?'—':fmt(count)}</b><span>{label}</span></button>)}</div>
  <button className="installationCalendarToggle" aria-expanded={showCalendar} onClick={()=>setShowCalendar(v=>!v)}><AppIcon name="calendar" size={19}/> جدول مواعيد المهندسين <span>{showCalendar?'إخفاء':'عرض الحجوزات'}</span></button>
  {showCalendar&&<InstallationCalendar onOpenJob={j=>{setFocusedId(String(j.id));setQuery('');setStatus('all');setShowCalendar(false);}}/>}
  <div className="workflowSearch"><input aria-label="بحث بالتنصيبات" value={query} onChange={e=>{setFocusedId('');setQuery(e.target.value);}} placeholder="رقم الوصل أو اسم الزبون أو المهندس…"/><button disabled={loading||busy!==null} onClick={reload}>تحديث</button></div>
  <div className="statusTabs" aria-label="تصفية المهام">{[['open','المفتوحة'],...stages,['all','الكل']].map(([value,label])=><button key={value} aria-pressed={status===value} onClick={()=>{setFocusedId('');setStatus(value);}}>{label}</button>)}</div>
  {error&&<div className="workflowError" role="alert">{error}</div>}{message&&<div className="workflowSuccess" role="status">{message}</div>}
  <div className="installationResultsHeading"><h3 ref={resultsHeading} tabIndex={-1}>{resultsTitle}</h3>{focusedId?<button type="button" className="installerControl" onClick={()=>selectSummary('open')}>العودة إلى القائمة</button>:<span aria-live="polite">{loading?'جاري التحميل…':visible.length+' ملف'}</span>}</div>
  {loading?<div className="empty">جاري تحميل المهام…</div>:!visible.length?<div className="workflowEmpty"><span>✓</span><h3>لا توجد مهام ضمن هذا الاختيار</h3><p>يمكن إسناد مهمة من فاتورة بيع المنظومة.</p></div>:visible.map(job=><JobCard key={job.id} job={job} focused={String(job.id)===focusedId} busy={busy!==null} change={change}/>)}
 </div>;
}
function JobCard({job,busy,change,focused}){
 const report=job.installationReport||{};
 const flexible=installationFlexibleTask(job,installationLocalDay(Date.now())),carried=flexible&&hasInstallationAppointment(job);
 const financials=installationFinancials(job);
 const canApprove=job.canManage&&job.canCloseFile&&job.warehouseStatus==='ready'&&job.installationStatus!=='closed';
 return <article className="workflowJob" data-job-id={job.id} data-job-status={job.installationStatus}>
  <header><div><small>ملف #{receiptNumber(job)}</small><h3>{job.party||'عميل منظومة'}</h3>{job.warehouseName&&<small className="orderWarehouseLabel">{job.warehouseName}</small>}</div><span className={'workflowStatus '+job.installationStatus}>{installationStageLabel(job)}</span></header>
  {!financials&&job.sellingPrice!=null&&Number.isFinite(Number(job.sellingPrice))&&<div className="jobSalePrice"><span>سعر بيع المنظومة</span><strong><bdi>{fmt(job.sellingPrice)}</bdi> <small>د.ع</small></strong></div>}
  <InstallationHandoff job={job}/>
  <WarehouseBadge status={job.warehouseStatus} compact/>
  {flexible&&<p className={'installationNoAppointment'+(carried?' carried':'')}>{carried?'مرحّل إلى أعمال اليوم · يُنفّذ حسب الوقت المتاح':'بدون موعد · ضمن أعمال كل يوم إلى أن يُنجز'}</p>}
  <div className="jobDetails"><div><small>{carried?'الموعد السابق':'موعد التنصيب'}</small><b>{hasInstallationAppointment(job)?job.installDate+' • '+job.installTime.slice(0,5):'بدون موعد محدد'}</b></div><div className="jobAddress"><small>العنوان</small><b>{job.customerAddress||'العنوان غير محدد'}</b></div></div>
  <div className="jobContact">{job.customerPhone?<PhoneActions phone={job.customerPhone} label={'بالزبون '+job.party}/>:<span>رقم الهاتف غير متوفر</span>}</div>
  <details className="jobMaterials" open><summary>مواد التنصيب <span>{job.items?.length||0} مادة</span></summary>{job.items?.length?job.items.map((item,i)=><div key={item.id||i}><span>{item.name}{item.brand&&<small>{item.brand}</small>}</span><b>× {fmt(item.qty)}</b></div>):<p>لا توجد مواد مسجلة</p>}</details>
  <div className="jobTimes">{job.installationStartedAt&&<span>بدء العمل: {dateText(job.installationStartedAt)}</span>}{job.installationCompletedAt&&<span>إرسال التقرير: {dateText(job.installationCompletedAt)}</span>}{job.installationClosedAt&&<span>إغلاق الملف: {dateText(job.installationClosedAt)}</span>}</div>
  {report.submittedAt&&<div className="jobReport"><h4>تقرير المهندس</h4><p>{report.notes}</p>{(report.expenses||[]).map((e,i)=><div key={i}><span>{e.description}</span><b>{fmt(e.amount)} د.ع</b></div>)}<div><span>المصاريف المرفوعة للمراجعة</span><b>{fmt(report.expenseTotal)} د.ع</b></div></div>}
  {financials&&<InstallationFinancials amounts={financials} closed={job.installationStatus==='closed'} expanded={focused||canApprove||job.installationStatus==='closed'}/>}
  {job.canManage&&job.installationStatus!=='closed'&&(installationPaidExpense(job)>0||Number(job.installationExpenses)>0)&&<div className="cancelInstallationExpenses"><p>مصاريف التنصيب المدفوعة: {fmt(installationPaidExpense(job))} د.ع</p><button type="button" className="workflowSecondary" disabled={busy} onClick={()=>confirm('إلغاء مصاريف التنصيب وإرجاع المدفوع إلى قاصة صاحبه؟')&&change(job,'clear_expenses',{notes:'إلغاء مصاريف التنصيب المعتمدة'})}>إلغاء مصاريف التنصيب وإرجاعها للقاصة</button></div>}
  {canApprove&&<ApproveInstallation job={job} financials={financials} busy={busy} onSubmit={payload=>change(job,'close',payload)}/>}
  {job.canManage&&job.canReturnReport&&<ReturnReport key={job.installationRevision} busy={busy} onSend={payload=>change(job,'return_report',payload)}/>}
  {job.canManage&&job.warehouseStatus!=='ready'&&job.installationStatus!=='closed'&&<p className="workflowNotice">بانتظار تجهيز المخزن. يظهر اعتماد المصاريف والغلق بعد التجهيز.</p>}
  {job.canManage&&job.installationStatus==='closed'&&<div className="jobFinancials">{job.installationExpenseNotes&&<p>{job.installationExpenseNotes}</p>}<button disabled={busy} onClick={()=>confirm('إعادة فتح الملف للمراجعة؟ فتح الملف لا يلغي المصاريف؛ يمكنك إلغاءها أو تعديلها بعد الفتح.')&&change(job,'reopen')}>إعادة فتح للمراجعة</button></div>}
 </article>;
}
function ReturnReport({busy,onSend}){
 const [notes,setNotes]=useState('');
 return <details className="installationReturn"><summary><AppIcon name="exchange" size={16}/>إرجاع التقرير للتعديل</summary>
  <form onSubmit={event=>{event.preventDefault();if(!busy&&notes.trim())void onSend({notes:notes.trim()});}}>
   <label>سبب إعادة التقرير للمهندس<textarea required maxLength={4000} value={notes} onChange={event=>setNotes(event.target.value)} disabled={busy}/></label>
   <button type="submit" className="workflowSecondary" disabled={busy||!notes.trim()}>إعادة التقرير للمهندس</button>
  </form></details>;
}
function installationFinancials(job){
 if(!job.canManage||job.total==null||job.expenses===undefined||job.installationExpenses===undefined)return null;
 if(job.cost==null){
  if(!job.personalPriceBasis||job.profit==null)return null;
  const netProfit=Number(job.profit),installationExpenses=Number(job.installationExpenses);
  return {kind:'system',personalBasis:true,costHidden:true,sales:Number(job.total),invoiceExpenses:Number(job.expenses),
   installationExpenses,netProfit,beforeInstallation:netProfit+installationExpenses};
 }
 const [sales,materialsCost,invoiceExpenses,installationExpenses]=[job.total,job.cost,job.expenses,job.installationExpenses].map(Number);
 if(![sales,materialsCost,invoiceExpenses,installationExpenses].every(Number.isFinite))return null;
 const grossProfit=sales-materialsCost,totalCost=installationCost(job);
 return {kind:'system',personalBasis:job.personalPriceBasis===true,sales,materialsCost,invoiceExpenses,installationExpenses,grossProfit,
  beforeInstallation:grossProfit-invoiceExpenses,totalCost,netProfit:sales-totalCost};
}
function InstallationFinancials({amounts,closed,expanded}){
 const figures=receiptProfitFigures(amounts,{provisional:!closed,showInvoiceExpenses:true});
 const [,saleLabel,sale]=figures[0];
 const rows=[...figures.slice(1,-1),...(amounts.costHidden?[]:[['totalCost','إجمالي الكلفة والمصاريف',amounts.totalCost]]),figures.at(-1)];
 return <details className="installationFinancials" open={expanded}>
  <summary><span className="installationFinancialsTitle">تفاصيل ربح المنظومة</span><span className="jobSalePrice"><span>{saleLabel}</span><strong><bdi dir="ltr">{fmt(sale)}</bdi> <small>د.ع</small></strong></span></summary>
  <dl>{rows.map(([key,label,value])=><div key={key} className={key==='net'?'installationNet'+(value<0?' loss':''):undefined}><dt>{label}</dt><dd><bdi dir="ltr">{fmt(value)}</bdi> <small>د.ع</small></dd></div>)}</dl>
 </details>;
}
function ApproveInstallation({job,financials,busy,onSubmit}){
 const [amount,setAmount]=useState(()=>approvedExpenseValue(job)),[notes,setNotes]=useState(job.installationExpenseNotes||''),[error,setError]=useState(''),[draftRevision,setDraftRevision]=useState(job.installationRevision);
 const stale=draftRevision!==job.installationRevision,paid=installationPaidExpense(job),difference=installationExpenseDifference(job,amountInput(amount)),proposal=job.installationReport?.expenseTotal;
 const approved=Number(amountInput(amount));
 const preview=financials&&!stale&&Number.isFinite(approved)&&approved>=0&&approved<=1e9&&approved!==financials.installationExpenses;
 return <form className="approvalForm" onSubmit={async e=>{e.preventDefault();setError('');if(stale)return setError('تغيّر الملف؛ حمّل القيم الحالية قبل الاعتماد.');if(!Number.isFinite(approved)||approved<0||approved>1e9)return setError('أدخل مصاريف صحيحة.');if(confirm('تأكيد اعتماد المصاريف وإغلاق الملف؟ يُسجّل فرق المبلغ فقط.'))await onSubmit({amount:approved,notes:notes.trim()})}}>
  <h4>مراجعة الإدارة وإغلاق الملف</h4>{stale&&<div className="workflowError" role="alert">تغيّر الملف أثناء المراجعة.<button type="button" onClick={()=>{setAmount(approvedExpenseValue(job));setNotes(job.installationExpenseNotes||'');setDraftRevision(job.installationRevision);setError('');}}>تحميل القيم الحالية</button></div>}
  <p className="workflowHint">المدفوع فعليًا سابقًا: <b>{fmt(paid)} د.ع</b></p>{proposal!=null&&<p className="workflowHint">مقترح تقرير المهندس: <b>{fmt(proposal)} د.ع</b> <button type="button" disabled={busy||stale} onClick={()=>setAmount(String(proposal))}>استخدام مبلغ التقرير</button></p>}
  <label className="workflowField">المصاريف النهائية المعتمدة — د.ع<MoneyInput aria-label="المصاريف النهائية للمنظومة" value={amount} disabled={busy||stale} placeholder="اختياري — الفارغ يعني 0" onChange={setAmount}/></label>
  <label className="workflowField">ملاحظات الاعتماد (اختياري)<textarea value={notes} maxLength={4000} disabled={busy||stale} placeholder="يمكن إغلاق الملف بدون كتابة سبب" onChange={e=>setNotes(e.target.value)}/></label>
  {preview&&<div className="installationApprovalPreview" role="status"><h5>معاينة قبل الاعتماد</h5><dl><div><dt>مصاريف التنصيب بعد التعديل</dt><dd><bdi>{fmt(approved)}</bdi> د.ع</dd></div><div><dt>صافي الربح بعد التعديل</dt><dd><bdi>{fmt(financials.beforeInstallation-approved)}</bdi> د.ع</dd></div></dl></div>}
  {Number.isFinite(difference)&&<p className="workflowHint expenseDifference" role="status">{difference>0?'المبلغ الإضافي المطلوب من القاصة: '+fmt(difference)+' د.ع':difference<0?'المبلغ الذي يرجع لقاصة من دفعه: '+fmt(-difference)+' د.ع':'لا يوجد صرف إضافي؛ المبلغ مسجل سابقًا.'}</p>}
  <p className="workflowHint">تنخصم المصاريف حتى لو صار رصيد القاصة سالبًا؛ تسديدات الزبائن تُضاف إليه تلقائيًا. اعتماد الصفر يرجع المدفوع لقاصة صاحبه، والسجل يحفظ الصرف والإرجاع للتدقيق.</p>{error&&<p className="workflowError" role="alert">{error}</p>}<button className="workflowPrimary" disabled={busy||stale}>{busy?'جاري الاعتماد…':'اعتماد المصاريف وإغلاق الملف'}</button>
 </form>;
}
