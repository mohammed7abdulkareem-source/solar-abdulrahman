'use client';
import {useEffect,useMemo,useState} from 'react';
import AppIcon from './app-icons';
import UserActivityReview from './user-activity-review';
import ActivityPerformance,{usablePerformance} from './user-activity-performance';
import UserActivityReport from './user-activity-report';
import {isAdministrator} from './access-utils.mjs';
import {baghdadToday} from './party-balances-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {currencyUnit,formatMoney} from './money-format.mjs';
import {partyInitials} from './compact-party-utils.mjs';
import {supabase} from './supabase';
import './user-activity.css';

const roleOf=user=>user.userType==='warehouse'?'warehouse':user.userType==='installer'?'installer':'office';
const roleLabel={office:'المكتب',warehouse:'المخزن',installer:'التنصيب'};
const roleIcons={office:'user',warehouse:'package',installer:'tools'};
const timestamp=new Intl.DateTimeFormat('ar-IQ',{timeZone:'Asia/Baghdad',dateStyle:'medium',timeStyle:'short'});
const counts=new Intl.NumberFormat('en-US',{maximumFractionDigits:0});
function shownDate(value){
 if(!value)return '';
 const date=new Date(value);
 return Number.isFinite(date.getTime())?timestamp.format(date):'';
}
function isAmount(value){
 return (typeof value==='number'||typeof value==='string'&&value.trim()!=='')&&Number.isFinite(Number(value));
}
function valueText(value,currency){return !isAmount(value)?'غير متاح':currency?formatMoney(value,currency):counts.format(value);}

function useActivity(ownerId,from,to,enabled,revision){
 const key=JSON.stringify([ownerId,from,to,revision]);
 const [response,setResponse]=useState(null);
 useEffect(()=>{
  if(!enabled)return;
  let live=true;
  const controller=new AbortController();
  async function load(){
   try{
    const payload=ownerId?{ownerId,from:from||null,to:to||null}:{};
    const {data,error}=await supabase.rpc('solar_user_activity',{payload}).abortSignal(controller.signal);
    if(error)throw error;
    if(ownerId?data?.user?.id!==ownerId||data.from!==(from||null)||(to&&data.to!==to):!Array.isArray(data?.users))throw new Error('تعذّر تأكيد المستخدم أو فترة النشاط.');
    if(live)setResponse({key,data});
   }catch(err){if(live)setResponse({key,error:err.message||'تعذّر تحميل النشاط.'});}
  }
  void load();
  return ()=>{live=false;controller.abort();};
 },[ownerId,from,to,enabled,revision,key]);
 return enabled&&response?.key===key?response:{};
}
function Metric({label,value,currency,metric}){
 return <div className="activityMetric"><dt>{label}</dt><dd data-activity-metric={metric}>
  <bdi>{valueText(value,currency)}</bdi>{isAmount(value)&&currency&&<small> {currencyUnit(currency)}</small>}
 </dd></div>;
}
function Heading({icon,title,caption}){
 return <div className="activityCardHeading"><span aria-hidden="true"><AppIcon name={icon} size={21}/></span>
 <div><h3>{title}</h3>{caption&&<small>{caption}</small>}</div></div>;
}
function AmountPair({values,scope}){
 return <dl className="activityPair"><Metric label="دينار عراقي" value={values?.IQD} currency="IQD" metric={scope+'.IQD'}/>
  <Metric label="دولار أمريكي" value={values?.USD} currency="USD" metric={scope+'.USD'}/></dl>;
}
function FinancialSummary({data}){
 const {sales,debts,profit,collections,handovers,cash,expenses}=data;
 return <div className="activityFinancialGrid" aria-label="الملخص المالي">
  <section className="activityCard activitySales"><Heading icon="receipt" title="المبيعات" caption="الفواتير خلال الفترة"/>
   <dl className="activityPair">
    {!usablePerformance(data.performance)&&<><Metric label="إجمالي المبيعات" value={sales?.totalIQD} currency="IQD" metric="sales.totalIQD"/>
    <Metric label="عدد الفواتير" value={sales?.count} metric="sales.count"/></>}
    <Metric label="مبيعات الجملة" value={sales?.wholesaleIQD} currency="IQD" metric="sales.wholesaleIQD"/>
    <Metric label="فواتير الجملة" value={sales?.wholesaleCount} metric="sales.wholesaleCount"/>
    <Metric label="مبيعات المنظومات" value={sales?.systemIQD} currency="IQD" metric="sales.systemIQD"/>
    <Metric label="فواتير المنظومات" value={sales?.systemCount} metric="sales.systemCount"/>
   </dl></section>
  <section className="activityCard activityDebts"><Heading icon="users" title="ديون الزبائن" caption={'أرصدة زبائن المستخدم حتى '+(data.to||'اليوم')}/>
   <dl className="activityPair"><Metric label="مبالغ على الزبائن" value={debts?.dueIQD} currency="IQD" metric="debts.dueIQD"/>
    <Metric label="أرصدة لصالح الزبائن" value={debts?.creditIQD} currency="IQD" metric="debts.creditIQD"/>
    <Metric label="صافي رصيد الزبائن" value={debts?.netIQD} currency="IQD" metric="debts.netIQD"/>
    <Metric label="زبائن عليهم دين" value={debts?.debtorCount} metric="debts.debtorCount"/>
    <Metric label="عدد الزبائن" value={debts?.customerCount} metric="debts.customerCount"/>
   </dl></section>
  <section className="activityCard"><Heading icon="chart" title="الأرباح"/><dl className="activityPair">
   <Metric label="صافي نتيجة المستخدم خلال الفترة" value={profit?.earnedIQD} currency="IQD" metric="profit.earnedIQD"/>
   <Metric label="رصيد الأرباح الحالي · كل الفترات" value={profit?.remainingIQD} currency="IQD" metric="profit.remainingIQD"/>
  </dl></section>
  <section className="activityCard"><Heading icon="wallet" title="رصيد القاصة الحالي" caption="الرصيد المتاح الآن"/><AmountPair values={cash} scope="cash"/></section>
  <section className="activityCard"><Heading icon="banknote" title="تحصيلات الزبائن" caption="التسديدات التي استلمها المستخدم خلال الفترة"/>
   <AmountPair values={collections} scope="collections"/><dl><Metric label="عدد التسديدات" value={collections?.count} metric="collections.count"/></dl></section>
  <section className="activityCard activityExpenses"><Heading icon="document" title="المصاريف" caption="المصاريف النقدية ومصاريف الربح والفواتير خلال الفترة"/>
   <h4>مصروف من القاصة</h4><AmountPair values={expenses?.cash} scope="expenses.cash"/>
   <dl className="activityPair">
    <Metric label="عدد المصاريف النقدية" value={expenses?.cash?.count} metric="expenses.cash.count"/>
    <Metric label="مصروف من أرباح المستخدم" value={expenses?.personalProfitIQD} currency="IQD" metric="expenses.personalProfitIQD"/>
    <Metric label="مصاريف بيع تتحمّلها الشركة" value={expenses?.companySaleIQD} currency="IQD" metric="expenses.companySaleIQD"/>
    <Metric label="مصاريف بيع على الزبون" value={expenses?.customerSaleIQD} currency="IQD" metric="expenses.customerSaleIQD"/>
    <Metric label="مصاريف تنصيب معتمدة" value={expenses?.systemInstallationIQD} currency="IQD" metric="expenses.systemInstallationIQD"/>
   </dl></section>
  <section className="activityCard activityHandovers"><Heading icon="exchange" title="تسليم واستلام القاصة" caption="حركات بين المستخدمين"/>
   {[['outgoing','سلّم لمستخدم آخر'],['incoming','استلم من مستخدم آخر'],['pendingOutgoing','تسليمات بانتظار الاستلام']].map(([key,label])=>
    <div className="activityHandover" key={key}><h4>{label}</h4><AmountPair values={handovers?.[key]} scope={'handovers.'+key}/>
    <span>عدد الحركات <bdi data-activity-metric={'handovers.'+key+'.count'}>{valueText(handovers?.[key]?.count)}</bdi></span></div>)}
  </section>
 </div>;
}
const operationFields={
 warehouse:[['prepared','عمليات تجهيز الوصولات'],['preparedWholesale','تجهيزات الجملة'],['preparedSystems','تجهيزات المنظومات'],['edited','تعديلات التجهيز'],['reopened','إعادة فتح التجهيز'],['transfersPrepared','مناقلات مخزنية جهّزها']],
 installer:[['scheduled','مواعيد التنصيب'],['started','تنصيبات بدأها'],['completed','تقارير إنجاز رفعها'],['closed','ملفاته التي أغلقتها الإدارة']]
};
const kindNames={expense:'مصروف من القاصة',profit_expense:'مصروف من الأرباح',system_payment:'تسديد منظومة',sale:'بيع جملة',system:'بيع منظومة',purchase:'شراء مواد',customer_payment:'تسديد زبون',collection:'تحصيل زبون',handover_in:'استلام قاصة',handover_out:'تسليم قاصة',cash_in:'استلام قاصة',cash_out:'تسليم قاصة',handover_pending:'تسليم بانتظار الاستلام',prepared:'تجهيز وصل',edited:'تعديل التجهيز',reopened:'إعادة فتح التجهيز',transfersPrepared:'تجهيز مناقلة',scheduled:'موعد تنصيب',started:'بدء التنصيب',completed:'رفع تقرير الإنجاز',closed:'إغلاق ملف التنصيب'};
function ActivityRows({rows}){
 if(!Array.isArray(rows))return <p className="activityFeedback">تعذّر عرض سجل الحركات.</p>;
 if(!rows.length)return <p className="activityFeedback">لا توجد حركات ضمن الفترة المختارة.</p>;
 return <ul className="activityRows">{rows.map((row,i)=><li key={[row.kind,row.id,row.at||row.date,i].join(':')}>
  <div><strong>{row.label||kindNames[row.kind]||'حركة مسجّلة'}</strong>
   {(row.party||row.warehouseName)&&<span dir="auto">{[row.party,row.warehouseName].filter(Boolean).join(' · ')}</span>}
   <small>{shownDate(row.at||row.date)}{row.archived?' · وصل مؤرشف':''}{row.receiptNo!=null&&<> · وصل <bdi>#{row.receiptNo}</bdi></>}</small></div>
  {isAmount(row.amount)&&['USD','IQD'].includes(row.currency)&&<b><bdi>{formatMoney(row.amount,row.currency)}</bdi> {currencyUnit(row.currency)}</b>}
 </li>)}</ul>;
}
function Operations({data,role}){
 const selected=data.operations?.[role],isWarehouse=role==='warehouse';
 return <div className="activityOperational">
  <section className="activityCard"><Heading title={isWarehouse?'تجهيز المخزن':'تنصيب المنظومات'} icon={roleIcons[role]} caption="العمليات المسجّلة خلال الفترة"/>
   <dl className="activityPair">{operationFields[role].map(([key,label])=><Metric key={key} label={label} value={selected?.[key]} metric={'operations.'+role+'.'+key}/>)}</dl></section>
  <section className="activityCard"><Heading icon="document" title="آخر العمليات"/><ActivityRows rows={data.operations?.recent}/></section>
 </div>;
}
function Detail({user,onBack,a4}){
 const [period,setPeriod]=useState({from:'',to:''}),[draft,setDraft]=useState(period),[revision,setRevision]=useState(0);
 const [pickedTab,setTab]=useState(roleOf(user)==='office'?'finance':'operations');
 const {data,error}=useActivity(user.id,period.from,period.to,true,revision);
 const detailUser=data?.user||user,role=roleOf(detailUser),tab=pickedTab==='operations'&&role==='office'?'finance':pickedTab;
 const invalid=!!(draft.from&&draft.to&&draft.from>draft.to);
 const tabs=[['finance','الملخص المالي'],['review','مراجعة الحساب'],...(role==='office'?[]:[['operations','العمليات']]),['recent','آخر الحركات']];
 return <section className="userActivity" dir="rtl" aria-label="نشاط المستخدم">
  <header className="activityDetailHead"><button className="activityBack" type="button" aria-label="رجوع إلى دليل المستخدمين" onClick={onBack}><AppIcon name="arrow" size={18}/>دليل المستخدمين</button>
   <button type="button" className="activityRefresh" aria-label="تحديث نشاط المستخدم" onClick={()=>setRevision(n=>n+1)}><AppIcon name="refresh" size={17}/>تحديث</button></header>
  <div className={'activityIdentity '+role}><span className="activityAvatar" aria-hidden="true">{partyInitials(detailUser.name)}</span>
   <div><h1>{detailUser.name}</h1><span>{roleLabel[role]}{detailUser.active===false?' · حساب غير نشط':''}</span></div></div>
  <form className="activityDates" onSubmit={event=>{event.preventDefault();if(!invalid)setPeriod({...draft});}}>
   <label>من تاريخ<input aria-label="من تاريخ النشاط" type="date" value={draft.from} max={draft.to||baghdadToday()} onChange={e=>setDraft({...draft,from:e.target.value})}/></label>
   <label>إلى تاريخ<input aria-label="إلى تاريخ النشاط" type="date" value={draft.to} max={baghdadToday()} min={draft.from||undefined} onChange={e=>setDraft({...draft,to:e.target.value})}/></label>
   <button type="submit" className="activityApply" disabled={invalid}>تطبيق الفترة</button>
   {(draft.from||draft.to||period.from||period.to)&&<button type="button" className="activityReset" onClick={()=>{setDraft({from:'',to:''});setPeriod({from:'',to:''});}}>كل الفترة</button>}
   {invalid&&<small role="alert">تاريخ البداية يجب أن يسبق تاريخ النهاية.</small>}
  </form>
  <div className="activityPeriodTools"><p className="activityPeriod">الفترة المعروضة · {period.from||'بداية التعامل'} إلى {period.to||'اليوم'}</p>
   {data&&!error&&<UserActivityReport data={data} a4={a4}/>}
  </div>
  <nav className="activityTabs" aria-label="أقسام نشاط المستخدم">{tabs.map(([key,label])=><button type="button" key={key} aria-pressed={tab===key} onClick={()=>setTab(key)}>{label}</button>)}</nav>
  {error?<div className="activityFeedback error" role="alert">{error}<button type="button" onClick={()=>setRevision(n=>n+1)}>إعادة المحاولة</button></div>:!data?<p className="activityFeedback" role="status">جاري تحميل نشاط المستخدم…</p>:
   tab==='finance'?<><ActivityPerformance key={JSON.stringify([user.id,period.from,period.to])} data={data}/><FinancialSummary data={data}/></>:tab==='review'?<UserActivityReview review={data.review}/>:tab==='operations'?<Operations data={data} role={role}/>:<section className="activityCard"><Heading title="آخر الحركات المالية" icon="receipt"/><ActivityRows rows={data.recent}/></section>}
 </section>;
}
function Directory({a4}){
 const [selected,setSelected]=useState(null),[query,setQuery]=useState(''),[role,setRole]=useState('all'),[revision,setRevision]=useState(0);
 const {data,error}=useActivity(null,null,null,true,revision);
 const users=useMemo(()=>(data?.users||[]).filter(user=>user?.id&&!user.isAdmin&&!user.is_admin&&user.userType!=='admin'),[data]);
 const matches=useMemo(()=>{
  const words=normalizeSearch(query).split(/\s+/).filter(Boolean);
  return users.filter(user=>{const text=normalizeSearch([user.name,user.username,roleLabel[roleOf(user)]].join(' '));return (role==='all'||roleOf(user)===role)&&words.every(word=>text.includes(word));});
 },[users,query,role]);
 if(selected)return <Detail key={selected.id} user={selected} a4={a4} onBack={()=>setSelected(null)}/>;
 return <section className="userActivity" dir="rtl" aria-label="دليل نشاط المستخدمين">
  <header className="activityDirectoryHead"><div><h1>نشاط المستخدمين</h1><p>اختر المستخدم لعرض حساباته وعملياته.</p></div>
   <button type="button" className="activityRefresh" aria-label="تحديث دليل المستخدمين" onClick={()=>setRevision(n=>n+1)}><AppIcon name="refresh" size={18}/>تحديث</button></header>
  <div className="activityDirectoryTools"><label><AppIcon name="search" size={20}/>
   <input aria-label="بحث المستخدمين" type="search" value={query} placeholder="ابحث بالاسم أو اسم المستخدم" onChange={e=>setQuery(e.target.value)}/></label>
   <div className="activityRoleFilter" role="group" aria-label="تصفية حسب الدور">{[['all','الكل'],...Object.entries(roleLabel)].map(([key,label])=><button type="button" key={key} aria-pressed={role===key} onClick={()=>setRole(key)}>{label}</button>)}</div></div>
  {error?<div role="alert" className="activityFeedback error">{error}<button type="button" onClick={()=>setRevision(n=>n+1)}>إعادة المحاولة</button></div>:!data?<p role="status" className="activityFeedback">جاري تحميل المستخدمين…</p>:
   <><div className="activityDirectoryCount" role="status">{matches.length} مستخدم</div><ul className="activityDirectory">{matches.map(user=><li key={user.id}><button type="button" className={roleOf(user)} aria-label={'عرض نشاط '+user.name} onClick={()=>{setSelected(user);window.scrollTo({top:0});}}>
    <span className="activityAvatar" aria-hidden="true">{partyInitials(user.name)}</span><span className="activityUserName"><strong dir="auto">{user.name}</strong><small>{roleLabel[roleOf(user)]}{user.active===false?' · غير نشط':''}</small></span>
    <AppIcon name="chevron" size={17}/></button></li>)}</ul>{!matches.length&&<p className="activityFeedback">لا يوجد مستخدم مطابق.</p>}</>}
 </section>;
}
export default function UserActivity({profile,a4}){
 if(!isAdministrator(profile))return <p role="alert" className="activityFeedback">هذه الصفحة مخصّصة للإدارة.</p>;
 return <Directory key={profile.id} a4={a4}/>;
}
