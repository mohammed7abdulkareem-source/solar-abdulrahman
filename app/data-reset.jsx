'use client';
import {useRef,useState} from 'react';
import {supabase,verifyResetPassword} from './supabase';

const CONFIRMATION='تصفير بيانات عبدالرحمن سولار';
const labels={'public.transactions':'الفواتير والحركات المالية','public.transaction_items':'فقرات الفواتير','public.products':'المواد والمخزون','public.brands':'البراندات','public.customers':'الزبائن','public.suppliers':'الموردون','public.cash_ledger':'حركات الصندوق','public.solar_cash_entries':'حركات قواصي المستخدمين','solar_private.cash_transfers':'تحويلات القاصة','public.solar_quotes':'مسودات التحصيل','public.solar_price_estimates':'عروض أسعار محفوظة','public.solar_estimate_specs':'إعدادات مواد عروض الأسعار','public.solar_notifications':'الإشعارات','solar_private.supplier_payment_requests':'طلبات تسديد الموردين','solar_private.receipt_counters':'عدادات ترقيم الوصولات'};

export default function DataReset({onReset}){
 const [open,setOpen]=useState(false),[plan,setPlan]=useState(null),[password,setPassword]=useState(''),[confirmation,setConfirmation]=useState(''),[downloaded,setDownloaded]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[success,setSuccess]=useState(null);
 const lock=useRef(false);
 async function run(fn){if(lock.current)return;lock.current=true;setBusy(true);setError('');try{await fn()}catch(e){setError(e.message||'تعذر تنفيذ العملية')}finally{lock.current=false;setBusy(false)}}
 function close(){if(busy)return;setOpen(false);setPlan(null);setPassword('');setConfirmation('');setDownloaded(false);setError('')}
 async function prepare(){await run(async()=>{
  setPlan(null);setPassword('');setConfirmation('');setDownloaded(false);setSuccess(null);
  const {data,error}=await supabase.rpc('solar_prepare_reset');if(error)throw new Error(error.message||'تعذر تجهيز النسخة الاحتياطية');setPlan(data);
 })}
 async function download(){await run(async()=>{
  const {data,error}=await supabase.rpc('solar_reset_backup',{request_id:plan.requestId});if(error)throw new Error('تعذر تنزيل النسخة الاحتياطية. حاول مجدداً.');
  const url=URL.createObjectURL(new Blob([JSON.stringify(data,null,2)],{type:'application/json'}));
  const a=document.createElement('a');a.href=url;a.download='solar-backup-'+data.backupId+'.json';document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);setDownloaded(true);
 })}
 async function reset(e){e.preventDefault();if(!plan||!downloaded||confirmation!==CONFIRMATION||!password)return;
  await run(async()=>{
   await verifyResetPassword(password);
   if(!confirm('تم التحقق من الباسورد. سيتم حذف بيانات العمل لجميع المستخدمين. حسابات الدخول تبقى محفوظة. هل تؤكد تنفيذ التصفير؟')){setPassword('');return;}
   const {data,error}=await supabase.functions.invoke('solar-reset-data',{body:{requestId:plan.requestId,password,confirmation}});setPassword('');
   if(error){let message='لم يتأكد تنفيذ التصفير. أعد تحميل بيانات البرنامج وتحقق قبل المحاولة.';try{message=(await error.context?.json())?.error||message}catch{}throw new Error(message)}
   if(!data?.ok)throw new Error(data?.error||'لم يتأكد تنفيذ التصفير');
   setSuccess(data);setPlan(null);setConfirmation('');setDownloaded(false);
   try{await onReset?.()}catch{setError('تم التصفير. أعد تحميل البرنامج لعرض البيانات الجديدة.')}
  })
 }
 return <section className="resetSection"><h3>تصفير البيانات</h3><p>حذف بيانات العمل والبدء من جديد. هذا الخيار للأدمن فقط.</p><button className="resetOpen" onClick={()=>setOpen(true)}>فتح خيارات تصفير البيانات</button>
 {open&&<div className="resetPanel"><div className="resetPanelHead"><h4>تصفير بيانات البرنامج</h4><button onClick={close} disabled={busy}>إغلاق</button></div><p className="resetWarning">يشمل جميع المستخدمين: الفواتير والمشتريات والتسديدات والمصاريف ورأس المال، قواصي المستخدمين والتحويلات، التنصيبات، المخزون والمواد والبراندات، الزبائن والموردين، المسودات والإشعارات. يبدأ ترقيم الوصولات من جديد.</p><p>تبقى حسابات المستخدمين والباسوردات والصلاحيات، وسجل التدقيق والنسخ الاحتياطية محفوظة.</p><button onClick={prepare} disabled={busy}>{busy?'جاري التنفيذ…':plan?'إعادة المعاينة والنسخ الاحتياطي':'معاينة البيانات وحفظ نسخة احتياطية'}</button>
 {plan&&<><div className="resetCounts">{Object.entries(plan.counts).filter(([,n])=>n>0).map(([key,count])=><div key={key}><span>{labels[key]||key}</span><b>{Number(count).toLocaleString('en-US')}</b></div>)}</div>{Object.values(plan.counts).every(n=>n===0)&&<p>لا توجد بيانات عمل حالياً.</p>}<p className="resetHint">المعاينة صالحة 15 دقيقة. إذا تغيرت البيانات، يجب إعادة المعاينة.</p><button onClick={download} disabled={busy}>{downloaded?'تنزيل النسخة الاحتياطية مرة أخرى':'تنزيل النسخة الاحتياطية قبل التصفير'}</button><form onSubmit={reset}><fieldset disabled={busy}><label>باسورد حساب الأدمن<input aria-label="باسورد التصفير" type="password" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} required/></label><label>اكتب: {CONFIRMATION}<input aria-label="عبارة تأكيد التصفير" value={confirmation} onChange={e=>setConfirmation(e.target.value)} autoComplete="off" required/></label><button className="resetExecute" disabled={!downloaded||!password||confirmation!==CONFIRMATION||busy}>{busy?'جاري التحقق والتنفيذ…':'التحقق من الباسورد ومتابعة التصفير'}</button></fieldset></form></>}
 {success&&<p className="workflowSuccess" role="status">تم تصفير بيانات العمل بنجاح. النسخة الاحتياطية محفوظة برقم: {success.backupId}</p>}{error&&<p className="workflowError" role="alert">{error}</p>}
 </div>}
 </section>;
}
