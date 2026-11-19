'use client';
import {userDisplayName} from './user-name-utils.mjs';

import {useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import MoneyInput from './money-input';
import ReportActions from './report-actions';
import AppIcon from './app-icons';
import SalesTrend from './sales-trend';
import ProfitSettlements from './profit-settlements';
import ProfitTransfer from './profit-transfer';
import ProfitMovement from './profit-movement';
import {dateKey,money} from './supplier-utils.mjs';
import {cashOwner} from './access-utils.mjs';
import {companyInvoiceCost,companyMovementTotals} from './company-profit-figures.mjs';
import {cashReceiptBody} from './cash-utils.mjs';
import PendingSystems from './pending-systems';
import {profitBalanceReport,companySaleExpenses,profitSalesBreakdown} from './profit-balance-report.mjs';
import './company-profit.css';

const sections=[
 ['overview','نظرة عامة','chart'],['sales','المبيعات والمنظومات','receipt'],
 ['movements','المصاريف والحركات','wallet'],['settled','التسويات والتوزيع','exchange'],['export','تصدير التقرير','download']
];
const saleLabels={all:'الجملة والمنظومات المغلقة',sale:'بيع الجملة',system:'المنظومات المغلقة'};
function ProfitAmount({value,id}){
 return <b className={value!=null&&Number(value)<0?'profitNegative':undefined} data-testid={id}>
  {value!=null?<><bdi dir="ltr">{money(value)}</bdi> <small>د.ع</small></>:'—'}
 </b>;
}
function Figure({label,value,id}){
 return <div className="companyFigure"><dt>{label}</dt><dd><ProfitAmount value={value} id={id}/></dd></div>;
}
function LedgerItems({rows,a4,empty}){
 if(!rows.length)return <p className="companyProfitEmpty">{empty}</p>;
 return <div className="companyLedgerList">{rows.slice().reverse().map(row=><ProfitMovement key={row.ownerId+':'+row.key}
  row={row} ownerId={row.ownerId} a4={a4} meta={'أثر الحركة '+money(row.value)+' د.ع · غير المسوّى '+money(row.available)+' د.ع'}/>)}</div>;
}

export default function ProfitWorkspace(props){
 const [tab,setTab]=useState(props.profile.is_admin?(props.initialTab||'company'):'settlements'),[pendingCount,setPendingCount]=useState(0);
 return <>{props.profile.is_admin&&<nav className="profitWorkspaceTabs" aria-label="تقارير وتسوية الأرباح"><button type="button" aria-pressed={tab==='company'} className={tab==='company'?'active':''} onClick={()=>setTab('company')}>أرباح الشركة</button><button type="button" aria-pressed={tab==='settlements'} className={tab==='settlements'?'active':''} onClick={()=>setTab('settlements')}>تسويات المستخدمين {pendingCount>0?'· '+pendingCount:''}</button></nav>}{!props.profile.is_admin&&<PendingSystems a4={props.a4} ownerId={props.profile.id} revision={props.tx}/>}<ProfitSettlements {...props} hidden={tab!=='settlements'} onPending={setPendingCount}/>{props.profile.is_admin&&tab==='company'&&<CompanyProfitWorkspace {...props}/>}</>;
}
function CompanyProfitWorkspace({tx,profile,staff=[],onChanged,a4}){
 const [section,setSection]=useState('overview');
 const admin=!!profile.is_admin,[owner,setOwner]=useState(admin?'all':profile.id),[from,setFrom]=useState(''),[to,setTo]=useState(''),[type,setType]=useState('all'),[distribution,setDistribution]=useState(''),[note,setNote]=useState(''),[cashSnapshot,setCashSnapshot]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[receipt,setReceipt]=useState(null),[refresh,setRefresh]=useState(0);
 const [assignments,setAssignments]=useState([]),[transferOpen,setTransferOpen]=useState(false),[selectedProfit,setSelectedProfit]=useState([]),[transferLocked,setTransferLocked]=useState(false),[transferMessage,setTransferMessage]=useState('');
 const [balanceLoaded,setBalanceLoaded]=useState(null),[balanceError,setBalanceError]=useState(null);
 const balanceKey=JSON.stringify([profile.id,admin,owner,from,to,type]);
 const balance=balanceLoaded?.key===balanceKey&&balanceLoaded.tx===tx&&balanceLoaded.refresh===refresh?balanceLoaded.data:null;
 useEffect(()=>{let live=true;setBalanceError(null);supabase.rpc('solar_profit_workspace',{action:'balance',payload:{ownerId:owner,from,to,type}}).then(({data,error})=>{if(!live)return;if(error)throw error;setBalanceLoaded({key:balanceKey,tx,refresh,data});}).catch(err=>{if(live)setBalanceError({key:balanceKey,tx,refresh,message:err.message||'تعذر تأكيد رصيد الأرباح. أعد التحديث.'});});return()=>{live=false;};},[balanceKey,owner,from,to,type,tx,refresh]);
 const pending=useRef(null);
 useEffect(()=>{let live=true;supabase.rpc('solar_profit_transfer',{action:'list'}).then(({data,error})=>{if(!live)return;if(error){setError(error.message);return;}setAssignments(data.assignments||[]);});return()=>{live=false;};},[tx,refresh]);
 const profitOwners=new Map(assignments.map(r=>[Number(r.invoiceId),r.ownerId]));
 useEffect(()=>{let live=true;setCashSnapshot(null);if(admin&&owner!=='all')supabase.rpc('solar_cash_workspace',{payload:{ownerId:owner,limit:1}}).then(({data,error})=>{if(error)throw error;if(live)setCashSnapshot({owner,tx,refresh,data});}).catch(err=>live&&setError(err.message));return()=>{live=false;};},[owner,admin,tx,refresh]);
 const cash=cashSnapshot?.owner===owner&&cashSnapshot.tx===tx&&cashSnapshot.refresh===refresh?cashSnapshot.data:null;
 const sourceRows=new Map((balance?.rows||[]).map(r=>[r.key,r]));
 // The confirmed ledger has already applied Baghdad dates, beneficiary, sale type and system closure.
 const rows=tx.filter(t=>['sale','system'].includes(t.kind)&&sourceRows.get('tx:'+t.id)?.kind===t.kind).map(t=>{
  const sales=Number(t.kind==='system'?t.total:t.subtotal??t.total??0),cost=companyInvoiceCost(t);
  const source=sourceRows.get('tx:'+t.id);
  return {...t,sales,cost,earned:Number(source.value),settled:Number(source.settled),available:Number(source.available),profitOwnerId:source.ownerId};
 });
 const totals=rows.reduce((s,t)=>({sales:s.sales+t.sales,cost:s.cost+t.cost,profit:s.profit+t.earned}),{sales:0,cost:0,profit:0});
 const companyExpenses=companySaleExpenses(rows);
 const ledger=balance?.rows||[];
 const {expenses,fx,externalProfit}=companyMovementTotals(ledger);
 const net=balance?.period.earned,unallocated=balance?.remaining;
 const available=Math.max(0,Number(cash?.retainedProfit||0)),amount=Number(distribution),valid=!!cash&&amount>0&&amount<=available&&amount<=Number(cash.summary.IQD)&&amount<=1e12;
 async function save(event){event.preventDefault();if(busy||!valid)return;setBusy(true);setError('');const payload={ownerId:owner,mode:'distribution',currency:'IQD',amount,note:note.trim()||'توزيع أرباح'},signature=JSON.stringify(payload);
  try{if(pending.current&&pending.current.signature!==signature)throw new Error('أعد تأكيد الطلب السابق بنفس البيانات.');if(!pending.current)pending.current={id:crypto.randomUUID(),signature};const {data,error}=await supabase.rpc('solar_cash_save',{request_id:pending.current.id,payload});if(error)throw error;pending.current=null;setReceipt(data);setDistribution('');setNote('');setRefresh(n=>n+1);try{await onChanged?.();}catch{setError('تم التوزيع؛ حدّث البيانات لإظهاره.');}}
  catch(err){if(err.code)pending.current=null;setError(err.code?err.message:'لم يتأكد رد الحفظ؛ أعد تأكيده بنفس البيانات ولن تتكرر الحركة.');}finally{setBusy(false);}
 }
 const ownerName=owner==='all'?'جميع المستخدمين':userDisplayName(staff.find(u=>u.id===owner)||profile);
 const reportBody=section==='export'&&balance?profitBalanceReport({balance,ownerName,from,to,rows,expenses,fx,externalProfit,type}):'';
 const reportError=balanceError?.key===balanceKey&&balanceError.tx===tx&&balanceError.refresh===refresh?balanceError.message:'';
 const today=dateKey(new Date()),currentPeriod=(from||'البداية')+' — '+(to||'اليوم');
 const scopeLocked=busy||!!pending.current||transferLocked;
 const movements=ledger.filter(r=>!['sale','system','personal_distribution','external_adjustment'].includes(r.kind));
 const settledMovements=ledger.filter(r=>Number(r.settled)!==0||['personal_distribution','external_adjustment'].includes(r.kind));
 const subtotalByKind=balance?profitSalesBreakdown(rows).filter(group=>type==='all'||type===group.kind):[];

 function clearTransfer(){
  setTransferOpen(false);setSelectedProfit([]);setTransferMessage('');
 }
 function selectOwner(value){
  clearTransfer();setOwner(value);setReceipt(null);setError('');setCashSnapshot(null);setDistribution('');setNote('');
 }
 function selectSection(value){
  if(scopeLocked)return;
  setSection(value);
 }
 function transferSaved(result){
  setTransferOpen(false);setSelectedProfit([]);
  setTransferMessage('تم حفظ تغيير الأرباح: '+money(result.total)+' د.ع إلى '+result.ownerName+'.');
  setRefresh(n=>n+1);window.dispatchEvent(new Event('solar-notification'));
  Promise.resolve().then(()=>onChanged?.()).catch(()=>setError('تم الحفظ؛ حدّث البيانات لإظهار بقية الأقسام.'));
 }
 const distributionForm=<details className="distributionDetails companyDistribution" key={owner} open={owner!=='all'||undefined}>
  <summary>سحب أرباح الإدارة</summary><form className="uiPanel distributionForm" onSubmit={save}>
   <p>يُخصم المبلغ من الأرباح المتاحة ومن قاصة المستخدم المختار. لتحديد حصة الموظف افتح «تسويات المستخدمين».</p>
   {owner==='all'?<p className="fxNotice">اختر مستخدمًا من تصفية التقرير لعرض أرباحه المتاحة وقاصته قبل التوزيع.</p>:cash?<>
    <dl className="companyFigures"><Figure label="الربح المتاح للتوزيع · كل الفترات" value={available}/>
     <Figure label={'دينار قاصة '+cash.ownerName} value={cash.summary.IQD}/></dl>
    <fieldset disabled={busy||!!pending.current}><div className="formGrid"><label>المبلغ الموزع · د.ع<MoneyInput value={distribution} onChange={setDistribution} aria-label="مبلغ توزيع الأرباح" required/></label>
     <label>بيان التوزيع<input value={note} onChange={e=>setNote(e.target.value)} maxLength={2000} placeholder="المستلم أو سبب التوزيع"/></label></div></fieldset>
    <button className="uiButton primary" type="submit" disabled={busy||!valid}>{busy?'جاري الحفظ…':pending.current?'إعادة تأكيد الحفظ':'حفظ التوزيع وخصمه من القاصة'}</button>
   </>:<p role="status">جاري تحميل القاصة والأرباح المتاحة…</p>}
  </form>
 </details>;
 return <section className="profitWorkspace companyProfit" dir="rtl" aria-label="تقرير أرباح الشركة">
  <header className="companyProfitHead"><div><span className="companyProfitIcon"><AppIcon name="chart" size={24}/></span><h1>أرباح الشركة</h1></div>
   <button type="button" disabled={scopeLocked} className="companyProfitRefresh" onClick={()=>setRefresh(n=>n+1)}><AppIcon name="refresh" size={16}/>تحديث</button>
  </header>
  <div className="companyProfitTotals">
   <article className="companyProfitPeriod"><span><AppIcon name="chart" size={18}/>ربح الفترة قبل التسويات</span>
    <ProfitAmount value={net} id="profit-period-earned"/><small>{currentPeriod} · {ownerName}</small></article>
   <article className="companyProfitCurrent"><span><AppIcon name="wallet" size={18}/>الأرباح المتبقية بعد التسوية</span>
    <ProfitAmount value={unallocated} id="profit-current-balance"/><small>الرصيد الحالي · جميع الفترات</small></article>
  </div>
  <nav className="companyProfitNav" aria-label="أقسام تقرير أرباح الشركة">{sections.map(([key,label,icon])=>
   <button key={key} type="button" aria-pressed={section===key} disabled={scopeLocked&&section!==key} onClick={()=>selectSection(key)}>
    <AppIcon name={icon} size={18}/><span>{label}</span></button>)}</nav>
  <details className="companyProfitFilters" open><summary><span><AppIcon name="filter" size={17}/>تصفية التقرير</span>
   <small aria-label="نطاق تقرير الأرباح">{ownerName} · {saleLabels[type]}</small></summary>
   <fieldset disabled={scopeLocked} className="companyFilterFields">
    <label>صاحب الربح<select aria-label="مستخدم تقرير الأرباح" value={owner} onChange={e=>selectOwner(e.target.value)}><option value="all">جميع المستخدمين</option>
     {staff.filter(u=>!['installer','warehouse'].includes(u.user_type)).map(u=><option value={u.id} key={u.id}>{userDisplayName(u)}</option>)}</select></label>
    <label>نوع المبيعات<select aria-label="نوع مبيعات تقرير الأرباح" value={type} onChange={e=>{clearTransfer();setType(e.target.value);}}>{Object.entries(saleLabels).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></label>
    <label>من تاريخ<input aria-label="بداية فترة الأرباح" type="date" value={from} max={to||today} onChange={e=>{clearTransfer();setFrom(e.target.value);}}/></label>
    <label>إلى تاريخ<input aria-label="نهاية فترة الأرباح" type="date" value={to} min={from||undefined} max={today} onChange={e=>{clearTransfer();setTo(e.target.value);}}/></label>
    {(from||to)&&<button type="button" className="companyClearPeriod" onClick={()=>{clearTransfer();setFrom('');setTo('');}}>كل الفترات</button>}
   </fieldset>
  </details>
  {reportError?<div role="alert" className="accountAlert error">{reportError}<button type="button" className="uiButton" onClick={()=>setRefresh(n=>n+1)}>إعادة تحميل الأرباح</button></div>
   :!balance&&<p className="companyReportStatus" role="status">جاري تأكيد رصيد الأرباح والتسويات…</p>}
  {section==='overview'&&<div className="companyProfitView" aria-label="نظرة عامة">
   <section className="uiPanel profitResultSummary"><h2>نتائج الفترة المختارة</h2>
    <dl className="companyFigures">
     <Figure label="إجمالي المبيعات" value={balance?totals.sales:null}/><Figure label="الكلفة المثبتة" value={balance?totals.cost:null}/>
     <Figure label="ربح المبيعات" value={balance?totals.profit:null}/><Figure label="المصاريف الفعلية" value={balance?-expenses:null}/>
     <Figure label="الأرباح الخارجية" value={balance?externalProfit:null}/><Figure label="فرق الصرف المحقّق" value={balance?fx:null}/>
    </dl>
    {companyExpenses>0&&balance&&<p className="companyAccountingNote">يتضمن ربح المبيعات مصاريف وصولات جملة تحمّلتها الشركة بمبلغ <ProfitAmount value={companyExpenses}/>.</p>}
   </section>
   {balance&&<SalesTrend rows={rows} from={from} to={to} title="المبيعات والكلفة" subtitle={from?'من '+from+' إلى '+(to||today):to?'آخر 14 يومًا حتى '+to:'آخر 14 يومًا'}/>}
  </div>}
  {section==='sales'&&<div className="companyProfitView" aria-label="المبيعات والمنظومات">
   <section className="uiPanel"><h2>الأرباح حسب نوع البيع</h2>
    <div className="companySaleGroups">{subtotalByKind.map(group=>
     <article key={group.kind} data-profit-sale-kind={group.kind}><header><h3>{group.label}</h3><small>{group.count} فاتورة</small></header>
      <dl className="companyFigures"><Figure label="المبيعات" value={group.sales}/><Figure label="الكلفة" value={group.cost}/>
       <Figure label="ربح الفواتير" value={group.profit}/><div className="companyFigure"><dt>هامش الربح</dt><dd>{group.marginPercent==null?'غير محتسب':<bdi dir="ltr">{money(group.marginPercent)}%</bdi>}</dd></div></dl>
     </article>)}</div>
   </section>
   <section className="uiPanel"><div className="companySectionHeading"><h2>تفاصيل فواتير البيع</h2>{balance&&<small>{rows.length} فاتورة</small>}</div>
    <div className="profitTransferTools"><button type="button" className="uiButton" disabled={transferLocked||!balance||!rows.length} onClick={()=>{setTransferOpen(v=>!v);setSelectedProfit([]);setTransferMessage('');}}>تحويل الأرباح لمستخدم آخر</button></div>
    {transferMessage&&<p role="status" className="accountAlert">{transferMessage}</p>}
    {transferOpen&&<ProfitTransfer rows={rows.filter(r=>selectedProfit.includes(r.id))} staff={staff} onLocked={setTransferLocked} onClose={clearTransfer} onSaved={transferSaved}/>}
    {balance&&<div className="profitList">{rows.length?rows.slice().reverse().map(t=><article className="profitRow profitCompanyRow" key={t.id}>
     {transferOpen&&<label className="profitTransferCheck"><input type="checkbox" aria-label={'تحويل ربح الفاتورة '+(t.receiptNo||t.id)} disabled={transferLocked} checked={selectedProfit.includes(t.id)} onChange={ev=>setSelectedProfit(ids=>ev.target.checked?[...ids,t.id]:ids.filter(id=>id!==t.id))}/></label>}
     <ProfitMovement row={{key:'tx:'+t.id,date:t.date,label:(t.kind==='system'?'منظومة':'بيع جملة')+' · '+(t.party||'نقدي'),receiptNo:t.receiptNo,value:t.earned,available:t.available,settled:t.settled}}
      ownerId={t.profitOwnerId||profitOwners.get(Number(t.id))||cashOwner(t)} a4={a4}
      meta={'الربح '+money(t.earned)+' د.ع · الكلفة '+money(t.cost)+' د.ع'+(profitOwners.has(Number(t.id))?' · صاحب الربح '+(staff.find(u=>u.id===profitOwners.get(Number(t.id)))?.display_name||'مستخدم'):'')}/>
    </article>):<p className="companyProfitEmpty">لا توجد مبيعات ضمن الاختيارات.</p>}</div>}
   </section>
   {type!=='sale'&&<PendingSystems a4={a4} ownerId={owner==='all'?null:owner} from={from} to={to} revision={tx}/>}
  </div>}
  {section==='movements'&&<section className="uiPanel companyProfitView" aria-label="المصاريف والحركات"><h2>المصاريف والحركات الأخرى</h2>
   <dl className="companyFigures"><Figure label="المصاريف التشغيلية" value={balance?expenses:null}/><Figure label="فرق الصرف المحقّق" value={balance?fx:null}/><Figure label="الأرباح الخارجية" value={balance?externalProfit:null}/></dl>
   {companyExpenses>0&&balance&&<p className="companyAccountingNote">مصاريف وصولات الجملة على الشركة <ProfitAmount value={companyExpenses}/>، وهي مخصومة ضمن ربح الفواتير.</p>}
   <h3>حركات الفترة</h3>{balance&&<LedgerItems rows={movements} a4={a4} empty="لا توجد مصاريف أو حركات أخرى ضمن الفترة."/>}
  </section>}
  {section==='settled'&&<div className="companyProfitView" aria-label="التسويات والتوزيع"><section className="uiPanel"><h2>تسوية أرباح الفترة</h2>
   <dl className="companyFigures"><Figure label="المسوّى من أرباح الفترة" value={balance?.period.settled}/><Figure label="غير المسوّى من أرباح الفترة" value={balance?.period.available}/>
    {owner!=='all'&&<Figure label="أثر التسويات الخارجية على الرصيد" value={balance?.period.adjustments}/>}</dl>
   <p className="companyAccountingNote">{owner==='all'?'الرصيد الحالي يجمع الأرباح المتبقية للشركة بعد التوزيعات المعتمدة عبر جميع الفترات.':'الرصيد الحالي يجمع أرباح هذا المستخدم وتوزيعاته وتسوياته الخارجية عبر جميع الفترات.'}</p>
   <h3>الحركات التي شملتها التسوية</h3>{balance&&<LedgerItems rows={settledMovements} a4={a4} empty="لا توجد حركات مسوّاة ضمن الفترة."/>}
  </section>{distributionForm}
  {receipt&&<section className="uiPanel"><h2>تم حفظ توزيع الأرباح #{receipt.receiptNo}</h2><ReportActions enabled html={a4('وصل توزيع الأرباح',cashReceiptBody(receipt),money(receipt.amount)+' د.ع')} filename={'توزيع-أرباح-'+receipt.receiptNo}/></section>}
  </div>}
  {section==='export'&&<section className="uiPanel companyProfitView companyReportExport" aria-label="تصدير التقرير"><h2>تقرير الأرباح</h2>
   <dl className="companyExportScope"><div><dt>صاحب الربح</dt><dd>{ownerName}</dd></div><div><dt>الفترة</dt><dd>{currentPeriod}</dd></div><div><dt>المبيعات</dt><dd>{saleLabels[type]}</dd></div></dl>
   <ReportActions enabled={!!balance} html={balance?a4('تقرير الأرباح',reportBody,money(unallocated)+' د.ع · المتبقي الحالي'):''} filename="تقرير-الأرباح" disabledNotice="يتاح التصدير بعد اكتمال بيانات التقرير."/>
  </section>}
  {error&&<p role="alert" className="accountAlert error">{error}</p>}
 </section>;
}
