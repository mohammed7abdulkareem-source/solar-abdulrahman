'use client';
import {useEffect,useMemo,useRef,useState} from 'react';
import {supabase} from './supabase';
import {downloadPdf,sharePdf} from './pdf-share.mjs';
import {money} from './supplier-utils.mjs';
import {baghdadToday,balanceDate,partyType,filterBalances,balancesTotal,balancesDocument} from './party-balances-utils.mjs';

export default function PartyBalances({mode='customers',a4,openA4}){
 const customer=mode==='customers',title=customer?'مدينون العملاء':'الموردون';
 const [asOf,setAsOf]=useState(baghdadToday),[query,setQuery]=useState(''),[wholesale,setWholesale]=useState(true),[systems,setSystems]=useState(true),[dueOnly,setDueOnly]=useState(true),[showPhone,setShowPhone]=useState(false),[showType,setShowType]=useState(false);
 const [data,setData]=useState(null),[loading,setLoading]=useState(true),[error,setError]=useState(''),[busy,setBusy]=useState(false),[notice,setNotice]=useState(''),[refresh,setRefresh]=useState(0);
 const exportLock=useRef(false);
 useEffect(()=>{
  let live=true;setLoading(true);setError('');setData(null);setNotice('');
  if(!asOf){setLoading(false);return()=>{live=false};}
  supabase.rpc('solar_party_balances',{report_kind:mode,as_of:asOf}).then(({data,error})=>{if(!live)return;if(error)throw error;setData(data);}).catch(e=>{if(live)setError(e.code==='42501'?'ليس لديك صلاحية عرض هذا التقرير.':'تعذر تحميل الأرصدة. حاول تحديث التقرير.');}).finally(()=>{if(live)setLoading(false)});
  return()=>{live=false};
 },[mode,asOf,refresh]);
 const options={mode,asOf,query,wholesale,systems,dueOnly:customer||dueOnly,showPhone,showType,scope:data?.scope||''};
 const rows=useMemo(()=>filterBalances(data?.rows||[],{mode,query,wholesale,systems,dueOnly:customer||dueOnly}),[data,mode,query,wholesale,systems,customer,dueOnly]);
 const total=balancesTotal(rows),ready=!!data&&data.as_of===asOf&&!loading&&!error&&!data.unresolved;
 const html=()=>a4(title,balancesDocument(rows,options),money(total)+' د.ع',asOf);
 async function exportReport(share){if(exportLock.current||!ready)return;exportLock.current=true;setBusy(true);setNotice('');try{const file=title+'-'+asOf;if(share){const result=await sharePdf(file,html());if(result==='downloaded')setNotice('تم تنزيل PDF. يمكنك مشاركته من ملفات الجهاز.');}else await downloadPdf(file,html());}catch{setNotice('تعذر تجهيز PDF. حاول مجدداً.');}finally{exportLock.current=false;setBusy(false)}}
 return <section className="balanceWorkspace">
  <div className="balanceHero"><div><h2>{title}</h2><p>{customer?'أرصدة العملاء وآخر تسديد':'أرصدة الموردين وآخر تسديد'}</p></div><button onClick={()=>setRefresh(n=>n+1)} disabled={loading}>تحديث</button></div>
  <div className="card balanceFilters"><label>بحث بالاسم أو الهاتف<input aria-label="بحث الأرصدة" value={query} onChange={e=>setQuery(e.target.value)} placeholder="اكتب الاسم أو رقم الهاتف"/></label><label>الرصيد لغاية<input aria-label="الرصيد لغاية" type="date" value={asOf} max={baghdadToday()} onChange={e=>setAsOf(e.target.value)}/></label>
   <div className="balanceChecks">{customer?<><label><input type="checkbox" checked={wholesale} onChange={e=>setWholesale(e.target.checked)}/>جملة</label><label><input type="checkbox" checked={systems} onChange={e=>setSystems(e.target.checked)}/>منظومات</label></>:<label><input type="checkbox" checked={dueOnly} onChange={e=>setDueOnly(e.target.checked)}/>المبالغ المستحقة فقط</label>}</div>
   <div className="balanceChecks balanceColumns"><span>أعمدة إضافية:</span><label><input type="checkbox" checked={showPhone} onChange={e=>setShowPhone(e.target.checked)}/>الهاتف</label>{customer&&<label><input type="checkbox" checked={showType} onChange={e=>setShowType(e.target.checked)}/>النوع</label>}</div>
  </div>
  {!asOf&&<p role="alert" className="workflowError">اختر تاريخ الرصيد.</p>}{error&&<p role="alert" className="workflowError">{error}</p>}
  {loading?<p role="status" className="empty">جاري احتساب الأرصدة…</p>:data&&data.as_of===asOf&&<>
   <p className="balanceScope">{data.scope}</p>{data.unresolved>0&&<p role="alert" className="workflowError">توجد حركات قديمة بأسماء مكررة أو غير مرتبطة بعميل أو مورد. التقرير غير مكتمل؛ يجب تصحيح ربطها قبل تصديره.</p>}
   <div className="balanceTotals"><div><small>{customer?'إجمالي الديون المختارة':'إجمالي الأرصدة المختارة'}</small><strong>{money(total)} <small>د.ع</small></strong></div><div><small>{customer?'عدد العملاء':'عدد الموردين'}</small><strong>{rows.length}</strong></div></div>
   <div className="balanceTableWrap"><table className="balanceTable"><thead><tr><th>#</th><th>{customer?'العميل':'المورد'}</th>{showPhone&&<th>الهاتف</th>}{customer&&showType&&<th>النوع</th>}<th>{customer?'الرصيد المدين':'الرصيد للمورد'}</th><th>آخر تسديد</th><th>تاريخ آخر تسديد</th></tr></thead><tbody>{rows.map((r,i)=><tr key={r.id}><td>{i+1}</td><td>{r.name}</td>{showPhone&&<td>{r.phone||'—'}</td>}{customer&&showType&&<td>{partyType(r.customer_type)}</td>}<td><b>{money(r.balance)}</b></td><td>{r.last_payment==null?'—':money(r.last_payment)}</td><td>{balanceDate(r.last_payment_at)}</td></tr>)}</tbody></table>{!rows.length&&<p className="empty">{customer&&!wholesale&&!systems?'اختر جملة أو منظومات لعرض المدينين.':'لا توجد أرصدة مطابقة للاختيارات.'}</p>}</div>
   <p className="balanceScope">جميع المبالغ بالدينار العراقي. آخر تسديد لا يشمل الإضافات على الحساب.{!customer&&' الرصيد السالب دفعة مقدمة لنا عند المورد.'}</p>
  </>}
  <div className="balanceActions"><button disabled={!ready||busy} onClick={()=>openA4(html())}>معاينة</button><button disabled={!ready||busy} onClick={()=>exportReport(false)}>حفظ PDF</button><button disabled={!ready||busy} onClick={()=>exportReport(true)}>مشاركة</button></div>{notice&&<p role="status" className="balanceScope">{notice}</p>}
 </section>;
}
