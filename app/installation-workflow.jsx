'use client';
import AppIcon from './app-icons';
import WarehouseBadge from './warehouse-badge';
import {useCallback,useEffect,useRef,useState} from 'react';
import InstallationCalendar from './installation-calendar';
import {installationStages as stages,installationIndex,installationLocalDay} from './installation-utils.mjs';
import {saveRequest} from './save-request.mjs';
import {unlockNotificationSound,playNotificationSound} from './notification-sound.mjs';
import {supabase} from './supabase';
import {receiptNumber} from './supplier-utils.mjs';
const fmt=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2});
const rawMoney=value=>String(value??'').replace(/,/g,'').trim();
const moneyValue=value=>rawMoney(value)===''?'':fmt(rawMoney(value));
const dateText=value=>value?new Date(value).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad',dateStyle:'short',timeStyle:'short'}):'';
export default function InstallationWorkflow({profile,onChanged,selectedJob=''}){
 const [jobs,setJobs]=useState([]),[loading,setLoading]=useState(true),[error,setError]=useState(''),[status,setStatus]=useState(selectedJob?'all':'open'),[query,setQuery]=useState(selectedJob),[busy,setBusy]=useState(null),[message,setMessage]=useState('');
 const engineer=profile?.user_type==='installer';
 const request=useRef({seq:0,controller:null}),actionBusy=useRef(false);
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
   setMessage({start:'تم بدء التنصيب وتحديث المرحلة للجميع.',complete:'تم إنهاء التنصيب وإرسال التقرير للمراجعة.',close:'تم إغلاق الملف وتحديث المرحلة عند المهندس.',reopen:'تمت إعادة فتح الملف للمراجعة.'}[action]);
   void playNotificationSound();
   await refresh().catch(()=>setError('تم حفظ الخطوة. تعذر تحديث القائمة؛ اضغط تحديث لرؤية آخر حالة.'));
   if(onChanged)void Promise.resolve().then(onChanged).catch(()=>{});
   return true;
  }catch(e){setError(e.code==='P0002'?'رصيد قاصتك لا يكفي لدفع المصاريف. أضف الرصيد أو راجع المبلغ.':['40001','PT409'].includes(e.code)?'تغيّرت حالة الملف. تم تحديث المهام؛ راجعها وأعد المحاولة.':e.message?.includes('لم يصل تأكيد')?'لم يصل تأكيد العملية. حدّث المهام للتحقق من المرحلة قبل إعادة المحاولة.':'تعذر تنفيذ العملية. حدّث المهام وتأكد من الصلاحية والمرحلة الحالية.');await refresh().catch(()=>{});return false;}
  finally{actionBusy.current=false;setBusy(null);}
 }
 useEffect(()=>{const update=()=>{if(document.visibilityState==='visible'&&!actionBusy.current)refresh().catch(()=>{});};const timer=setInterval(update,5000);window.addEventListener('solar-notification',update);window.addEventListener('focus',update);document.addEventListener('visibilitychange',update);return()=>{clearInterval(timer);window.removeEventListener('solar-notification',update);window.removeEventListener('focus',update);document.removeEventListener('visibilitychange',update);};},[refresh]);
 const today=installationLocalDay(Date.now());
 const visible=jobs.filter(j=>(status==='all'||(status==='open'?j.installationStatus!=='closed':j.installationStatus===status))&&(!query||[j.party,j.customerPhone,j.customerAddress,j.installerName,j.creatorName,String(j.receiptNo),...(selectedJob?[String(j.id)]:[])].join(' ').includes(query.trim())));
 return <div className="workflow installationRefresh">
  <div className="workflowHero"><div><small>متابعة التنفيذ خطوة بخطوة</small><h2>{engineer?'مهامي الميدانية':'إدارة التنصيبات'}</h2><p>{engineer?'المواعيد والمواد وإنجاز خطواتك بمكان واحد':'جدول مشترك ومراحل موحّدة مع مهندس التنصيب'}</p></div><span aria-hidden="true"><AppIcon name="tools" size={26}/></span></div>
  <div className="workflowStats"><div><b>{jobs.filter(j=>j.installDate===today&&j.installationStatus!=='closed').length}</b><span>مواعيد اليوم</span></div><div><b>{jobs.filter(j=>j.installationStatus==='in_progress').length}</b><span>قيد التنفيذ</span></div><div><b>{jobs.filter(j=>j.installationStatus==='completed').length}</b><span>بانتظار المراجعة</span></div><div><b>{jobs.filter(j=>j.installationStatus==='closed').length}</b><span>مكتملة ومغلقة</span></div></div>
  <button className="installationCalendarToggle" aria-expanded={showCalendar} onClick={()=>setShowCalendar(v=>!v)}><AppIcon name="calendar" size={19}/> جدول مواعيد المهندسين <span>{showCalendar?'إخفاء':'عرض الحجوزات'}</span></button>
  {showCalendar&&<InstallationCalendar/>}
  <div className="workflowSearch"><input aria-label="بحث بالتنصيبات" value={query} onChange={e=>setQuery(e.target.value)} placeholder="بحث بالزبون، المستخدم أو الهاتف…"/><button disabled={loading||busy!==null} onClick={async()=>{setLoading(true);setError('');try{await refresh()}catch{setError('تعذر التحديث. تحقق من الاتصال.')}finally{setLoading(false)}}}>تحديث</button></div>
  <div className="statusTabs" aria-label="تصفية المهام">{[['open','المفتوحة'],...stages,['all','الكل']].map(([value,label])=><button key={value} aria-pressed={status===value} onClick={()=>setStatus(value)}>{label}</button>)}</div>
  {error&&<div className="workflowError" role="alert">{error}</div>}{message&&<div className="workflowSuccess" role="status">{message}</div>}
  {loading?<div className="empty">جاري تحميل المهام…</div>:!visible.length?<div className="workflowEmpty"><span>✓</span><h3>لا توجد مهام ضمن هذا الاختيار</h3><p>{engineer?'تظهر المهمة هنا عندما تسندها الإدارة إليك.':'يمكن إسناد مهمة من فاتورة بيع المنظومة.'}</p></div>:visible.map(job=><JobCard key={job.id+':'+job.installationRevision} job={job} engineer={engineer} busy={busy!==null} change={change}/>)}
 </div>;
}
function JobCard({job,engineer,busy,change}){
 const index=installationIndex(job.installationStatus),report=job.installationReport||{};
 const creatorPhone=String(job.creatorPhone||'').replace(/[^+0-9]/g,'');
 const phone=String(job.customerPhone||'').replace(/[^+0-9]/g,'');
 return <article className="workflowJob">
  <header><div><small>ملف #{receiptNumber(job)}</small><h3>{job.party||'عميل منظومة'}</h3>{job.warehouseName&&<small className="orderWarehouseLabel">{job.warehouseName}</small>}</div><span className={'workflowStatus '+job.installationStatus}>{stages[index][1]}</span></header>
  <div className="jobResponsible"><AppIcon name="user" size={17}/><span>المستخدم المسؤول <b>{job.creatorName||'غير محدد'}</b></span>{creatorPhone&&<a href={'tel:'+creatorPhone} aria-label={'اتصال بالمسؤول '+job.creatorName}><AppIcon name="phone" size={16}/><bdi>{job.creatorPhone}</bdi></a>}</div>
  <ol className="workflowSteps" aria-label="مراحل التنصيب">{stages.map(([stage,label],i)=><li key={stage} className={i<=index?'reached':''} aria-current={i===index?'step':undefined}><span>{i<index||job.installationStatus==='closed'?'✓':i+1}</span><small>{label}</small></li>)}</ol>
  <WarehouseBadge status={job.warehouseStatus} compact/>
  <div className="jobDetails"><div><small>موعد التنصيب</small><b>{job.installDate||'لم يحدد'} • {job.installTime?.slice(0,5)||'الوقت غير محدد'}</b></div><div><small>مهندس التنصيب</small><b>{job.installerName||'غير مسند'}</b></div><div className="jobAddress"><small>العنوان</small><b>{job.customerAddress||'العنوان غير محدد'}</b></div></div>
  <div className="jobContact">{phone?<a href={'tel:'+phone}>اتصال بالزبون · {job.customerPhone}</a>:<span>رقم الهاتف غير متوفر</span>}</div>
  <details className="jobMaterials" open><summary>مواد التنصيب <span>{job.items?.length||0} مادة</span></summary>{job.items?.length?job.items.map((item,i)=><div key={item.id||i}><span>{item.name}{item.brand&&<small>{item.brand}</small>}</span><b>× {fmt(item.qty)}</b></div>):<p>لا توجد مواد مسجلة</p>}</details>
  <div className="jobTimes">{job.installationStartedAt&&<span>بدء العمل: {dateText(job.installationStartedAt)}</span>}{job.installationCompletedAt&&<span>إرسال التقرير: {dateText(job.installationCompletedAt)}</span>}{job.installationClosedAt&&<span>إغلاق الملف: {dateText(job.installationClosedAt)}</span>}</div>
  {engineer&&job.installationStatus==='pending'&&<button className="workflowPrimary" disabled={busy||job.warehouseStatus!=='ready'} onClick={()=>change(job,'start')}>بدء التنصيب</button>}
  {engineer&&job.installationStatus==='in_progress'&&<CompletionReport busy={busy} onSubmit={payload=>change(job,'complete',payload)}/>}
  {report.submittedAt&&<div className="jobReport"><h4>تقرير المهندس</h4><p>{report.notes}</p>{(report.expenses||[]).map((e,i)=><div key={i}><span>{e.description}</span><b>{fmt(e.amount)} د.ع</b></div>)}<div><span>المصاريف المرفوعة للمراجعة</span><b>{fmt(report.expenseTotal)} د.ع</b></div></div>}
  {engineer&&job.installationStatus==='completed'&&<p className="workflowNotice">تم إرسال التقرير. الإدارة تراجع المصاريف وتغلق الملف.</p>}
  {engineer&&job.installationStatus==='closed'&&<p className="workflowNotice installationClosed"><AppIcon name="check" size={18}/> تم إنهاء التنصيب وإغلاق الملف من الإدارة.</p>}
  {job.canManage&&job.warehouseStatus==='ready'&&job.installationStatus!=='closed'&&<ApproveInstallation job={job} busy={busy} onSubmit={payload=>change(job,'close',payload)}/>}
  {job.canManage&&job.warehouseStatus!=='ready'&&job.installationStatus!=='closed'&&<p className="workflowNotice">بانتظار تجهيز المخزن. يظهر اعتماد المصاريف والغلق بعد التجهيز.</p>}
  {job.canManage&&job.installationStatus==='closed'&&<div className="jobFinancials"><div><small>المصاريف المعتمدة</small><b>{fmt(job.installationExpenses)} د.ع</b></div><div><small>الكلفة النهائية</small><b>{fmt(Number(job.cost||0)+Number(job.expenses||0)+Number(job.installationExpenses||0))} د.ع</b></div><div><small>الربح النهائي</small><b>{fmt(Number(job.total||0)-Number(job.cost||0)-Number(job.expenses||0)-Number(job.installationExpenses||0))} د.ع</b></div>{job.installationExpenseNotes&&<p>{job.installationExpenseNotes}</p>}<button disabled={busy} onClick={()=>confirm('إعادة فتح الملف لمراجعة المصاريف؟')&&change(job,'reopen')}>إعادة فتح للمراجعة</button></div>}
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
 const [amount,setAmount]=useState(String(job.installationExpenses||job.installationReport?.expenseTotal||0)),[notes,setNotes]=useState(job.installationExpenseNotes||''),[error,setError]=useState('');
 const approved=rawMoney(amount)===''?0:Number(rawMoney(amount)),cost=Number(job.cost||0)+Number(job.expenses||0)+(Number.isFinite(approved)?approved:0);
 return <form className="approvalForm" onSubmit={async e=>{e.preventDefault();setError('');if(!Number.isFinite(approved)||approved<0||approved>1e9)return setError('أدخل مصاريف صحيحة.');if(confirm('تأكيد دفع المصاريف من قاصتك وإغلاق الملف؟ إذا سبق الدفع يُسجل الفرق فقط.'))await onSubmit({amount:approved,notes:notes.trim()})}}><h4>مراجعة الإدارة وإغلاق الملف</h4><label className="workflowField">المصاريف النهائية المعتمدة — د.ع<input aria-label="المصاريف النهائية للمنظومة" inputMode="decimal" value={moneyValue(amount)} disabled={busy} placeholder="اختياري — الفارغ يعني 0" onChange={e=>setAmount(rawMoney(e.target.value))}/></label><label className="workflowField">ملاحظات الاعتماد (اختياري)<textarea value={notes} maxLength={4000} disabled={busy} placeholder="يمكن إغلاق الملف بدون كتابة سبب" onChange={e=>setNotes(e.target.value)}/></label><div className="approvalTotals"><span>الكلفة النهائية <b>{fmt(cost)} د.ع</b></span><span>الربح النهائي <b>{fmt(Number(job.total||0)-cost)} د.ع</b></span></div><p className="workflowHint">عند الغلق تُخصم المصاريف من قاصتك مباشرة. إعادة الغلق تخصم الزيادة فقط؛ التخفيض يعيد الفرق لقاصة من دفعه أولاً.</p>{error&&<p className="workflowError" role="alert">{error}</p>}<button className="workflowPrimary" disabled={busy}>{busy?'جاري الاعتماد…':'اعتماد المصاريف وإغلاق الملف'}</button></form>;
}
