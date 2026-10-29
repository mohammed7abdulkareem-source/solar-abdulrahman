'use client';
import PhoneActions from './phone-actions';
import {useEffect,useId,useState} from 'react';
import {supabase} from './supabase';
import AppIcon from './app-icons';
import ReportActions from './report-actions';
import {profitMaterialDocument} from './profit-material-document.mjs';
import {money,dateKey,escapeHtml as e} from './supplier-utils.mjs';

export default function ProfitMovement({row,ownerId,a4,meta}){
 const [open,setOpen]=useState(false),[data,setData]=useState(null),[loading,setLoading]=useState(false),[error,setError]=useState(''),[retry,setRetry]=useState(0),id=useId();
 useEffect(()=>{if(!open)return;let live=true;setLoading(true);setError('');setData(null);
  supabase.rpc('solar_profit_detail',{source_key:row.key,owner_id:ownerId}).then(({data,error})=>{if(!live)return;if(error){setError(error.message||'تعذر فتح تفاصيل الوصل.');return;}setData(data);}).catch(()=>{if(live)setError('تعذر الاتصال. أعد المحاولة.');}).finally(()=>{if(live)setLoading(false);});
  return()=>{live=false;};
 },[open,row.key,ownerId,retry]);
 const invoice=data?.invoice,breakdown=data?.breakdown,isSale=!!breakdown,system=breakdown?.kind==='system',document=breakdown?profitMaterialDocument(breakdown,row):null;
 const detailDoc=data&&!isSale?a4('تفاصيل حركة أرباح','<div class="meta"><div>الحركة: '+e(row.label)+'</div><div>التاريخ: '+e(dateKey(row.date))+'</div></div><p>الربح / الأثر: '+money(row.value)+' د.ع</p><p>المسوّى سابقاً: '+money(row.settled)+' د.ع</p><p>غير المسوّى: '+money(row.available)+' د.ع</p>'+(invoice?.notes?'<p class="notes">'+e(invoice.notes)+'</p>':'')):'';
 return <details className="profitMovement" open={open} onToggle={ev=>setOpen(ev.currentTarget.open)}><summary aria-controls={id} aria-label={'تفاصيل الوصل '+(row.receiptNo||row.label)}><span className="profitMovementIdentity"><b>{row.label}{row.deleted?' · حركة ملغاة':''}</b><small>{dateKey(row.date)}{row.receiptNo?' · #'+row.receiptNo:''}</small>{meta&&<small>{meta}</small>}</span><strong className={Number(row.available)<0?'negative':''}>{money(row.available)} <small>د.ع</small></strong><span className="profitMovementArrow"><AppIcon name="chevron" size={18}/></span></summary>
  <div id={id} className="profitMovementDetail">{loading&&<p role="status">جاري تحميل تفاصيل الوصل…</p>}{error&&<div role="alert"><p>{error}</p><button type="button" className="uiButton" onClick={()=>setRetry(n=>n+1)}>إعادة المحاولة</button></div>}{data&&<>
   <h3>{isSale?(system?'فاتورة بيع منظومة':'فاتورة بيع جملة'):'تفاصيل الحركة'}{row.receiptNo?' #'+row.receiptNo:''}</h3>
   {invoice&&<p className="profitMovementAuthor">{invoice.creatorName}{invoice.creatorPhone&&<> · <PhoneActions phone={invoice.creatorPhone} label={invoice.creatorName||'المسؤول'}/></>}</p>}
   {breakdown&&<><p className="profitMovementAuthor">{breakdown.party||'زبون نقدي'} · {breakdown.warehouseName}</p><div className="profitReceiptTotals"><div><span>مبلغ الفاتورة</span><b>{money(breakdown.total)} د.ع</b></div><div><span>كلفة المواد</span><b>{money(breakdown.materialsCost)} د.ع</b></div><div><span>ربح الحركة</span><b>{money(breakdown.netProfit)} د.ع</b></div></div>{system&&<p className="profitMovementBalance">سعر المنظومة إجمالي متفق عليه؛ تظهر كلفة كل مادة وربح المنظومة كاملًا.</p>}<div className="profitMovementTable"><table><thead><tr><th>المادة</th><th>العدد</th>{!system&&<th>سعر البيع / وحدة</th>}<th>الكلفة / وحدة</th><th>كلفة الفقرة</th>{!system&&<th>ربح الفقرة</th>}</tr></thead><tbody>{breakdown.items.map((item,index)=><tr key={item.id||index}><td><b>{item.name}</b><small>{[item.code&&'كود '+item.code,item.brand,item.category].filter(Boolean).join(' · ')}</small></td><td>{money(item.qty)}</td>{!system&&<td>{money(item.unitPrice)}</td>}<td>{money(item.unitCost)}</td><td>{money(item.lineCost)}</td>{!system&&<td>{money(item.lineProfit)}</td>}</tr>)}</tbody></table></div><p className="profitMovementBalance">مصاريف الفاتورة: <b>{money(breakdown.invoiceExpenses)}</b> · مصاريف التنصيب المعتمدة: <b>{money(breakdown.installationExpenses)} د.ع</b></p>{Math.abs(Number(breakdown.profitAdjustment))>=.005&&<p className="profitMovementBalance">تعديلات ربح الفاتورة المحفوظة: <b>{money(breakdown.profitAdjustment)} د.ع</b></p>}</>}
   {data.transferred&&<p className="profitMovementBalance">ربح محوّل لك من الإدارة؛ تظهر مواد الوصل وكلفته وربحه ضمن حساب أرباحك.</p>}{!isSale&&invoice?.notes&&<p>{invoice.notes}</p>}<p className="profitMovementBalance">المسوّى سابقاً: <b>{money(row.settled)}</b> · غير المسوّى: <b>{money(row.available)} د.ع</b></p>
   <ReportActions enabled html={document?a4(document.title,document.body,document.total,document.subtitle):detailDoc} filename={'وصل-'+(row.receiptNo||'حركة-أرباح')}/>
  </>}</div>
 </details>;
}
