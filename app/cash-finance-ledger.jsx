'use client';
import {useEffect,useState}from'react';
import {supabase}from'./supabase';
import AppIcon from'./app-icons';
import CashLedgerRows,{CashFigure} from './cash-ledger-rows';
import {cashPage,cashTypeOptions,monthStart,baghdadDay}from'./cash-finance-utils.mjs';

export default function CashFinanceLedger({profile,owners=[],ownerId='',initialType='all',revision,onMovement,onReport}){
 const [owner,setOwner]=useState(ownerId||(!profile.is_admin?profile.id:'')),[from,setFrom]=useState(monthStart),[to,setTo]=useState(baghdadDay),[type,setType]=useState(initialType),[currency,setCurrency]=useState('all'),[direction,setDirection]=useState('all'),[query,setQuery]=useState(''),[offset,setOffset]=useState(0),[retry,setRetry]=useState(0),[loaded,setLoaded]=useState(null),[error,setError]=useState('');
 const key=JSON.stringify([owner,from,to,type,currency,direction,query,offset,retry]);
 useEffect(()=>{let live=true;const ctl=new AbortController();setError('');const timer=setTimeout(async()=>{try{const r=await supabase.rpc('solar_cash_workspace',{payload:{ownerId:owner||null,from,to,currency,direction,query,offset:type==='all'?offset:0,limit:type==='all'?50:5000}}).abortSignal(ctl.signal);if(r.error)throw r.error;const data=cashPage(r.data,type,offset);if(live)setLoaded({key,data,revision});}catch(e){if(live)setError(e.code?e.message:e.message||'تعذر تحميل الحركات. أعد المحاولة.');}},query?250:0);return()=>{live=false;clearTimeout(timer);ctl.abort();};},[key,owner,from,to,type,currency,direction,query,offset,revision]);
 const data=loaded?.key===key&&loaded.revision===revision&&!error?loaded.data:null,s=data?.summary;
 const change=(set,value)=>{set(value);setOffset(0);};
 return <section className="cfLedger" aria-label="الحركات المالية"><div className="cfPanel cfLedgerFilters"><div className="cfSearch"><AppIcon name="search" size={18}/><input aria-label="بحث حركات الصندوق" placeholder="اسم الطرف، رقم الوصل، أو البيان…" value={query} maxLength={200} onChange={e=>change(setQuery,e.target.value)}/></div><div className="cfFilterGrid">
 {!ownerId&&profile.is_admin&&<label>القاصة<select aria-label="قاصة الحركات" value={owner} onChange={e=>change(setOwner,e.target.value)}><option value="">جميع القاصات</option>{owners.map(o=><option key={o.id} value={o.id}>{o.name}</option>)}</select></label>}
 <label>من<input type="date" aria-label="بداية فترة الصندوق" value={from} max={to||undefined} onChange={e=>change(setFrom,e.target.value)}/></label><label>إلى<input type="date" aria-label="نهاية فترة الصندوق" value={to} min={from||undefined} onChange={e=>change(setTo,e.target.value)}/></label>
 <label>نوع الحركة<select aria-label="نوع الحركة" value={type} onChange={e=>change(setType,e.target.value)}><option value="all">جميع الحركات</option><option value="expenses">المصروفات والإيداعات</option><option value="transfers">الحركات بين القاصات</option><option value="capital">رأس المال والأرباح</option>{cashTypeOptions.map(([k,v])=><option key={k} value={k}>{v}</option>)}</select></label>
 <label>العملة<select aria-label="عملة كشف الصندوق" value={currency} onChange={e=>change(setCurrency,e.target.value)}><option value="all">IQD + USD منفصلان</option><option value="IQD">دينار · IQD</option><option value="USD">دولار · USD</option></select></label><label>الاتجاه<select aria-label="اتجاه الحركة" value={direction} onChange={e=>change(setDirection,e.target.value)}><option value="all">داخل وخارج</option><option value="in">داخل</option><option value="out">خارج</option></select></label></div>
 <div className="cfFilterActions"><button onClick={()=>{setFrom(monthStart());setTo(baghdadDay());setOffset(0);}}>هذا الشهر</button><button onClick={()=>{setFrom(baghdadDay());setTo(baghdadDay());setOffset(0);}}>اليوم</button><button onClick={()=>{setFrom('');setTo('');setOffset(0);}}>كل الفترات</button><button onClick={()=>setRetry(n=>n+1)}><AppIcon name="refresh" size={15}/>تحديث</button>{onReport&&<button onClick={onReport}><AppIcon name="document" size={15}/>كشف PDF</button>}</div></div>
 {error?<p role="alert" className="workflowError">{error}</p>:!data?<p className="cfLoading" role="status">جاري تأكيد الحركات والأرصدة…</p>:<><div className="cfLedgerSummary">
  <h2>الحركات المالية <span>{data.count} حركة</span></h2>
  <div className="cfSummaryCurrencies">{['IQD','USD'].filter(c=>currency==='all'||c===currency).map(c=><div key={c} className="cfCurrencySummary">
   <strong>{c==='IQD'?'الدينار العراقي':'الدولار الأمريكي'}</strong>
   <span><span>داخل</span><b className="cfSummaryIn"><CashFigure value={s['period'+c+'In']} currency={c}/></b></span>
   <span><span>خارج</span><b className="cfSummaryOut"><CashFigure value={s['period'+c+'Out']} currency={c}/></b></span>
  </div>)}</div>
 </div>{type!=='all'&&<p className="cfHint">الداخل والخارج يشملان جميع أنواع الحركات ضمن الفترة.</p>}
 <CashLedgerRows rows={data.rows} owner={owner} onMovement={onMovement}/>
 {!data.rows.length&&<p className="cfEmpty">لا توجد حركات ضمن هذه الاختيارات.</p>}{data.count>50&&<nav className="cfPagination" aria-label="صفحات الحركات"><button disabled={!offset} onClick={()=>setOffset(n=>Math.max(0,n-50))}>السابق</button><span>{offset+1}–{Math.min(offset+50,data.count)} / {data.count}</span><button disabled={offset+50>=data.count} onClick={()=>setOffset(n=>n+50)}>التالي</button></nav>}</>}
 </section>;
}
