'use client';
import {userDisplayName} from './user-name-utils.mjs';

import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import MoneyInput from './money-input';
import ProfitMovement from './profit-movement';
import CashRecordEditor from './cash-record-editor';
import ProfitRejection from './profit-rejection';
import ProfitTargetForm from './profit-target-form';
import {isAdministrator} from './access-utils.mjs';
import {readProfitTargetAttempt,saveProfitTarget,retryProfitTarget,PROFIT_TARGET_EVENT} from './profit-target.mjs';
import ReportActions from './report-actions';
import {money,escapeHtml as e,dateKey} from './supplier-utils.mjs';
import {profitStatementRows,profitStatementDocument} from './profit-statement-report.mjs';
import {convertAmount} from './fx-utils.mjs';
const MODEL='owner_debit_supplier_charge';
const statusName={pending:'بانتظار قرار الإدارة',approved:'تمت التسوية',rejected:'مرفوض',cancelled:'ملغى'};
function allocationDocument(r){
 if(r?.settlement_model!==MODEL)return '';
 const supplier=r.supplier_receipt;
 const share='<p>حصة '+e(r.ownerName)+': '+money(r.share)+' د.ع</p>';
 const cash='<p>رصيد قاصته قبل التسوية: '+money(r.receipt?.beforeIQD)+' د.ع · بعد التسوية: '+money(r.receipt?.afterIQD)+' د.ع</p>';
 let allocation='';
 if(supplier){
  allocation='<p>زيادة دين المورد '+e(supplier.name)+': '+money(supplier.amount,supplier.currency)+' '+(supplier.currency==='USD'?'$':'د.ع')+' · المقابل '+money(r.supplier_amount_iqd)+' د.ع</p><p>دين المورد قبل الإضافة: '+money(supplier.beforeBalance,supplier.currency)+' · بعد الإضافة: '+money(supplier.afterBalance,supplier.currency)+'</p>';
 }else if(r.supplier_amount_iqd!=null){
  allocation='<p>حصة الشركة '+money(r.supplier_amount_iqd)+' د.ع</p>';
 }
 return '<div class="notes"><b>توزيع ربح الفترة</b>'+share+cash+allocation+'</div>';
}
export default function ProfitSettlements({profile,staff=[],onChanged,a4,hidden=false,onPending,tx}){
 const admin=!!profile.is_admin,[owner,setOwner]=useState(profile.id),[from,setFrom]=useState(''),[to,setTo]=useState(dateKey(new Date())),[data,setData]=useState(null),[error,setError]=useState(''),[message,setMessage]=useState(''),[busy,setBusy]=useState(false),[loading,setLoading]=useState(true),[revision,setRevision]=useState(0),[selected,setSelected]=useState(null),[share,setShare]=useState(''),[percent,setPercent]=useState(''),[supplierId,setSupplierId]=useState(''),[preview,setPreview]=useState(''),[note,setNote]=useState(''),[requestNote,setRequestNote]=useState(''),[historyOpen,setHistoryOpen]=useState(false);
 const [rejecting,setRejecting]=useState(null),[editingSettlement,setEditingSettlement]=useState(false);
 const pending=useRef(null),lock=useRef(false),sequence=useRef(0),panel=useRef(null);
 const canAdjust=isAdministrator(profile);
 const [savedExternal,setSavedExternal]=useState(null),[externalError,setExternalError]=useState('');
 const externalAttempt=canAdjust&&savedExternal?.actorId===profile.id?savedExternal:null;
 const operationLocked=busy||!!pending.current||!!externalAttempt;
 const actor=useRef(profile.id);
 actor.current=profile.id;
 useEffect(()=>{
  if(!canAdjust){setSavedExternal(null);return;}
  function sync(){
   const attempt=readProfitTargetAttempt(profile.id);
   setSavedExternal(attempt);
   if(attempt)setOwner(attempt.payload.ownerId);
  }
  sync();
  window.addEventListener(PROFIT_TARGET_EVENT,sync);
  window.addEventListener('storage',sync);
  return ()=>{window.removeEventListener(PROFIT_TARGET_EVENT,sync);window.removeEventListener('storage',sync);};
 },[canAdjust,profile.id]);
 function chooseOwner(next){
  if(operationLocked)return;
  setOwner(next);setSelected(null);setPreview('');setMessage('');setError('');setExternalError('');
 }
 async function adjustProfit(payload){
  if(!canAdjust||lock.current||pending.current)return false;
  const adminId=profile.id;
  lock.current=true;setBusy(true);setError('');setExternalError('');setMessage('');
  try {
   const receipt=payload?await saveProfitTarget(adminId,payload):await retryProfitTarget(adminId);
   if(actor.current!==adminId)return false;
   setMessage('تم حفظ رصيد الأرباح الجديد: '+money(receipt.after)+' د.ع.');
   setLoading(true);setRevision(n=>n+1);
   void Promise.resolve().then(()=>onChanged?.()).catch(()=>{});
   return true;
  } catch(err) {
   if(actor.current!==adminId)return false;
   const uncertain=readProfitTargetAttempt(adminId);
   setExternalError(uncertain?'تعذّر تأكيد نتيجة الحفظ. أعد تأكيد العملية بنفس البيانات.':err.message||'تعذّر تعديل رصيد الأرباح.');
   if(!uncertain)setRevision(n=>n+1);
   return false;
  } finally {lock.current=false;if(actor.current===adminId)setBusy(false);}
 }
 const load=useCallback(async()=>{
  const seq=++sequence.current;setLoading(true);setError('');
  try{const {data:result,error}=await supabase.rpc('solar_profit_workspace',{action:'overview',payload:{ownerId:admin?owner:profile.id,from,to}});if(error)throw error;if(seq!==sequence.current)return;setData(result);onPending?.(result.requests.filter(r=>r.status==='pending').length);}
  catch(err){if(seq===sequence.current){setData(null);setError(err.message);}}finally{if(seq===sequence.current)setLoading(false);}
 },[admin,owner,profile.id,from,to,onPending]);
 useEffect(()=>{load();return()=>{sequence.current++;};},[load,revision,tx]);
 useEffect(()=>{const refresh=()=>{if(!lock.current)setRevision(n=>n+1);};window.addEventListener('solar-notification',refresh);const timer=setInterval(refresh,30000);return()=>{window.removeEventListener('solar-notification',refresh);clearInterval(timer);};},[]);
 useEffect(()=>{if(selected&&!hidden)panel.current?.scrollIntoView({block:'start',behavior:'smooth'});},[selected?.id,hidden]);
 function choose(r){if(operationLocked)return;setExternalError('');if(admin){setOwner(r.owner_id);setFrom(r.date_from||'');setTo(r.date_to);}setSelected(r);setShare('');setPercent('');setSupplierId('');setPreview('');setNote('');setError('');setMessage('');}
 async function act(action,payload){
  if(lock.current||canAdjust&&readProfitTargetAttempt(profile.id))return;lock.current=true;setBusy(true);setError('');setMessage('');
  try{
   const signature=JSON.stringify({action,payload});if(pending.current&&pending.current.signature!==signature)throw new Error('أعد تأكيد الطلب السابق أولًا.');
   if(!pending.current)pending.current={id:crypto.randomUUID(),action,payload,signature};
   const {data:result,error}=await supabase.rpc('solar_profit_workspace',{action,request_id:pending.current.id,payload});if(error)throw error;
   pending.current=null;setSelected(null);setRejecting(null);setRequestNote('');setPreview('');setMessage(action==='approve'?'تمت التسوية: خُصمت حصة المستخدم من قاصته وأُضيف الباقي إلى دين المورد.':action==='request'?'تم إرسال طلبك وإشعار الإدارة.':action==='reject'?'تم رفض الطلب وإشعار المستخدم. تبقى أرباحه بدون تسوية.':'تم حفظ القرار.');
   setRevision(n=>n+1);try{await onChanged?.();}catch{setMessage('تم الحفظ. حدّث بيانات البرنامج لإظهار الحركة.');}return result;
  }catch(err){if(err.code)pending.current=null;setPreview('');setError(err.code?err.message:'لم يتأكد رد الحفظ؛ اضغط إعادة التأكيد بنفس البيانات. لن تتكرر الحركة.');if(['40001','PT409'].includes(err.code))setRevision(n=>n+1);}
  finally{lock.current=false;setBusy(false);}
 }
 const requests=data?.requests||[],rows=data?.rows||[],waiting=requests.filter(r=>r.status==='pending'),ownPending=waiting.some(r=>r.owner_id===(admin?owner:profile.id)),amount=Number(share),remaining=Number(selected?.profit||0)-amount,box=data?.cashOwners?.find(o=>o.id===selected?.owner_id),supplier=data?.suppliers?.find(s=>String(s.id)===supplierId),rate=supplier?.currency==='USD'?Number(supplier?.rate||0):1,supplierAmount=rate>0?convertAmount(Math.max(0,remaining),'IQD',supplier?.currency||'IQD',rate):0,valid=selected?.status==='pending'&&share.trim()!==''&&amount>=0&&Number.isInteger(amount)&&remaining>=0&&(remaining===0||!!supplier&&supplierAmount>0);
 const payload={id:selected?.id,expectedToken:selected?.token,share:amount,cashOwnerId:selected?.owner_id,collectionConfirmed:true,settlementModel:MODEL,supplierId:remaining>0?supplier?.id:null,supplierToken:remaining>0?supplier?.token:null,supplierRate:remaining>0?rate:null,note},signature=JSON.stringify(payload),reviewed=preview===signature;
 const ownerChoices=new Map();
 if(canAdjust){
  for(const user of data?.cashOwners||[])ownerChoices.set(user.id,{id:user.id,display_name:user.name,active:true});
  for(const user of staff)ownerChoices.set(user.id,user);
  if(!ownerChoices.has(profile.id))ownerChoices.set(profile.id,profile);
 }
 const externalRows=rows.filter(row=>row.kind==='external_adjustment');
 const current=rows.filter(row=>row.kind!=='external_adjustment').reduce((sum,row)=>sum+Number(row.value),0);
 const externalDelta=externalRows.reduce((sum,row)=>sum+Number(row.adjustment.delta),0);
 const settled=rows.reduce((sum,row)=>sum+Number(row.settled),0);
 const snapshotBody=selected?'<div class="meta"><div>المستخدم: '+e(selected.ownerName)+'</div><div>الفترة: '+e(selected.date_from||'البداية')+' — '+e(selected.date_to)+'</div><div>الحالة: '+e(statusName[selected.status])+'</div><div>حصة المستخدم: '+money(selected.share||0)+' د.ع</div></div>'+allocationDocument(selected)+profitStatementRows(selected.snapshot,selected.profit,{snapshot:true}):'';
 const requestList=(list)=><div className="staffProfitRequests">{list.map(r=><div key={r.id} className={'profitRequestCard '+r.status}><button type="button" disabled={operationLocked} className={'profitRequest '+r.status} onClick={()=>choose(r)}><span><b>{r.ownerName}</b><small>{r.date_from||'البداية'} — {r.date_to}</small><small>{statusName[r.status]}</small>{r.status==='rejected'&&r.decision_note&&<small className="profitRejectedReason">{r.decision_note}</small>}</span><span><b><bdi>{money(r.profit)}</bdi> د.ع</b>{r.status==='approved'&&<small>حصته: {money(r.share)} د.ع</small>}</span></button>{admin&&r.status==='pending'&&<div className="profitRequestQuickActions"><button type="button" className="profitReviewButton" disabled={operationLocked} onClick={()=>choose(r)}>مراجعة وتسوية</button><button type="button" className="profitRejectButton" aria-label={'رفض طلب '+r.ownerName} disabled={operationLocked} onClick={()=>{setError('');setRejecting(r);}}>رفض الطلب</button></div>}</div>)}</div>;
 return <section className="staffProfit" style={hidden?{display:'none'}:undefined}>
  {rejecting&&<ProfitRejection key={rejecting.id} request={rejecting} initialNote={selected?.id===rejecting.id?note:''} busy={busy} uncertain={!!pending.current} error={error} onClose={()=>setRejecting(null)} onReject={reason=>act('reject',pending.current?.payload||{id:rejecting.id,expectedToken:rejecting.token,note:reason})}/>}
  <header className="staffProfitHead"><div><h1>{admin?'تسويات أرباح المستخدمين':'أرباحي'}</h1><p>{admin?'راجع أرصدة الأرباح وطلبات توزيعها.':'اطلب تسوية أرباح الفترة؛ الطلب مستقل عن رصيد قاصتك.'}</p></div><button className="uiButton" disabled={operationLocked} onClick={()=>setRevision(n=>n+1)}>تحديث</button></header>
  {error&&<p role="alert" className="accountAlert error">{error}</p>}{message&&<p role="status" className="accountAlert">{message}</p>}{pending.current&&<button className="uiButton primary" disabled={busy} onClick={()=>act(pending.current.action,pending.current.payload)}>إعادة تأكيد العملية</button>}
  {canAdjust&&<ProfitTargetForm key={profile.id+':'+owner} owner={owner} staff={[...ownerChoices.values()]}
   data={data} loading={loading} busy={busy} blocked={!!pending.current} pending={externalAttempt} error={externalError}
   onOwner={chooseOwner} onSave={adjustProfit} onRetry={()=>adjustProfit(null)}/>}
  {admin&&<section className="uiPanel profitPendingPanel"><div className="panelTitle"><h2>طلبات بانتظار الموافقة</h2><span>{waiting.length}</span></div>{waiting.length?requestList(waiting):<p className="uiEmpty">لا توجد طلبات بانتظار قرارك.</p>}</section>}
  {selected&&<section ref={panel} className="uiPanel profitApproval" aria-label="مراجعة طلب التسوية"><div className="panelTitle"><h2>{selected.ownerName} · {statusName[selected.status]}</h2><button className="uiButton" disabled={operationLocked} onClick={()=>setSelected(null)}>إغلاق</button></div><div className="profitSplitTotal"><span>ربح الفترة المطلوب توزيعه</span><strong><bdi>{money(selected.profit)}</bdi> د.ع</strong><small>{selected.date_from||'البداية'} — {selected.date_to}</small></div>{selected.note&&<p>{selected.note}</p>}
   {selected.status==='pending'?<><fieldset disabled={operationLocked}>{admin&&<><div className="profitSplitFields"><label>حصة المستخدم · د.ع<MoneyInput aria-label="حصة المستخدم بالدينار" value={share} onChange={v=>{setShare(v);setPercent('');}}/></label><label>نسبة الحصة % · اختياري<input aria-label="نسبة حصة المستخدم" type="number" min="0" max="100" step="0.01" value={percent} onChange={ev=>{setPercent(ev.target.value);setShare(ev.target.value?String(Math.round(Number(selected.profit)*Number(ev.target.value)/100)):'');}}/></label></div>
    {remaining>0&&<label className="profitSupplierChoice">المورد المستفيد من بقية الأرباح<select aria-label="مورد بقية الأرباح" value={supplierId} onChange={ev=>setSupplierId(ev.target.value)}><option value="">اختر المورد</option>{data?.suppliers?.map(s=><option key={s.id} value={s.id}>{s.name} · {s.currency==='USD'?'دولار':'دينار'}</option>)}</select></label>}
    {share.trim()!==''&&amount>=0&&<div className="profitAllocationPreview" aria-label="معاينة توزيع الأرباح"><div><span>حصة {selected.ownerName}</span><b><bdi>{money(amount)}</bdi> د.ع</b></div><div><span>رصيد قاصته الآن</span><b><bdi>{money(box?.balance||0)}</bdi> د.ع</b></div><div className={Number(box?.balance||0)-amount<0?'negative':''}><span>رصيد قاصته بعد التسوية</span><b><bdi>{money(Number(box?.balance||0)-amount)}</bdi> د.ع</b></div><div className="supplierRemainder"><span>بقية الربح · زيادة دين المورد</span><b><bdi>{money(remaining)}</bdi> د.ع</b></div>{supplier&&remaining>0&&<><div><span>الإضافة إلى {supplier.name}</span><b><bdi>{money(supplierAmount,supplier.currency)}</bdi> {supplier.currency==='USD'?'$':'د.ع'}</b></div>{supplier.currency==='USD'&&<small>الصرف المثبت: {money(rate)} د.ع لكل دولار</small>}<div><span>دين المورد قبل الإضافة</span><b><bdi>{money(supplier.balance,supplier.currency)}</bdi> {supplier.currency==='USD'?'$':'د.ع'}</b></div><div><span>دين المورد بعد الإضافة</span><b><bdi>{money(Number(supplier.balance)+supplierAmount,supplier.currency)}</bdi> {supplier.currency==='USD'?'$':'د.ع'}</b></div></>}</div>}
    <p className="formHint">حصة المستخدم تُسجّل مصروفًا وتُخصم من قاصته حتى لو صار رصيدها سالبًا. الباقي زيادة دين للمورد بدون صرف نقدي.</p></>}
    <label>{admin?'ملاحظة التسوية · اختياري':'سبب الإلغاء · اختياري'}<textarea aria-label="ملاحظة قرار التسوية" value={note} maxLength={1500} onChange={ev=>setNote(ev.target.value)}/></label></fieldset>
    <div className="profitDecisionButtons">{admin?<>{reviewed?<button className="uiButton primary" disabled={operationLocked||!valid} onClick={()=>act('approve',payload)}>تأكيد حفظ التسوية</button>:<button className="uiButton primary" disabled={operationLocked||!valid} onClick={()=>setPreview(signature)}>معاينة واعتماد التوزيع</button>}<button className="uiButton danger" disabled={operationLocked} onClick={()=>{setError('');setRejecting(selected);}}>رفض الطلب</button></>:<button className="uiButton danger" disabled={operationLocked} onClick={()=>act('cancel',{id:selected.id,expectedToken:selected.token,note})}>إلغاء طلبي</button>}</div>{admin&&reviewed&&<p className="profitReviewReady" role="status">راجع الأرقام أعلاه، ثم اضغط تأكيد حفظ التسوية.</p>}</>:<>{selected.status==='approved'&&<div className="profitSettlementResult"><p>حصة المستخدم: <b><bdi>{money(selected.share)}</bdi> د.ع</b></p>{selected.receipt&&<p>{selected.settlement_model===MODEL?'رصيد قاصته بعد التسوية:':'قاصة الصرف: '+selected.receipt.ownerName+' · المبلغ:'} <bdi>{money(selected.settlement_model===MODEL?selected.receipt.afterIQD:selected.share)}</bdi> د.ع</p>}{selected.settlement_model===MODEL&&!selected.supplier_receipt&&selected.supplier_amount_iqd!=null&&<p>حصة الشركة <b><bdi>{money(selected.supplier_amount_iqd)}</bdi> د.ع</b></p>}{selected.supplier_receipt&&<><p>زيادة دين {selected.supplier_receipt.name}: <b><bdi>{money(selected.supplier_receipt.amount,selected.supplier_receipt.currency)}</bdi> {selected.supplier_receipt.currency==='USD'?'$':'د.ع'}</b></p>{selected.supplier_receipt.afterBalance!=null&&<p>دين المورد بعد الإضافة: <bdi>{money(selected.supplier_receipt.afterBalance,selected.supplier_receipt.currency)}</bdi> {selected.supplier_receipt.currency==='USD'?'$':'د.ع'}</p>}</>}</div>}<p className={selected.status==='rejected'?'profitRejectedReason':undefined}>{selected.decision_note}</p><p>القرار بواسطة: {selected.decidedByName} · {selected.decided_at?dateKey(selected.decided_at):''}</p></>}
   {admin&&selected.status==='approved'&&selected.settlement_model===MODEL&&<div className="profitApprovedEdit">{editingSettlement?<CashRecordEditor key={selected.id} movementId={'profit:'+selected.id} profile={profile} onCancel={()=>setEditingSettlement(false)} onSaved={()=>{setEditingSettlement(false);setSelected(null);setRevision(n=>n+1);setMessage('تم تعديل التسوية وتحديث القاصة وحساب المورد.');if(onChanged)void Promise.resolve().then(onChanged).catch(()=>{});}}/>:<button type="button" className="uiButton" disabled={operationLocked} onClick={()=>setEditingSettlement(true)}>تعديل التسوية المعتمدة</button>}</div>}
   <ReportActions enabled={!busy} html={a4('كشف تسوية أرباح المستخدم',snapshotBody,money(selected.profit)+' د.ع')} filename="كشف-تسوية-أرباح"/>
  </section>}
  <section className="uiPanel"><fieldset disabled={operationLocked}><div className="formGrid profitFilters">{admin&&!canAdjust&&<label>كشف المستخدم<select aria-label="مستخدم كشف التسوية" value={owner} onChange={ev=>chooseOwner(ev.target.value)}>{staff.filter(u=>!['installer','warehouse'].includes(u.user_type)).map(u=><option key={u.id} value={u.id}>{userDisplayName(u)}</option>)}</select></label>}<label>من<input aria-label="من تاريخ أرباحي" type="date" value={from} max={to} onChange={ev=>setFrom(ev.target.value)}/></label><label>إلى<input aria-label="إلى تاريخ أرباحي" type="date" value={to} min={from||undefined} max={dateKey(new Date())} onChange={ev=>setTo(ev.target.value)}/></label></div></fieldset></section>
  {loading?<p role="status">جاري تحميل كشف الأرباح…</p>:data&&<><div className="staffProfitMetrics"><article className="available"><span>الرصيد المتبقي بعد التسوية · كل الفترات</span><b><bdi data-testid="staff-profit-current-balance">{money(data.retainedProfit)}</bdi> <small>د.ع</small></b></article><article><span>ربح الفترة قبل التسويات</span><b><bdi>{money(current)}</bdi> <small>د.ع</small></b></article><article><span>المسوّى من حركات الفترة</span><b><bdi>{money(settled)}</bdi> <small>د.ع</small></b></article></div>{externalRows.length>0&&<div className="profitExternalPeriodTotal"><span>صافي تعديلات الرصيد الخارجية في الفترة</span><b><bdi>{money(externalDelta)}</bdi> د.ع</b></div>}<p className="profitBalanceNotice">المتاح للتسوية ضمن الفترة المختارة: <b>{money(data.available)} د.ع</b>. الرصيد الحالي يشمل أرباح جميع الفترات وتعديلات الرصيد والتوزيعات المعتمدة.</p>
   <section className="uiPanel"><div className="panelTitle"><h2>كشف أرباح {data.ownerName}</h2><span>{rows.length} حركة</span></div><div className="reportScopeStrip"><strong>الفترة المختارة</strong><span>{from||'البداية'} — {to}</span><span>الدينار العراقي · IQD</span></div><p className="reportReadingHint">الكشف المطبوع يشمل جميع حركات الفترة، بما فيها المسوّاة. القائمة أدناه تعرض الحركات التي بقي عليها ربح غير مسوّى.</p><ReportActions enabled html={a4('كشف أرباح المستخدم',profitStatementDocument(data,from,to),money(data.retainedProfit)+' د.ع · المتبقي الحالي')} filename="كشف-أرباحي"/><div className="staffProfitRows">{rows.filter(r=>Number(r.available)!==0).map(r=><ProfitMovement key={(admin?owner:profile.id)+r.key} row={r} ownerId={admin?owner:profile.id} a4={a4}/>)}{!rows.some(r=>Number(r.available)!==0)&&<p className="uiEmpty">لا توجد أرباح غير مسوّاة ضمن الفترة.</p>}</div>
    {data.canRequest&&<form className="staffProfitRequest" onSubmit={ev=>{ev.preventDefault();act('request',{ownerId:owner,from,to,expectedToken:data.token,note:requestNote});}}><label>ملاحظة للإدارة<input aria-label="ملاحظة طلب التسوية" value={requestNote} maxLength={2000} disabled={operationLocked} onChange={ev=>setRequestNote(ev.target.value)} placeholder="اختياري"/></label><button className="uiButton primary" disabled={operationLocked||ownPending||Number(data.available)<=0}>{ownPending?'طلب بانتظار موافقة الإدارة':'طلب تسوية أرباح الفترة'}</button><small>طلب التسوية يعتمد على أرباح الفترة، ولا يشترط وجود رصيد في القاصة.</small></form>}
   </section>
   <section className="uiPanel"><div className="panelTitle"><h2>{admin?'سجل التسويات':'طلباتي والتسويات السابقة'}</h2><button type="button" className="uiButton" aria-expanded={historyOpen} onClick={()=>setHistoryOpen(v=>!v)}>{historyOpen?'إخفاء السجل':'عرض السجل'}</button></div>{!admin&&requestList(waiting)}{historyOpen&&requestList(requests.filter(r=>r.status!=='pending'))}</section>
  </>}
 </section>;
}
