'use client';
import PhoneActions from './phone-actions';
import {createPortal} from 'react-dom';
import AppIcon from './app-icons';
import WarehouseBadge from './warehouse-badge';
import {useCallback,useEffect,useRef,useState} from 'react';
import InstallationCalendar from './installation-calendar';
import {installationStages as stages,installationIndex,installationLocalDay,installationMatchesStatus} from './installation-utils.mjs';
import {saveRequest} from './save-request.mjs';
import {unlockNotificationSound,playNotificationSound} from './notification-sound.mjs';
import {supabase} from './supabase';
import {receiptNumber} from './supplier-utils.mjs';
import {approvedExpenseValue,installationPaidExpense,installationExpenseDifference} from './expense-review.mjs';
const fmt=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2});
const rawMoney=value=>String(value??'').replace(/,/g,'').trim();
const moneyValue=value=>rawMoney(value)===''?'':fmt(rawMoney(value));
const dateText=value=>value?new Date(value).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad',dateStyle:'short',timeStyle:'short'}):'';
export default function InstallationWorkflow({profile,onChanged,selectedJob=''}){
 const [jobs,setJobs]=useState([]),[loading,setLoading]=useState(true),[error,setError]=useState(''),[status,setStatus]=useState(selectedJob?'all':'open'),[query,setQuery]=useState(selectedJob),[busy,setBusy]=useState(null),[message,setMessage]=useState(''),[toast,setToast]=useState(false);
 const engineer=profile?.user_type==='installer';
 useEffect(()=>{if(!toast)return;const timer=setTimeout(()=>setToast(false),6500);return()=>clearTimeout(timer);},[toast]);
 const request=useRef({seq:0,controller:null}),actionBusy=useRef(false),resultsHeading=useRef(null);
 const [showCalendar,setShowCalendar]=useState(!selectedJob);
 const refresh=useCallback(async()=>{
  request.current.controller?.abort();const controller=new AbortController(),seq=++request.current.seq;request.current.controller=controller;const timer=setTimeout(()=>controller.abort(),12000);
  try{const {data,error}=await supabase.rpc('solar_installation_jobs').abortSignal(controller.signal);if(error)throw error;if(seq===request.current.seq)setJobs(data||[]);}finally{clearTimeout(timer);}
 },[]);
 useEffect(()=>{if(selectedJob){setQuery(String(selectedJob));setStatus('all');}},[selectedJob]);
 useEffect(()=>{let live=true;refresh().catch(()=>{if(live)setError('تعذر تحميل المهام. اضغط تحديث للمحاولة مجدداً.');}).finally(()=>{if(live)setLoading(false);});return()=>{live=false;request.current.seq++;request.current.controller?.abort();};},[refresh]);
 async function change(job,action,payload={}){
  if(actionBusy.current)return false;actionBusy.current=true;setBusy(job.id);setError('');setMessage('');void unlockNotificationSound();
  try{
   const {error}=await saveRequest(signal=>supabase.rpc('solar_installation_action',{job_id:job.id,expected_revision:job.installationRevision,action,payload}).abortSignal(signal));
   if(error)throw error;
   setMessage({start:'تم بدء التنصيب وتحديث المرحلة للجميع.',complete:'تم إنهاء التنصيب وإرسال التقرير للمراجعة.',close:'تم إغلاق الملف وتحديث المرحلة عند المهندس.',reopen:'تمت إعادة فتح الملف للمراجعة.',clear_expenses:'تم إلغاء المصاريف وإرجاع المدفوع إلى قاصة صاحبه وتحديث الربح.'}[action]);
   if(action==='close')setToast(true);
   void playNotificationSound();
   await refresh().catch(()=>setError('تم حفظ الخطوة. تعذر تحديث القائمة؛ اضغط تحديث لرؤية آخر حالة.'));
   if(onChanged)void Promise.resolve().then(onChanged).catch(()=>{});
   return true;
  }catch(e){setError(e.code==='P0002'?'رصيد قاصتك لا يكفي لدفع المصاريف. أضف الرصيد أو راجع المبلغ.':['40001','PT409'].includes(e.code)?'تغيّرت حالة الملف. تم تحديث المهام؛ راجعها وأعد المحاولة.':e.message?.includes('لم يصل تأكيد')?'لم يصل تأكيد العملية. حدّث المهام للتحقق من المرحلة قبل إعادة المحاولة.':'تعذر تنفيذ العملية. حدّث المهام وتأكد من الصلاحية والمرحلة الحالية.');await refresh().catch(()=>{});return false;}
  finally{actionBusy.current=false;setBusy(null);}
 }
 useEffect(()=>{const update=()=>{if(document.visibilityState==='visible'&&!actionBusy.current)refresh().catch(()=>{});};const timer=setInterval(update,5000);window.addEventListener('solar-notification',update);window.addEventListener('focus',update);document.addEventListener('visibilitychange',update);return()=>{clearInterval(timer);window.removeEventListener('solar-notification',update);window.removeEventListener('focus',update);document.removeEventListener('visibilitychange',update);};},[refresh]);
 const today=installationLocalDay(Date.now());
 const summaries=[['today','مواعيد اليوم'],['in_progress','قيد التنفيذ'],['completed','بانتظار المراجعة'],['closed','مكتملة ومغلقة']].map(([key,label])=>({key,label,count:jobs.filter(j=>installationMatchesStatus(j,key,today)).length}));
 const resultsTitle=summaries.find(s=>s.key===status)?.label||stages.find(([key])=>key===status)?.[1]||(status==='all'?'جميع التنصيبات':'التنصيبات المفتوحة');
 function selectSummary(key){setStatus(key);setQuery('');setShowCalendar(false);requestAnimationFrame(()=>{resultsHeading.current?.focus({preventScroll:true});resultsHeading.current?.scrollIntoView({block:'start',behavior:window.matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'});});}
 const visible=jobs.filter(j=>installationMatchesStatus(j,status,today)&&(!query||[j.party,j.customerPhone,j.customerAddress,j.installerName,j.creatorName,String(j.receiptNo),...(selectedJob?[String(j.id)]:[])].join(' ').includes(query.trim())));
 return <div className="workflow installationRefresh">
  {toast&&createPortal(<div className="installationActionToast" role="status"><AppIcon name="check" size={22}/><div><b>تم الغلق</b><span>تم اعتماد المصاريف وإغلاق ملف التنصيب بنجاح.</span></div><button type="button" aria-label="إغلاق تنبيه الغلق" onClick={()=>setToast(false)}>×</button></div>,document.body)}
  <div className="workflowHero"><div><small>متابعة التنفيذ خطوة بخطوة</small><h2>{engineer?'مهامي الميدانية':'إدارة التنصيبات'}</h2><p>{engineer?'المواعيد والمواد وإنجاز خطواتك بمكان واحد':'جدول مشترك ومراحل موحّدة مع مهندس التنصيب'}</p></div><span aria-hidden="true"><AppIcon name="tools" size={26}/></span></div>
  <div className="workflowStats" role="group" aria-label="ملخص حالات التنصيب">{summaries.map(({key,label,count})=><button type="button" key={key} aria-pressed={status===key} disabled={loading} onClick={()=>selectSummary(key)}><b>{loading?'—':fmt(count)}</b><span>{label}</span></button>)}</div>
  <button className="installationCalendarToggle" aria-expanded={showCalendar} onClick={()=>setShowCalendar(v=>!v)}><AppIcon name="calendar" size={19}/> جدول مواعيد المهندسين <span>{showCalendar?'إخفاء':'عرض الحجوزات'}</span></button>
  {showCalendar&&<InstallationCalendar/>}
  <div className="workflowSearch"><input aria-label="بحث بالتنصيبات" value={query} onChange={e=>setQuery(e.target.value)} placeholder="بحث بالزبون، المستخدم أو الهاتف…"/><button disabled={loading||busy!==null} onClick={async()=>{setLoading(true);setError('');try{await refresh()}catch{setError('تعذر التحديث. تحقق من الاتصال.')}finally{setLoading(false)}}}>تحديث</button></div>
  <div className="statusTabs" aria-label="تصفية المهام">{[['open','المفتوحة'],...stages,['all','الكل']].map(([value,label])=><button key={value} aria-pressed={status===value} onClick={()=>setStatus(value)}>{label}</button>)}</div>
  {error&&<div className="workflowError" role="alert">{error}</div>}{message&&<div className="workflowSuccess" role="status">{message}</div>}
  <div className="installationResultsHeading"><h3 ref={resultsHeading} tabIndex={-1}>{resultsTitle}</h3><span aria-live="polite">{loading?'جاري التحميل…':visible.length+' ملف'}</span></div>
  {loading?<div className="empty">جاري تحميل المهام…</div>:!visible.length?<div className="workflowEmpty"><span>✓</span><h3>لا توجد مهام ضمن هذا الاختيار</h3><p>{engineer?'تظهر المهمة هنا عندما تسندها الإدارة إليك.':'يمكن إسناد مهمة من فاتورة بيع المنظومة.'}</p></div>:visible.map(job=><JobCard key={engineer?job.id+':'+job.installationRevision:job.id} job={job} engineer={engineer} busy={busy!==null} change={change}/>)}
 </div>;
}
function JobCard({job,engineer,busy,change}){
 const index=installationIndex(job.installationStatus),report=job.installationReport||{};
 return <article className="workflowJob">
  <header><div><small>ملف #{receiptNumber(job)}</small><h3>{job.party||'عميل منظومة'}</h3>{job.warehouseName&&<small className="orderWarehouseLabel">{job.warehouseName}</small>}</div><span className={'workflowStatus '+job.installationStatus}>{stages[index][1]}</span></header>
  {!engineer&&job.sellingPrice!=null&&Number.isFinite(Number(job.sellingPrice))&&<div className="jobSalePrice"><span>سعر بيع المنظومة</span><strong><bdi>{fmt(job.sellingPrice)}</bdi> <small>د.ع</small></strong></div>}
  <div className="jobResponsible"><AppIcon name="user" size={17}/><span>المستخدم المسؤول <b>{job.creatorName||'غير محدد'}</b></span><PhoneActions phone={job.creatorPhone} label={'بالمسؤول '+job.creatorName}/></div>
  <ol className="workflowSteps" aria-label="مراحل التنصيب">{stages.map(([stage,label],i)=><li key={stage} className={i<=index?'reached':''} aria-current={i===index?'step':undefined}><span>{i<index||job.installationStatus==='closed'?'✓':i+1}</span><small>{label}</small></li>)}</ol>
  <WarehouseBadge status={job.warehouseStatus} compact/>
  <div className="jobDetails"><div><small>موعد التنصيب</small><b>{job.installDate||'لم يحدد'} • {job.installTime?.slice(0,5)||'الوقت غير محدد'}</b></div><div><small>مهندس التنصيب</small><b>{job.installerName||'غير مسند'}</b></div><div className="jobAddress"><small>العنوان</small><b>{job.customerAddress||'العنوان غير محدد'}</b></div></div>
  <div className="jobContact">{job.customerPhone?<PhoneActions phone={job.customerPhone} label={'بالزبون '+job.party}/>:<span>رقم الهاتف غير متوفر</span>}</div>
  <details className="jobMaterials" open><summary>مواد التنصيب <span>{job.items?.length||0} مادة</span></summary>{job.items?.length?job.items.map((item,i)=><div key={item.id||i}><span>{item.name}{item.brand&&<small>{item.brand}</small>}</span><b>× {fmt(item.qty)}</b></div>):<p>لا توجد مواد مسجلة</p>}</details>
  <div className="jobTimes">{job.installationStartedAt&&<span>بدء العمل: {dateText(job.installationStartedAt)}</span>}{job.installationCompletedAt&&<span>إرسال التقرير: {dateText(job.installationCompletedAt)}</span>}{job.installationClosedAt&&<span>إغلاق الملف: {dateText(job.installationClosedAt)}</span>}</div>
  {engineer&&job.installationStatus==='pending'&&<button className="workflowPrimary" disabled={busy||job.warehouseStatus!=='ready'} onClick={()=>change(job,'start')}>بدء التنصيب</button>}
  {engineer&&job.installationStatus==='in_progress'&&<CompletionReport busy={busy} onSubmit={payload=>change(job,'complete',payload)}/>}
  {report.submittedAt&&<div className="jobReport"><h4>تقرير المهندس</h4><p>{report.notes}</p>{(report.expenses||[]).map((e,i)=><div key={i}><span>{e.description}</span><b>{fmt(e.amount)} د.ع</b></div>)}<div><span>المصاريف المرفوعة للمراجعة</span><b>{fmt(report.expenseTotal)} د.ع</b></div></div>}
  {engineer&&job.installationStatus==='completed'&&<p className="workflowNotice">تم إرسال التقرير. الإدارة تراجع المصاريف وتغلق الملف.</p>}
  {engineer&&job.installationStatus==='closed'&&<p className="workflowNotice installationClosed"><AppIcon name="check" size={18}/> تم إنهاء التنصيب وإغلاق الملف من الإدارة.</p>}
  {job.canManage&&job.installationStatus!=='closed'&&(installationPaidExpense(job)>0||Number(job.installationExpenses)>0)&&<div className="cancelInstallationExpenses"><p>مصاريف التنصيب المدفوعة: {fmt(installationPaidExpense(job))} د.ع</p><button type="button" className="workflowSecondary" disabled={busy} onClick={()=>confirm('إلغاء مصاريف التنصيب وإرجاع المدفوع إلى قاصة صاحبه؟')&&change(job,'clear_expenses',{notes:'إلغاء مصاريف التنصيب المعتمدة'})}>إلغاء مصاريف التنصيب وإرجاعها للقاصة</button></div>}
  {job.canManage&&job.warehouseStatus==='ready'&&job.installationStatus!=='closed'&&<ApproveInstallation job={job} busy={busy} onSubmit={payload=>change(job,'close',payload)}/>}
  {job.canManage&&job.warehouseStatus!=='ready'&&job.installationStatus!=='closed'&&<p className="workflowNotice">بانتظار تجهيز المخزن. يظهر اعتماد المصاريف والغلق بعد التجهيز.</p>}
  {job.canManage&&job.installationStatus==='closed'&&<div className="jobFinancials"><div><small>المصاريف المعتمدة</small><b>{fmt(job.installationExpenses)} د.ع</b></div><div><small>الكلفة النهائية</small><b>{fmt(Number(job.cost||0)+Number(job.expenses||0)+Number(job.installationExpenses||0))} د.ع</b></div><div><small>الربح النهائي</small><b>{fmt(Number(job.total||0)-Number(job.cost||0)-Number(job.expenses||0)-Number(job.installationExpenses||0))} د.ع</b></div>{job.installationExpenseNotes&&<p>{job.installationExpenseNotes}</p>}<button disabled={busy} onClick={()=>confirm('إعادة فتح الملف للمراجعة؟ فتح الملف لا يلغي المصاريف؛ يمكنك إلغاءها أو تعديلها بعد الفتح.')&&change(job,'reopen')}>إعادة فتح للمراجعة</button></div>}
 </article>;
}
function CompletionReport({busy,onSubmit}){
 const [checks,setChecks]=useState({materials:false,tested:false,handover:false}),[notes,setNotes]=useState(''),[expenses,setExpenses]=useState([]),[error,setError]=useState('');
 const total=expenses.reduce((s,e)=>s+(Number(rawMoney(e.amount))||0),0);
 const submit=async e=>{e.preventDefault();setError('');if(!Object.values(checks).every(Boolean)||!notes.trim())return setError('أكمل الفحص واكتب ملخص التنفيذ.');const entered=expenses.filter(x=>rawMoney(x.amount)!=='');if(entered.some(x=>!Number.isFinite(Number(rawMoney(x.amount)))||Number(rawMoney(x.amount))<0||Number(rawMoney(x.amount))>1e9))return setError('أدخل مبلغاً صحيحاً للمصروف.');const actual=entered.filter(x=>Number(rawMoney(x.amount))>0).map(x=>({description:x.description.trim()||'مصروف',amount:Number(rawMoney(x.amount))}));if(!confirm('إرسال التقرير وتأكيد اكتمال التنصيب؟'))return;await onSubmit({checks,notes:notes.trim(),expenses:actual});};
 return <form className="completionForm" onSubmit={submit}><h4>تقرير إنجاز التنصيب</h4><fieldset disabled={busy}><legend>فحص وتسليم المنظومة</legend>{[['materials','تمت مطابقة وتركيب المواد'],['tested','تم فحص التشغيل والسلامة'],['handover','تم شرح التشغيل وتسليم المنظومة للزبون']].map(([key,label])=><label className="workflowCheck" key={key}><input type="checkbox" checked={checks[key]} onChange={e=>setChecks({...checks,[key]:e.target.checked})}/><span>{label}</span></label>)}
 <label className="workflowField">ملخص التنفيذ والملاحظات<textarea required maxLength={4000} value={notes} onChange={e=>setNotes(e.target.value)} placeholder="اكتب الأعمال المنجزة ونتيجة فحص التشغيل…"/></label>
 <h4>مصاريف المهمة</h4><p className="workflowHint">أضف المصاريف الفعلية لمراجعتها من الإدارة. إذا ماكو مصاريف، اترك القائمة فارغة.</p>
 {expenses.map((x,i)=><div className="expenseLine" key={i}><input aria-label={'بيان المصروف '+(i+1)} maxLength={500} placeholder="بيان المصروف (اختياري)" value={x.description} onChange={e=>setExpenses(expenses.map((v,k)=>k===i?{...v,description:e.target.value}:v))}/><input aria-label={'مبلغ المصروف '+(i+1)} inputMode="decimal" placeholder="المبلغ د.ع (اختياري)" value={moneyValue(x.amount)} onChange={e=>setExpenses(expenses.map((v,k)=>k===i?{...v,amount:rawMoney(e.target.value)}:v))}/><button type="button" className="expenseRemove" onClick={()=>setExpenses(expenses.filter((_,k)=>k!==i))}>حذف</button></div>)}
 <button type="button" className="workflowSecondary" disabled={expenses.length>=50} onClick={()=>setExpenses([...expenses,{description:'',amount:''}])}>＋ إضافة مصروف</button><div className="expenseTotal"><span>إجمالي مصاريف التقرير</span><b>{fmt(total)} د.ع</b></div>
 {error&&<p role="alert" className="workflowError">{error}</p>}<button className="workflowPrimary" type="submit">{busy?'جاري الإرسال…':'إكمال التنصيب وإرسال التقرير'}</button></fieldset></form>;
}
function ApproveInstallation({job,busy,onSubmit}){
 const [amount,setAmount]=useState(()=>approvedExpenseValue(job)),[notes,setNotes]=useState(job.installationExpenseNotes||''),[error,setError]=useState(''),[draftRevision,setDraftRevision]=useState(job.installationRevision);
 const stale=draftRevision!==job.installationRevision,paid=installationPaidExpense(job),difference=installationExpenseDifference(job,rawMoney(amount)),proposal=job.installationReport?.expenseTotal;
 const approved=rawMoney(amount)===''?0:Number(rawMoney(amount)),cost=Number(job.cost||0)+Number(job.expenses||0)+(Number.isFinite(approved)?approved:0);
 return <form className="approvalForm" onSubmit={async e=>{e.preventDefault();setError('');if(stale)return setError('تغيّر الملف؛ حمّل القيم الحالية قبل الاعتماد.');if(!Number.isFinite(approved)||approved<0||approved>1e9)return setError('أدخل مصاريف صحيحة.');if(confirm('تأكيد اعتماد المصاريف وإغلاق الملف؟ يُسجّل فرق المبلغ فقط.'))await onSubmit({amount:approved,notes:notes.trim()})}}>
  <h4>مراجعة الإدارة وإغلاق الملف</h4>{stale&&<div className="workflowError" role="alert">تغيّر الملف أثناء المراجعة.<button type="button" onClick={()=>{setAmount(approvedExpenseValue(job));setNotes(job.installationExpenseNotes||'');setDraftRevision(job.installationRevision);setError('');}}>تحميل القيم الحالية</button></div>}
  <p className="workflowHint">المدفوع فعليًا سابقًا: <b>{fmt(paid)} د.ع</b></p>{proposal!=null&&<p className="workflowHint">مقترح تقرير المهندس: <b>{fmt(proposal)} د.ع</b> <button type="button" disabled={busy||stale} onClick={()=>setAmount(String(proposal))}>استخدام مبلغ التقرير</button></p>}
  <label className="workflowField">المصاريف النهائية المعتمدة — د.ع<input aria-label="المصاريف النهائية للمنظومة" inputMode="decimal" value={moneyValue(amount)} disabled={busy||stale} placeholder="اختياري — الفارغ يعني 0" onChange={e=>setAmount(rawMoney(e.target.value))}/></label>
  <label className="workflowField">ملاحظات الاعتماد (اختياري)<textarea value={notes} maxLength={4000} disabled={busy||stale} placeholder="يمكن إغلاق الملف بدون كتابة سبب" onChange={e=>setNotes(e.target.value)}/></label>
  <div className="approvalTotals"><span>الكلفة النهائية <b>{fmt(cost)} د.ع</b></span><span>الربح النهائي <b>{fmt(Number(job.total||0)-cost)} د.ع</b></span></div>
  {Number.isFinite(difference)&&<p className="workflowHint expenseDifference" role="status">{difference>0?'المبلغ الإضافي المطلوب من القاصة: '+fmt(difference)+' د.ع':difference<0?'المبلغ الذي يرجع لقاصة من دفعه: '+fmt(-difference)+' د.ع':'لا يوجد صرف إضافي؛ المبلغ مسجل سابقًا.'}</p>}
  <p className="workflowHint">اعتماد الصفر يلغي أثر المصاريف السابقة ويرجع المدفوع لقاصة صاحبه. السجل يحفظ الصرف والإرجاع للتدقيق.</p>{error&&<p className="workflowError" role="alert">{error}</p>}<button className="workflowPrimary" disabled={busy||stale}>{busy?'جاري الاعتماد…':'اعتماد المصاريف وإغلاق الملف'}</button>
 </form>;
}
