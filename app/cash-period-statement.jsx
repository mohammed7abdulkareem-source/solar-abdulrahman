'use client';
import {useEffect,useMemo,useState} from 'react';
import {supabase} from './supabase';
import ReportActions from './report-actions';
import {cashStatementStyle} from './cash-statement-style.mjs';
import AppIcon from './app-icons';
import {cashStatementDocument,cashStatementTable} from './cash-statement-report.mjs';

const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export default function CashPeriodStatement({owner,ownerName,revision,refresh,a4}){
 const [from,setFrom]=useState(()=>today().slice(0,8)+'01'),[to,setTo]=useState(today),[currency,setCurrency]=useState('all'),[requested,setRequested]=useState(false),[retry,setRetry]=useState(0),[state,setState]=useState(null),[error,setError]=useState('');
 const key=JSON.stringify([owner,from,to,currency,refresh,retry]);
 useEffect(()=>{
  if(!requested)return;
  let live=true;const controller=new AbortController();setState(null);setError('');
  if(!from||!to||from>to){setError('حدد تاريخ البداية والنهاية بصورة صحيحة.');return()=>{live=false;};}
  const timer=setTimeout(async()=>{try{const {data,error}=await supabase.rpc('solar_cash_statement',{owner_id:owner||null,date_from:from,date_to:to,currency_filter:currency}).abortSignal(controller.signal);if(error)throw error;if(live)setState({key,data,revision});}catch(e){if(live)setError(e.message||'تعذر تحميل كشف الصندوق.');}},180);
  return()=>{live=false;clearTimeout(timer);controller.abort();};
 },[requested,owner,from,to,currency,revision,refresh,retry,key]);
 const data=state?.key===key&&state.revision===revision?state.data:null;
 const html=useMemo(()=>data?cashStatementDocument(data,a4):'',[data,a4]);
 return <section className="uiPanel cashPeriodStatement" aria-label="كشف صندوق حسب الفترة"><style>{cashStatementStyle}</style><div className="panelTitle"><div><span className="sectionKicker">كشف مفصل قابل للمشاركة</span><h2>كشف صندوق حسب الفترة</h2><p>{ownerName||'القاصة المحددة'} · الرصيد السابق والحركات والملاحظات ورصيد النهاية</p></div><AppIcon name="document" size={24}/></div>
  <form className="cashStatementFilters" onSubmit={e=>{e.preventDefault();setRequested(true);setRetry(n=>n+1);}}><label>من<input aria-label="من تاريخ كشف الصندوق" type="date" required value={from} max={to||undefined} onChange={e=>setFrom(e.target.value)}/></label><label>إلى<input aria-label="إلى تاريخ كشف الصندوق" type="date" required value={to} min={from||undefined} onChange={e=>setTo(e.target.value)}/></label><label>عملة الكشف<select aria-label="عملة كشف الفترة" value={currency} onChange={e=>setCurrency(e.target.value)}><option value="all">الدينار والدولار منفصلان</option><option value="IQD">الدينار العراقي</option><option value="USD">الدولار الأمريكي</option></select></label><button className="uiButton primary" type="submit"><AppIcon name="refresh" size={17}/>{requested?'تحديث كشف الفترة':'عرض كشف الفترة'}</button></form>
  {error&&<p role="alert" className="accountAlert error">{error}</p>}{requested&&!data&&!error&&<p role="status">جاري احتساب الكشف من الحركات الحالية…</p>}
  {data&&<><p className="cashStatementSnapshot">{data.count} حركة · كل قاصة وعملة بكشف مستقل. التعديلات تُحدّث الكشف عند وصولها، ويمكن تحديثه يدويًا.</p><ReportActions enabled html={html} filename={'كشف-صندوق-'+data.ownerName+'-'+data.from+'-'+data.to}/><p className="cashStatementSwipe">اسحب الجدول أفقيًا لعرض بقية الأعمدة.</p><div className="cashStatementScreen">{data.ledgers.map(g=><div className="cashStatementScroll" key={String(g.ownerId)+g.currency} aria-label={'كشف قاصة '+g.ownerName+' '+g.currency} role="region" tabIndex={0} dangerouslySetInnerHTML={{__html:cashStatementTable(g)}}/>)}</div></>}
 </section>;
}
