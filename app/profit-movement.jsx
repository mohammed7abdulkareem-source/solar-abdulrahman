'use client';
import PhoneActions from './phone-actions';
import {useEffect,useId,useState} from 'react';
import {supabase} from './supabase';
import AppIcon from './app-icons';
import ReportActions from './report-actions';
import {receiptProfitFigures,profitMaterialDocument} from './profit-material-document.mjs';
import {money,dateKey,escapeHtml as e} from './supplier-utils.mjs';

export default function ProfitMovement({row,ownerId,a4,meta,companyBasis=false}){
 const [open,setOpen]=useState(false),[data,setData]=useState(null),[loading,setLoading]=useState(false),[error,setError]=useState(''),[retry,setRetry]=useState(0),id=useId();
 useEffect(()=>{if(!open||row.receiptRestricted)return;let live=true;setLoading(true);setError('');setData(null);
  supabase.rpc(companyBasis?'solar_company_profit_detail':'solar_profit_detail',{source_key:row.key,owner_id:ownerId}).then(({data,error})=>{if(!live)return;if(error){setError(error.message||'تعذر فتح تفاصيل الوصل.');return;}setData(data);}).catch(()=>{if(live)setError('تعذر الاتصال. أعد المحاولة.');}).finally(()=>{if(live)setLoading(false);});
  return()=>{live=false;};
 },[open,row.key,row.receiptRestricted,ownerId,companyBasis,retry]);
 const invoice=data?.invoice,breakdown=data?.breakdown,isSale=!!breakdown,system=breakdown?.kind==='system',document=breakdown?profitMaterialDocument(breakdown,row):null;
 const external=row.kind==='external_adjustment';
 const adjustment=external&&(data?.movement?.adjustment||row.adjustment);
 const detailDoc=data&&!isSale?a4('تفاصيل حركة أرباح','<div class="meta"><div>الحركة: '+e(row.label)+'</div><div>التاريخ: '+e(dateKey(row.date))+'</div></div><p>الربح / الأثر: '+money(row.value)+' د.ع</p><p>المسوّى سابقاً: '+money(row.settled)+' د.ع</p><p>غير المسوّى: '+money(row.available)+' د.ع</p>'+(invoice?.notes?'<p class="notes">'+e(invoice.notes)+'</p>':'')):'';
 if(row.receiptRestricted||data?.receiptRestricted)return <article className="profitMovement profitMovementRestricted"><div className="profitMovementRestrictedHead"><span className="profitMovementIdentity"><b>أثر حسابي على أرباحك</b><small>{dateKey(row.date)}</small><small>المسوّى: {money(row.settled)} د.ع</small></span><strong className={Number(row.available)<0?'negative':''}>{money(row.available)} <small>د.ع</small></strong></div></article>;
 if(row.kind==='personal_distribution')return <article className="profitMovement profitMovementRestricted"><div className="profitMovementRestrictedHead">
  <span className="profitMovementIdentity"><b>{row.label}</b><small>{dateKey(row.date)}</small><small>المبلغ المدفوع: <bdi>{money(row.settled)}</bdi> د.ع</small></span>
  <span>الأثر على المتاح <strong><bdi>{money(row.available)}</bdi> د.ع</strong></span>
 </div></article>;
 return <details className="profitMovement" open={open} onToggle={ev=>setOpen(ev.currentTarget.open)}><summary aria-controls={id} aria-label={external?'تفاصيل تسوية الأرباح الخارجية':'تفاصيل الوصل '+(row.receiptNo||row.label)}><span className="profitMovementIdentity"><b>{row.label}{row.deleted?' · حركة ملغاة':''}</b><small>{dateKey(row.date)}{row.receiptNo?' · #'+row.receiptNo:''}</small>{meta&&<small>{meta}</small>}</span><strong className={Number(external&&adjustment?adjustment.delta:row.available)<0?'negative':''}>{money(external&&adjustment?adjustment.delta:row.available)} <small>د.ع</small></strong><span className="profitMovementArrow"><AppIcon name="chevron" size={18}/></span></summary>
  <div id={id} className="profitMovementDetail">{loading&&<p role="status">جاري تحميل تفاصيل الوصل…</p>}{error&&<div role="alert"><p>{error}</p><button type="button" className="uiButton" onClick={()=>setRetry(n=>n+1)}>إعادة المحاولة</button></div>}{data&&<>
   <h3>{isSale?(system?'فاتورة بيع منظومة':'فاتورة بيع جملة'):external?'تسوية أرباح خارجية':'تفاصيل الحركة'}{row.receiptNo?' #'+row.receiptNo:''}</h3>
   {adjustment&&<div className="profitExternalAudit">
    <dl>{[['الرصيد قبل التعديل',adjustment.before],['الرصيد بعد التعديل',adjustment.after],['فرق التعديل',adjustment.delta]].map(([label,value])=><div key={label}><dt>{label}</dt><dd><bdi>{money(value)}</bdi> د.ع</dd></div>)}</dl>
    {adjustment.actorName&&<p>سجّل التعديل: {adjustment.actorName}</p>}{adjustment.note&&<p>{adjustment.note}</p>}
   </div>}
   {invoice&&<p className="profitMovementAuthor">{invoice.creatorName}{invoice.creatorPhone&&<> · <PhoneActions phone={invoice.creatorPhone} label={invoice.creatorName||'المسؤول'}/></>}</p>}
   {breakdown&&<><p className="profitMovementAuthor">{breakdown.party||'زبون نقدي'} · {breakdown.warehouseName}</p>{breakdown.responsibleName&&<p className="profitMovementAuthor">منشئ الوصل {breakdown.creatorName||'غير محدد'} · المسؤول عن الوصل {breakdown.responsibleName}</p>}<dl className="receiptProfitFigures">{receiptProfitFigures(breakdown).map(([key,label,value])=><div data-profit-component={key} key={key}><dt>{label}</dt><dd><bdi>{money(value)}</bdi> د.ع</dd></div>)}</dl>{breakdown.costHidden&&<p className="profitMovementBalance">تظهر كلفة المواد التي حُدّد لها سعر عند إصدار الوصل.</p>}{system&&!breakdown.costHidden&&<p className="profitMovementBalance">سعر المنظومة إجمالي متفق عليه؛ تظهر كلفة كل مادة وربح المنظومة كاملًا.</p>}<div className="profitMovementTable"><table><thead><tr><th>المادة</th><th>العدد</th>{!system&&<th>سعر البيع / وحدة</th>}<th>الكلفة / وحدة</th><th>كلفة الفقرة</th>{!system&&<th>ربح الفقرة</th>}</tr></thead><tbody>{breakdown.items.map((item,index)=><tr key={item.id||index}><td><b>{item.name}</b><small>{[item.code&&'كود '+item.code,item.brand,item.category].filter(Boolean).join(' · ')}</small></td><td>{money(item.qty)}</td>{!system&&<td>{money(item.unitPrice)}</td>}<td>{item.unitCost==null?'—':money(item.unitCost)}</td><td>{item.lineCost==null?'—':money(item.lineCost)}</td>{!system&&<td>{item.lineProfit==null?'—':money(item.lineProfit)}</td>}</tr>)}</tbody></table></div></>}
   {data.transferred&&<p className="profitMovementBalance">ربح محوّل لك من الإدارة؛ تظهر مواد الوصل وكلفته وربحه ضمن حساب أرباحك.</p>}{!isSale&&invoice?.notes&&<p>{invoice.notes}</p>}<p className="profitMovementBalance">المسوّى سابقاً: <b>{money(row.settled)}</b> · غير المسوّى: <b>{money(row.available)} د.ع</b></p>
   <ReportActions enabled html={document?a4(document.title,document.body,document.total,document.subtitle):detailDoc} filename={'وصل-'+(row.receiptNo||'حركة-أرباح')}/>
  </>}</div>
 </details>;
}
