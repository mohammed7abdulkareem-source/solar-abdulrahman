'use client';
import {useEffect,useMemo,useState} from 'react';
import {supabase} from './supabase';
import ReportActions from './report-actions';
import {cashStatementStyle} from './cash-statement-style.mjs';
import AppIcon from './app-icons';
import {cashStatementDocument,cashStatementTable} from './cash-statement-report.mjs';
import {statementByType,cashTypeOptions,baghdadDay} from './cash-finance-utils.mjs';
import {formatMoney as money,currencyUnit as unit} from './money-format.mjs';

const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export default function CashPeriodStatement({owner,ownerName,revision,refresh,a4}){
 const [from,setFrom]=useState(()=>today().slice(0,8)+'01'),[to,setTo]=useState(today),[currency,setCurrency]=useState('all'),[type,setType]=useState('all'),[requested,setRequested]=useState(false),[retry,setRetry]=useState(0),[state,setState]=useState(null),[error,setError]=useState('');
 const key=JSON.stringify([owner,from,to,currency,refresh,retry]);
 useEffect(()=>{
  if(!requested)return;
  let live=true;const controller=new AbortController();setState(null);setError('');
  if(!from||!to||from>to){setError('حدد تاريخ البداية والنهاية بصورة صحيحة.');return()=>{live=false;};}
  const timer=setTimeout(async()=>{try{const {data,error}=await supabase.rpc('solar_cash_statement',{owner_id:owner||null,date_from:from,date_to:to,currency_filter:currency}).abortSignal(controller.signal);if(error)throw error;if(live)setState({key,data,revision});}catch(e){if(live)setError(e.message||'تعذر تحميل كشف الصندوق.');}},180);
  return()=>{live=false;clearTimeout(timer);controller.abort();};
 },[requested,owner,from,to,currency,revision,refresh,retry,key]);
 const raw=state?.key===key&&state.revision===revision?state.data:null;
 const data=useMemo(()=>raw?statementByType(raw,type):null,[raw,type]);
 const summaries=useMemo(()=>data?['IQD','USD'].filter(c=>currency==='all'||currency===c).map(c=>({currency:c,...data.ledgers.filter(g=>g.currency===c).reduce((s,g)=>Object.fromEntries(['opening','incoming','outgoing','closing'].map(k=>[k,s[k]+Number(g[k]||0)])),{opening:0,incoming:0,outgoing:0,closing:0})})):[],[data,currency]);
 const html=useMemo(()=>data?cashStatementDocument(data,a4):'',[data,a4]);
 return <section className="uiPanel cashPeriodStatement" aria-label="كشف صندوق حسب الفترة"><style>{cashStatementStyle}</style><div className="panelTitle"><div><span className="sectionKicker">كشف مفصل قابل للمشاركة</span><h2>كشف صندوق حسب الفترة</h2><p>{ownerName||'القاصة المحددة'} · الرصيد السابق والحركات والملاحظات ورصيد النهاية</p></div><AppIcon name="document" size={24}/></div>
  <form className="cashStatementFilters" onSubmit={e=>{e.preventDefault();setRequested(true);setRetry(n=>n+1);}}><label>من<input aria-label="من تاريخ كشف الصندوق" type="date" required value={from} max={to||undefined} onChange={e=>setFrom(e.target.value)}/></label><label>إلى<input aria-label="إلى تاريخ كشف الصندوق" type="date" required value={to} min={from||undefined} onChange={e=>setTo(e.target.value)}/></label><label>عملة الكشف<select aria-label="عملة كشف الفترة" value={currency} onChange={e=>setCurrency(e.target.value)}><option value="all">الدينار والدولار منفصلان</option><option value="IQD">الدينار العراقي</option><option value="USD">الدولار الأمريكي</option></select></label><label>نوع الحركة<select aria-label="نوع حركة التقرير" value={type} onChange={e=>setType(e.target.value)}><option value="all">جميع الحركات</option>{cashTypeOptions.map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></label><button className="uiButton primary" type="submit"><AppIcon name="document" size={17}/>{requested?'تحديث كشف الفترة':'عرض كشف الفترة'}</button><button type="button" className="uiButton" onClick={()=>{setFrom(baghdadDay());setTo(baghdadDay());setRequested(true);}}>كشف اليوم</button></form>
  {error&&<p role="alert" className="accountAlert error">{error}</p>}{requested&&!data&&!error&&<p role="status">جاري احتساب الكشف من الحركات الحالية…</p>}
  {data&&<><div className="cfReportSummaries" role="region" aria-label="ملخص كشف الحساب">{summaries.map(g=><section key={g.currency} className={'cfReportSummary '+g.currency}><h3>{g.currency==='IQD'?'الدينار العراقي':'الدولار الأمريكي'} · {g.currency}</h3><dl>{[['opening','الرصيد الافتتاحي'],['incoming','إجمالي الداخل'],['outgoing','إجمالي الخارج'],['closing','الرصيد الختامي']].map(([key,label])=><div key={key}><dt>{label}</dt><dd className={g[key]<0||key==='outgoing'?'cfNegative':'cfPositive'}><bdi>{money(g[key],g.currency)} {unit(g.currency)}</bdi></dd></div>)}</dl></section>)}</div><p className="cashStatementSnapshot">{data.count} حركة معروضة · كل قاصة وعملة بكشف مستقل. {type!=='all'?'الأرصدة والمجاميع تشمل كل حركات الفترة؛ تصفية النوع تختصر صفوف الجدول فقط.':'يعكس الكشف التعديلات وقت احتسابه.'}</p><ReportActions enabled html={html} filename={'كشف-صندوق-'+data.ownerName+'-'+data.from+'-'+data.to}/><p className="cashStatementSwipe">اسحب الجدول لعرض التفاصيل والملاحظات.</p><div className="cashStatementScreen">{data.ledgers.map(g=><div className="cashStatementScroll" key={String(g.ownerId)+g.currency} aria-label={'كشف قاصة '+g.ownerName+' '+g.currency} role="region" tabIndex={0} dangerouslySetInnerHTML={{__html:cashStatementTable(g)}}/>)}</div></>}
 </section>;
}
