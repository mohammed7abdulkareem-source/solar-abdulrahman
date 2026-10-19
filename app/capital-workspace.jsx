'use client';
import {useEffect,useState} from 'react';
import {supabase} from './supabase';
import AppIcon from './app-icons';
import ReportActions from './report-actions';
import {a4} from './document-template.mjs';
import {previewPdf} from './pdf-preview.mjs';
import {money} from './supplier-utils.mjs';
import {capitalStockReport,capitalCashReport,capitalDebtReport} from './capital-reports.mjs';
import {capitalSnapshotReport} from './capital-snapshot-report.mjs';

function Amount({value}){return <span className="capitalAmount"><bdi dir="ltr">{money(value)}</bdi><small>د.ع</small></span>;}
export default function CapitalWorkspace({profile,revision}){
 const [snapshot,setSnapshot]=useState(null),[refresh,setRefresh]=useState(0),[loading,setLoading]=useState(true),[error,setError]=useState('');
 useEffect(()=>{let live=true;setLoading(true);setError('');supabase.rpc('solar_capital_snapshot').then(({data,error})=>{
  if(!live)return;if(error)throw error;if(!data?.asOf||!Number.isFinite(Number(data.net)))throw new Error('تعذر التحقق من بيانات رأس المال');setSnapshot(data);
 }).catch(err=>{if(live){setSnapshot(null);setError(err.message||'تعذر تحميل الحساب. أعد المحاولة.');}}).finally(()=>{if(live)setLoading(false);});return()=>{live=false;};},[profile.id,revision,refresh]);
 const report=snapshot?capitalSnapshotReport(snapshot):null;
 const document=r=>a4(r.title,r.body,money(r.total)+' د.ع',new Date(snapshot.asOf).toLocaleString('en-GB',{timeZone:'Asia/Baghdad'}));
 const preview=r=>previewPdf(document(r),r.title);
 const s=snapshot;
 const debt=(accounts,supplier=false,credit=false)=>{const total=credit?(supplier?accounts.prepayments:accounts.advances):(supplier?accounts.payable:accounts.receivable);const r=capitalDebtReport({rows:credit?accounts.rows.filter(r=>r.balance<0):accounts.rows,net:credit?-total:accounts.net,total},supplier);return credit?{...r,title:supplier?'كشف سلفنا لدى الموردين':'كشف أرصدة العملاء الدائنة'}:r;};
 const cashRows=s?.cash.rows.filter(r=>r.currency==='IQD').map(r=>({...r,total:Math.abs(r.delta),cashDelta:r.delta,cashboxUserId:r.ownerId,party:[r.party,r.ownerName].filter(Boolean).join(' · '),systemCash:!r.id.startsWith('tx:')}));
 const tiles=s?[
  ['المخزون بالكلفة',s.stock.value,'package',()=>capitalStockReport(s.stock.rows)],
  ['الصندوق بالدينار',s.cash.iqd,'wallet',()=>capitalCashReport(cashRows)],
  ['ديون العملاء لنا',s.customers.receivable,'customers',()=>debt(s.customers)],
  ['ديون الموردين علينا',s.suppliers.payable,'suppliers',()=>debt(s.suppliers,true)],
  ...(s.cash.usd!==0||s.cash.usdBook!==0?[['قاصة الدولار بالكلفة',s.cash.usdBook,'wallet',()=>({title:'قاصة الدولار',total:s.cash.usdBook,body:'<p>رصيد الدولار: '+money(s.cash.usd)+' $</p><p>القيمة الدفترية: '+money(s.cash.usdBook)+' د.ع</p>'})]]:[]),
  ...(s.suppliers.prepayments!==0?[['سلفنا لدى الموردين',s.suppliers.prepayments,'suppliers',()=>debt(s.suppliers,true,true)]]:[]),
  ...(s.customers.advances!==0?[['أرصدة العملاء الدائنة',s.customers.advances,'customers',()=>debt(s.customers,false,true)]]:[])
 ]:[];
 return <section className="capitalWorkspace" aria-busy={loading}>
  <header className="workspaceHead"><div><h1>{s?.scope==='own'?'ملخص أرصدتي':'رأس المال'}</h1><p>ملخص الأرصدة بالقيمة الدفترية.</p></div><button className="uiButton" disabled={loading} onClick={()=>setRefresh(n=>n+1)}><AppIcon name="refresh" size={17}/>{loading?'جاري الاحتساب…':'تحديث الحساب'}</button></header>
  {error&&<div className="accountAlert error" role="alert">{error}</div>}
  {!s&&loading&&<div className="uiPanel" role="status">جاري قراءة الأرصدة وحسابها…</div>}
  {s&&<>
   {s.scope==='own'&&<p className="capitalScopeNote">هذا الملخص يشمل حركاتك وقاصتك والمخازن المسموحة لك. رأس مال الشركة الكامل يظهر للإدارة.</p>}
   <section className={'capitalSnapshotHero'+(s.net<0?' negative':'')}><span>{s.scope==='company'?'صافي قيمة النشاط الحالية':'صافي الأرصدة ضمن صلاحيتك'}</span><Amount value={s.net}/><small>الموجودات − المطلوبات · جميع القيم بالدينار</small></section>
   <div className="capitalTotals"><div><span>الموجودات</span><Amount value={s.assets}/></div><div><span>المطلوبات</span><Amount value={s.liabilities}/></div></div>
   <div className="capitalSnapshotGrid">{tiles.map(([label,value,icon,getReport])=><button className="capitalSnapshotTile" key={label} disabled={loading} onClick={()=>preview(getReport())} aria-label={'تفاصيل '+label}><span className="capitalTileLabel"><AppIcon name={icon} size={18}/>{label}<AppIcon name="chevron" size={15}/></span><Amount value={value}/><small>عرض الكشف</small></button>)}</div>
   <section className="uiPanel"><div className="panelTitle"><h2>تقرير رأس المال</h2><small>بتاريخ {new Date(s.asOf).toLocaleString('en-GB',{timeZone:'Asia/Baghdad'})}</small></div><ReportActions enabled={!loading} html={document(report)} filename="تقرير-رأس-المال"/></section>
  </>}
 </section>;
}
