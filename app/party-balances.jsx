'use client';
import PhoneActions from './phone-actions';
import {useEffect,useMemo,useState} from 'react';
import {supabase} from './supabase';
import {money} from './supplier-utils.mjs';
import ReportActions,{ReportIcon} from './report-actions';
import {baghdadToday,balanceDate,partyType,filterBalances,filterUnresolved,balancesTotal,balancesDocument,groupBalances,legacyReason,ownerKey} from './party-balances-utils.mjs';

export default function PartyBalances({mode='customers',a4,profile}){
 const customer=mode==='customers',title=customer?'مدينون العملاء':'أرصدة الموردين';
 const [asOf,setAsOf]=useState(baghdadToday),[query,setQuery]=useState(''),[category,setCategory]=useState('all'),[ownerId,setOwnerId]=useState('all'),[dueOnly,setDueOnly]=useState(true),[showPhone,setShowPhone]=useState(true),[showType,setShowType]=useState(true),[groupByOwner,setGroupByOwner]=useState(true);
 const [data,setData]=useState(null),[loading,setLoading]=useState(true),[error,setError]=useState(''),[refresh,setRefresh]=useState(0);
 useEffect(()=>{let live=true;setLoading(true);setError('');setData(null);
  if(!asOf){setLoading(false);return()=>{live=false;};}
  supabase.rpc('solar_party_balances',{report_kind:mode,as_of:asOf}).then(({data,error})=>{if(!live)return;if(error)throw error;setData(data);}).catch(e=>{if(live)setError(e.code==='42501'?'ليس لديك صلاحية عرض هذا التقرير.':'تعذر تحميل الأرصدة. اضغط تحديث لإعادة المحاولة.');}).finally(()=>{if(live)setLoading(false);});
  return()=>{live=false;};
 },[mode,asOf,refresh]);
 const options=useMemo(()=>({mode,asOf,query,ownerId,wholesale:category!=='system',systems:category!=='wholesale',dueOnly:customer||dueOnly,showPhone,showType,groupByOwner,scope:data?.scope||''}),[mode,asOf,query,ownerId,category,customer,dueOnly,showPhone,showType,groupByOwner,data]);
 const rows=useMemo(()=>filterBalances(data?.rows||[],options),[data,options]);
 const legacy=useMemo(()=>filterUnresolved(data?.unresolved_rows||[],options),[data,options]);
 const groups=customer&&groupByOwner?groupBalances(rows):[{id:'all',name:'',rows,total:balancesTotal(rows)}];
 const total=balancesTotal(rows),wholesaleTotal=balancesTotal(rows.filter(r=>r.customer_type==='wholesale')),systemsTotal=balancesTotal(rows.filter(r=>r.customer_type!=='wholesale'));
 const ownerName=ownerId==='all'?data?.scope:(data?.owners||[]).find(o=>ownerKey(o.id)===ownerId)?.name||'غير مخصص';
 const ready=!!data&&data.as_of===asOf&&!loading&&!error;
 const html=ready?a4(title,balancesDocument(rows,{...options,ownerName,unresolved:legacy}),money(total)+' د.ع',asOf):'';
 const columns=5+(showPhone?1:0)+(customer&&showType?1:0);
 return <section className="accountWorkspace debtorWorkspace">
  <header className="accountHero"><span className="accountHeroIcon"><ReportIcon name={customer?'users':'wallet'}/></span><div><span className="accountEyebrow">التقارير المالية</span><h1>{title}</h1><p>{customer?'ديون الجملة والمنظومات حسب مسؤول العميل.':'رصيد الموردين وآخر دفعة ضمن صلاحيات حسابك.'}</p></div><button className="reportRefresh" disabled={loading} onClick={()=>setRefresh(n=>n+1)}><ReportIcon name="refresh"/>{loading?'جاري التحديث':'تحديث الأرصدة'}</button></header>
  <section className="accountFilterPanel" aria-label="تصفية تقرير الأرصدة"><div className="accountFilterTitle"><div><h2>تصفية المدينين</h2></div><span className="accountScopeBadge">{data?.scope||'ضمن صلاحياتك'}</span></div>
   <div className="accountFilterGrid"><label className="accountSearchField">بحث بالاسم أو الهاتف<div><ReportIcon name="search"/><input aria-label="بحث الأرصدة" value={query} onChange={e=>setQuery(e.target.value)} placeholder="اسم العميل أو رقم الهاتف…"/>{query&&<button aria-label="مسح بحث الأرصدة" onClick={()=>setQuery('')}>×</button>}</div></label>
    {customer&&<label>مسؤول العميل{profile?.is_admin?<select aria-label="مستخدم تقرير المدينين" value={ownerId} onChange={e=>setOwnerId(e.target.value)}><option value="all">جميع المستخدمين</option>{(data?.owners||[]).map(o=><option key={ownerKey(o.id)} value={ownerKey(o.id)}>{o.name}</option>)}</select>:<div className="accountReadonly">{profile?.display_name||profile?.username||'زبائني المخصصون لي'}</div>}</label>}
    <label>لغاية تاريخ<input aria-label="الرصيد لغاية" type="date" value={asOf} max={baghdadToday()} onChange={e=>setAsOf(e.target.value)}/></label>
   </div>
   <div className="accountFilterBottom">{customer?<div className="accountSegments" role="group" aria-label="نوع بيع المدينين">{[['all','الكل'],['wholesale','جملة'],['system','منظومات']].map(([key,label])=><button key={key} aria-pressed={category===key} className={category===key?'active':''} onClick={()=>setCategory(key)}>{label}</button>)}</div>:<label className="accountCheck"><input type="checkbox" checked={dueOnly} onChange={e=>setDueOnly(e.target.checked)}/>المبالغ المستحقة فقط</label>}
    <div className="accountColumnOptions"><label className="accountCheck"><input type="checkbox" checked={showPhone} onChange={e=>setShowPhone(e.target.checked)}/>الهاتف</label>{customer&&<><label className="accountCheck"><input type="checkbox" checked={showType} onChange={e=>setShowType(e.target.checked)}/>النوع</label><label className="accountCheck"><input type="checkbox" checked={groupByOwner} onChange={e=>setGroupByOwner(e.target.checked)}/>تجميع حسب المستخدم</label></>}</div>
   </div>
  </section>
  {!asOf&&<p className="accountAlert error" role="alert">اختر تاريخ الرصيد.</p>}{error&&<p className="accountAlert error" role="alert">{error}</p>}
  <div className={'accountSummary '+(!customer?'supplierSummary':'')}><div className="accountSummaryPrimary"><span>{customer?'إجمالي المستحق لنا':'إجمالي الأرصدة المختارة'}</span><b data-testid="debt-total">{money(total)} <small>د.ع</small></b><small>{rows.length} {customer?'عميل':'مورد'} ضمن الاختيارات</small></div>{customer&&<><div className="wholesale"><span><i/>ديون الجملة</span><b>{money(wholesaleTotal)} <small>د.ع</small></b><small>{rows.filter(r=>r.customer_type==='wholesale').length} عميل</small></div><div className="systems"><span><i/>ديون المنظومات</span><b>{money(systemsTotal)} <small>د.ع</small></b><small>{rows.filter(r=>r.customer_type!=='wholesale').length} عميل</small></div></>}</div>
  <div className="accountReportBar"><div><span className="accountEyebrow">جاهز للمراجعة والتصدير</span><h2>{customer?'قائمة المدينين':'قائمة الموردين'} <small>{rows.length}</small></h2></div><ReportActions enabled={ready} html={html} filename={title+'-'+(ownerName||'')+'-'+asOf}/></div>
  {loading?<div className="accountEmpty" role="status"><span className="accountSpinner"/>جاري احتساب الأرصدة…</div>:ready&&<>
   <div className="accountTableWrap"><table className="accountTable debtorTable"><thead><tr><th>#</th><th>{customer?'العميل':'المورد'}</th>{showPhone&&<th>رقم الهاتف</th>}{customer&&showType&&<th>النوع</th>}<th>{customer?'الرصيد المدين':'الرصيد للمورد'}</th><th>آخر تسديد</th><th>تاريخ التسديد</th></tr></thead><tbody>{groups.map((group,groupIndex)=><GroupRows key={group.id} group={group} customer={customer} groupByOwner={groupByOwner} columns={columns} showPhone={showPhone} showType={showType} startIndex={groups.slice(0,groupIndex).reduce((sum,g)=>sum+g.rows.length,0)}/>)}</tbody></table>{!rows.length&&<div className="accountEmpty"><ReportIcon name="search"/><h3>لا توجد أرصدة مطابقة</h3><p>جرّب تغيير المستخدم أو نوع البيع أو البحث.</p></div>}</div>
   {legacy.length>0&&<details className="accountLegacy"><summary><span className="accountLegacyMark">i</span><span><b>سجل قديم للمراجعة</b><small>{legacy.length} حركة محفوظة بصورة مستقلة</small></span><span>عرض التفاصيل⌄</span></summary><div><p>هذه الحركات غير مرتبطة بحساب مسجّل حاليًا، لذلك تظهر في ملحق مستقل في PDF ولا تُضاف إلى مجموع الأرصدة أعلاه. مبالغها الأصلية محفوظة.</p><div className="accountLegacyRows">{legacy.map(row=><article key={row.id}><div><b>{row.name||'بدون اسم'}</b><span>{legacyReason(row)}</span><small>{row.owner_name} · {balanceDate(row.date)} · #{row.receipt_no||row.id}</small></div><strong>{money(row.effect)} <small>د.ع</small></strong></article>)}</div></div></details>}
   <p className="accountFootnote">جميع المبالغ بالدينار العراقي. {customer?'التجميع حسب مسؤول العميل عن الزبون، ويشمل كامل حسابه حتى لو استلم مستخدم آخر التسديد.':'الرصيد السالب دفعة مقدمة لنا عند المورد.'} آخر تسديد يستثني الأرصدة الافتتاحية والمطابقات.</p>
  </>}
 </section>;
}
function GroupRows({group,customer,groupByOwner,columns,showPhone,showType,startIndex}){
 return <>{customer&&groupByOwner&&<tr className="accountOwnerRow"><td colSpan={columns}><div><span className="accountOwnerAvatar"><ReportIcon name="users"/></span><strong>{group.name}</strong><small>{group.rows.length} عميل</small><b>{money(group.total)} <span>د.ع</span></b></div></td></tr>}{group.rows.map((row,index)=><tr key={row.id} className="accountDataRow"><td data-label="ت">{startIndex+index+1}</td><td data-label={customer?'العميل':'المورد'} className="accountNameCell"><b>{row.name}</b></td>{showPhone&&<td className="accountPhoneCell" data-label="رقم الهاتف">{row.phone?<PhoneActions phone={row.phone} label={row.name}/>:<span>—</span>}</td>}{customer&&showType&&<td className="accountCategoryCell" data-label="النوع"><span className={'accountTypeBadge '+row.customer_type}>{partyType(row.customer_type)}</span></td>}<td data-label={customer?'الرصيد المدين':'الرصيد للمورد'} className="accountAmountCell"><bdi>{money(row.balance)}</bdi><small>د.ع</small></td><td data-label="آخر تسديد" className="accountPaymentCell">{row.last_payment==null?'—':money(row.last_payment)}</td><td data-label="تاريخ التسديد" className="accountDateCell">{balanceDate(row.last_payment_at)}</td></tr>)}</>;
}
