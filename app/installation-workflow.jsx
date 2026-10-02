'use client';
import {useEffect,useState} from 'react';
import {supabase} from './supabase';
const stages=[['pending','موعد محدد'],['in_progress','جاري التنصيب'],['completed','مراجعة التقرير'],['closed','ملف مغلق']];
const fmt=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2});
const dateText=value=>value?new Date(value).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad',dateStyle:'short',timeStyle:'short'}):'';
export default function InstallationWorkflow({profile,onChanged}){
 const [jobs,setJobs]=useState([]),[loading,setLoading]=useState(true),[error,setError]=useState(''),[status,setStatus]=useState('open'),[query,setQuery]=useState(''),[busy,setBusy]=useState(null),[message,setMessage]=useState('');
 const engineer=profile?.user_type==='installer';
 async function refresh(){const {data,error}=await supabase.rpc('solar_installation_jobs');if(error)throw error;setJobs(data||[]);}
 useEffect(()=>{let live=true;supabase.rpc('solar_installation_jobs').then(({data,error})=>{if(!live)return;if(error)setError('تعذر تحميل المهام. اضغط تحديث للمحاولة مجدداً.');else setJobs(data||[]);setLoading(false)});return()=>{live=false}},[]);
 async function change(job,action,payload={}){
  if(busy!==null)return false;setBusy(job.id);setError('');setMessage('');
  try{
   const {error}=await supabase.rpc('solar_installation_action',{job_id:job.id,expected_revision:job.installationRevision,action,payload});
   if(error)throw error;
   await refresh();
   setMessage({start:'تم بدء التنصيب وتسجيل الوقت.',complete:'تم إرسال تقريرك للإدارة. الملف بانتظار المراجعة.',close:'تم إغلاق الملف واعتماد المصاريف والربح.',reopen:'تمت إعادة فتح الملف للمراجعة.'}[action]);
   if(onChanged)await onChanged();
   return true;
  }catch(e){setError(e.code==='40001'?'تغيّرت حالة الملف. تم تحديث المهام؛ راجعها وأعد المحاولة.':'تعذر تنفيذ العملية. حدّث المهام وتأكد من الصلاحية والمرحلة الحالية.');await refresh().catch(()=>{});return false;}
  finally{setBusy(null)}
 }
 const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const visible=jobs.filter(j=>(status==='all'||(status==='open'?j.installationStatus!=='closed':j.installationStatus===status))&&(!query||[j.party,j.customerPhone,j.customerAddress,j.installerName,String(j.id)].join(' ').includes(query.trim())));
 return <div className="workflow">
  <div className="workflowHero"><div><small>متابعة التنفيذ خطوة بخطوة</small><h2>{engineer?'مهامي الميدانية':'إدارة التنصيبات'}</h2><p>{engineer?'موعدك، موادك، وتقرير إنجازك بمكان واحد':'متابعة المهندس، مراجعة التقرير، ثم اعتماد الكلفة النهائية'}</p></div><span aria-hidden="true">☀</span></div>
  <div className="workflowStats"><div><b>{jobs.filter(j=>j.installDate===today&&j.installationStatus!=='closed').length}</b><span>مواعيد اليوم</span></div><div><b>{jobs.filter(j=>j.installationStatus==='in_progress').length}</b><span>قيد التنفيذ</span></div><div><b>{jobs.filter(j=>j.installationStatus==='completed').length}</b><span>بانتظار المراجعة</span></div></div>
  <div className="workflowSearch"><input aria-label="بحث بالتنصيبات" value={query} onChange={e=>setQuery(e.target.value)} placeholder="بحث بالزبون، الهاتف أو العنوان…"/><button disabled={loading||busy!==null} onClick={async()=>{setLoading(true);setError('');try{await refresh()}catch{setError('تعذر التحديث. تحقق من الاتصال.')}finally{setLoading(false)}}}>تحديث</button></div>
  <div className="statusTabs" aria-label="تصفية المهام">{[['open','المفتوحة'],...stages,['all','الكل']].map(([value,label])=><button key={value} aria-pressed={status===value} onClick={()=>setStatus(value)}>{label}</button>)}</div>
  {error&&<div className="workflowError" role="alert">{error}</div>}{message&&<div className="workflowSuccess" role="status">{message}</div>}
  {loading?<div className="empty">جاري تحميل المهام…</div>:!visible.length?<div className="workflowEmpty"><span>✓</span><h3>لا توجد مهام ضمن هذا الاختيار</h3><p>{engineer?'تظهر المهمة هنا عندما تسندها الإدارة إليك.':'يمكن إسناد مهمة من فاتورة بيع المنظومة.'}</p></div>:visible.map(job=><JobCard key={job.id+':'+job.installationRevision} job={job} engineer={engineer} busy={busy!==null} change={change}/>)}
 </div>;
}
function JobCard({job,engineer,busy,change}){
 const index=stages.findIndex(([s])=>s===job.installationStatus),report=job.installationReport||{};
 const phone=String(job.customerPhone||'').replace(/[^+0-9]/g,'');
 return <article className="workflowJob">
  <header><div><small>ملف #{String(job.id).slice(-6)}</small><h3>{job.party||'عميل منظومة'}</h3></div><span className={'workflowStatus '+job.installationStatus}>{stages[index]?.[1]||job.installationStatus}</span></header>
  <ol className="workflowSteps" aria-label="مراحل التنصيب">{stages.map(([stage,label],i)=><li key={stage} className={i<=index?'reached':''} aria-current={i===index?'step':undefined}><span>{i<index?'✓':i+1}</span><small>{label}</small></li>)}</ol>
  <div className="jobDetails"><div><small>موعد التنصيب</small><b>{job.installDate||'لم يحدد'} • {job.installTime?.slice(0,5)||'الوقت غير محدد'}</b></div><div><small>مهندس التنصيب</small><b>{job.installerName||'غير مسند'}</b></div><div className="jobAddress"><small>العنوان</small><b>{job.customerAddress||'العنوان غير محدد'}</b></div></div>
  <div className="jobContact">{phone?<a href={'tel:'+phone}>اتصال بالزبون · {job.customerPhone}</a>:<span>رقم الهاتف غير متوفر</span>}</div>
  <details className="jobMaterials" open><summary>مواد التنصيب <span>{job.items?.length||0} مادة</span></summary>{job.items?.length?job.items.map((item,i)=><div key={item.id||i}><span>{item.name}{item.brand&&<small>{item.brand}</small>}</span><b>× {fmt(item.qty)}</b></div>):<p>لا توجد مواد مسجلة</p>}</details>
  <div className="jobTimes">{job.installationStartedAt&&<span>بدء العمل: {dateText(job.installationStartedAt)}</span>}{job.installationCompletedAt&&<span>إرسال التقرير: {dateText(job.installationCompletedAt)}</span>}{job.installationClosedAt&&<span>إغلاق الملف: {dateText(job.installationClosedAt)}</span>}</div>
  {engineer&&job.installationStatus==='pending'&&<button className="workflowPrimary" disabled={busy} onClick={()=>change(job,'start')}>بدء التنصيب</button>}
  {engineer&&job.installationStatus==='in_progress'&&<CompletionReport busy={busy} onSubmit={payload=>change(job,'complete',payload)}/>}
  {report.submittedAt&&<div className="jobReport"><h4>تقرير المهندس</h4><p>{report.notes}</p>{(report.expenses||[]).map((e,i)=><div key={i}><span>{e.description}</span><b>{fmt(e.amount)} د.ع</b></div>)}<div><span>المصاريف المرفوعة للمراجعة</span><b>{fmt(report.expenseTotal)} د.ع</b></div></div>}
  {engineer&&job.installationStatus==='completed'&&<p className="workflowNotice">تم إرسال التقرير. الإدارة تراجع المصاريف وتغلق الملف.</p>}
  {job.canManage&&job.installationStatus==='completed'&&<ApproveInstallation job={job} busy={busy} onSubmit={payload=>change(job,'close',payload)}/>}
  {job.canManage&&job.installationStatus==='closed'&&<div className="jobFinancials"><div><small>المصاريف المعتمدة</small><b>{fmt(job.installationExpenses)} د.ع</b></div><div><small>الكلفة النهائية</small><b>{fmt(Number(job.cost||0)+Number(job.expenses||0)+Number(job.installationExpenses||0))} د.ع</b></div><div><small>الربح النهائي</small><b>{fmt(Number(job.total||0)-Number(job.cost||0)-Number(job.expenses||0)-Number(job.installationExpenses||0))} د.ع</b></div>{job.installationExpenseNotes&&<p>{job.installationExpenseNotes}</p>}<button disabled={busy} onClick={()=>confirm('إعادة فتح الملف لمراجعة المصاريف؟')&&change(job,'reopen')}>إعادة فتح للمراجعة</button></div>}
 </article>;
}
function CompletionReport({busy,onSubmit}){
 const [checks,setChecks]=useState({materials:false,tested:false,handover:false}),[notes,setNotes]=useState(''),[expenses,setExpenses]=useState([]),[error,setError]=useState('');
 const total=expenses.reduce((s,e)=>s+Number(e.amount||0),0);
 const submit=async e=>{e.preventDefault();setError('');if(!Object.values(checks).every(Boolean)||!notes.trim())return setError('أكمل الفحص واكتب ملخص التنفيذ.');if(expenses.some(x=>!x.description.trim()||!Number.isFinite(Number(x.amount))||Number(x.amount)<=0||Number(x.amount)>1e9))return setError('أدخل بياناً ومبلغاً صحيحاً لكل مصروف.');if(!confirm('إرسال التقرير وتأكيد اكتمال التنصيب؟'))return;await onSubmit({checks,notes:notes.trim(),expenses:expenses.map(x=>({description:x.description.trim(),amount:Number(x.amount)}))});};
 return <form className="completionForm" onSubmit={submit}><h4>تقرير إنجاز التنصيب</h4><fieldset disabled={busy}><legend>فحص وتسليم المنظومة</legend>{[['materials','تمت مطابقة وتركيب المواد'],['tested','تم فحص التشغيل والسلامة'],['handover','تم شرح التشغيل وتسليم المنظومة للزبون']].map(([key,label])=><label className="workflowCheck" key={key}><input type="checkbox" checked={checks[key]} onChange={e=>setChecks({...checks,[key]:e.target.checked})}/><span>{label}</span></label>)}
 <label className="workflowField">ملخص التنفيذ والملاحظات<textarea required maxLength={4000} value={notes} onChange={e=>setNotes(e.target.value)} placeholder="اكتب الأعمال المنجزة ونتيجة فحص التشغيل…"/></label>
 <h4>مصاريف المهمة</h4><p className="workflowHint">أضف المصاريف الفعلية لمراجعتها من الإدارة. إذا ماكو مصاريف، اترك القائمة فارغة.</p>
 {expenses.map((x,i)=><div className="expenseLine" key={i}><input aria-label={'بيان المصروف '+(i+1)} maxLength={500} placeholder="بيان المصروف" value={x.description} onChange={e=>setExpenses(expenses.map((v,k)=>k===i?{...v,description:e.target.value}:v))}/><input aria-label={'مبلغ المصروف '+(i+1)} type="number" min=".01" max="1000000000" step=".01" placeholder="المبلغ د.ع" value={x.amount} onChange={e=>setExpenses(expenses.map((v,k)=>k===i?{...v,amount:e.target.value}:v))}/><button type="button" className="expenseRemove" onClick={()=>setExpenses(expenses.filter((_,k)=>k!==i))}>حذف</button></div>)}
 <button type="button" className="workflowSecondary" disabled={expenses.length>=50} onClick={()=>setExpenses([...expenses,{description:'',amount:''}])}>＋ إضافة مصروف</button><div className="expenseTotal"><span>إجمالي مصاريف التقرير</span><b>{fmt(total)} د.ع</b></div>
 {error&&<p role="alert" className="workflowError">{error}</p>}<button className="workflowPrimary" type="submit">{busy?'جاري الإرسال…':'إكمال التنصيب وإرسال التقرير'}</button></fieldset></form>;
}
function ApproveInstallation({job,busy,onSubmit}){
 const [amount,setAmount]=useState(String(job.installationExpenses||job.installationReport?.expenseTotal||0)),[notes,setNotes]=useState(job.installationExpenseNotes||''),[error,setError]=useState('');
 const cost=Number(job.cost||0)+Number(job.expenses||0)+Number(amount||0);
 return <form className="approvalForm" onSubmit={async e=>{e.preventDefault();setError('');if(!Number.isFinite(Number(amount))||amount===''||Number(amount)<0||Number(amount)>1e9)return setError('أدخل مصاريف صحيحة.');if(Number(amount)!==Number(job.installationReport?.expenseTotal||0)&&!notes.trim())return setError('اكتب سبب تعديل المصاريف عن تقرير المهندس.');if(confirm('اعتماد المصاريف وإغلاق الملف بالربح النهائي؟'))await onSubmit({amount:Number(amount),notes:notes.trim()})}}><h4>مراجعة الإدارة وإغلاق الملف</h4><label className="workflowField">المصاريف المعتمدة — د.ع<input type="number" min="0" max="1000000000" step=".01" required value={amount} disabled={busy} onChange={e=>setAmount(e.target.value)}/></label><label className="workflowField">ملاحظات الاعتماد / سبب تعديل المصاريف<textarea value={notes} maxLength={4000} disabled={busy} onChange={e=>setNotes(e.target.value)}/></label><div className="approvalTotals"><span>الكلفة النهائية <b>{fmt(cost)} د.ع</b></span><span>الربح النهائي <b>{fmt(Number(job.total||0)-cost)} د.ع</b></span></div><p className="workflowHint">اعتماد المصاريف يحتسب كلفة المنظومة؛ تسجيل دفعها من القاصة يتم من حركات الصندوق.</p>{error&&<p className="workflowError" role="alert">{error}</p>}<button className="workflowPrimary" disabled={busy}>{busy?'جاري الاعتماد…':'اعتماد المصاريف وإغلاق الملف'}</button></form>;
}
