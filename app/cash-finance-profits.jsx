'use client';
import dynamic from'next/dynamic';
import {useEffect,useState}from'react';
import {supabase}from'./supabase';
import {canOpenPage}from'./access-utils.mjs';
import {canUseCash}from'./cash-permissions.mjs';
import {formatMoney as money}from'./money-format.mjs';
import AppIcon from'./app-icons';
const Capital=dynamic(()=>import('./capital-workspace'));
const Settlements=dynamic(()=>import('./profit-settlements'));
const PendingSystems=dynamic(()=>import('./pending-systems'));
export default function CashFinanceProfits({profile,a4,revision,onChanged,onEntry,onLedger,onNavigate}){
 const [tab,setTab]=useState('overview'),[loaded,setData]=useState(null),[error,setError]=useState('');
 const capital=canOpenPage(profile,'capital'),profit=canOpenPage(profile,'profit'),adminTools=canUseCash(profile,'cashAdminTools');
 useEffect(()=>{let live=true;setData(null);setError('');const calls=[capital?supabase.rpc('solar_capital_snapshot'):Promise.resolve({data:null}),profit?supabase.rpc('solar_profit_workspace',{action:'overview'}):Promise.resolve({data:null}),profit?supabase.rpc('solar_pending_systems',{owner_id:profile.is_admin?null:profile.id}):Promise.resolve({data:null})];Promise.all(calls).then(results=>{if(!live)return;setData({scope:profile.id+':'+profile.is_admin+':'+capital+':'+profit,revision,data:{capital:results[0].data,profit:results[1].data,pending:results[2].data}});if(results.some(r=>r.error))setError('تعذر تأكيد بعض الملخصات؛ افتح القسم لإعادة تحميل بياناته.');}).catch(()=>live&&setError('تعذر تحميل الملخص المالي.'));return()=>{live=false;};},[profile.id,profile.is_admin,capital,profit,revision]);
 const scope=profile.id+':'+profile.is_admin+':'+capital+':'+profit,data=loaded?.scope===scope&&loaded.revision===revision?loaded.data:null;
 const external=data?.profit?.rows?.filter(r=>r.kind==='external_profit').reduce((n,r)=>n+Number(r.value),0),remaining=data?.profit?.retainedProfit;
 return <section className="cfProfit" aria-label="الأرباح ورأس المال"><nav className="cfTabs" role="tablist" aria-label="أقسام الأرباح ورأس المال">{[['overview','الملخص'],...(profit?[['pending','غير المغلقة'],['settlements','التسويات']]:[]),...(capital?[['capital','تفاصيل رأس المال']]:[])].map(([k,v])=><button key={k} role="tab" aria-selected={tab===k} onClick={()=>setTab(k)}>{v}</button>)}</nav>
 {error&&<p role="alert" className="workflowError">{error}</p>}{tab==='overview'&&<><div className="cfFinanceStats">{[[capital?'صافي رأس المال':'رأس المال','banknote',data?.capital?.net,capital],['أرباحي المتبقية بعد التسوية','chart',remaining,profit],[profit?'الأرباح الخارجية · حسابي':'الأرباح الخارجية','chart',external,profit],['ربح غير المغلق · غير نقدي','tools',data?.pending?.summary?.provisionalProfit,profit]].map(([label,icon,value,allowed])=><article className="cfPanel" key={label}><span><AppIcon name={icon} size={20}/>{label}</span><strong className={value<0?'cfNegative':'cfPositive'}>{value!=null?money(value):allowed?'…':'حسب الصلاحية'}</strong>{value!=null&&<small>د.ع</small>}</article>)}</div><p className="cfHint">رصيد الأرباح بعد التسويات يشمل جميع الفترات ويختلف عن النقد المتاح. الأرباح غير المغلقة تقديرية. رأس المال يعرض نطاق حسابك المسموح.</p><div className="cfActionGrid">{adminTools&&<><button onClick={()=>onEntry('capital_deposit')}><AppIcon name="download"/>إضافة رأس مال</button><button onClick={()=>onEntry('capital_withdraw')}><AppIcon name="banknote"/>سحب رأس مال</button></>}{canUseCash(profile,'cashExternalProfit')&&<button onClick={()=>onEntry('external_profit')}><AppIcon name="chart"/>إضافة ربح خارجي</button>}{profit&&<button onClick={()=>setTab('settlements')}><AppIcon name="calculator"/>تسوية أرباح</button>}<button onClick={onLedger}><AppIcon name="receipt"/>سجل العمليات</button>{profit&&onNavigate&&<button onClick={()=>onNavigate('profit')}><AppIcon name="chart"/>كشف الأرباح التفصيلي</button>}</div></>}
 {tab==='pending'&&profit&&<PendingSystems ownerId={profile.is_admin?null:profile.id} revision={revision} a4={a4}/>}{tab==='settlements'&&profit&&<Settlements profile={profile} a4={a4} tx={revision} onChanged={onChanged}/>}{tab==='capital'&&capital&&<Capital profile={profile} revision={revision}/>}
 </section>;
}
