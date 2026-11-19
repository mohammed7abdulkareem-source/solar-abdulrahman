'use client';
import {useId,useState} from 'react';
import {formatMoney} from './money-format.mjs';

const seriesChoices=[['salesIQD','المبيعات'],['companyProfitIQD','ربح الشركة']];
const grouping={day:'يومي',month:'شهري',year:'سنوي'};
const compactMoney=new Intl.NumberFormat('ar-IQ',{notation:'compact',maximumFractionDigits:1});
const dateFormats=Object.fromEntries(Object.entries({
 day:{day:'numeric',month:'short'},month:{month:'short',year:'numeric'},year:{year:'numeric'}
}).map(([key,options])=>[key,new Intl.DateTimeFormat('ar-IQ',{...options,timeZone:'UTC'})]));
const isNumber=v=>(typeof v==='number'||typeof v==='string'&&v.trim()!=='')&&Number.isFinite(Number(v));
const isoDay=/^\d{4}-\d{2}-\d{2}$/;
function shortDate(raw,granularity){
 const day=new Date(raw+'T12:00:00Z');
 return Number.isNaN(+day)?raw:dateFormats[granularity].format(day);
}
function usablePerformance(p){
 return !!p&&p.currency==='IQD'&&Object.hasOwn(grouping,p.granularity)&&Array.isArray(p.series)&&
  ['companyProfitIQD','eligibleSalesIQD','approvedShareIQD','approvedShareCount','approvedShareBaseIQD'].every(key=>isNumber(p[key]))&&
  (p.marginPercent===null||isNumber(p.marginPercent))&&(p.approvedSharePercent===null||isNumber(p.approvedSharePercent))&&
  p.series.every(row=>row&&isoDay.test(row.start)&&isoDay.test(row.end)&&row.start<=row.end&&['invoiceCount','salesIQD','companyProfitIQD'].every(key=>isNumber(row[key])));
}
function DataValue({value,metric,unit='',unavailable='غير متاح',activityMetric}){
 return <span data-performance-metric={metric} data-activity-metric={activityMetric} className={isNumber(value)&&Number(value)<0?'performanceNegative':undefined}>
  {isNumber(value)?<><bdi dir="ltr">{formatMoney(value)}</bdi>{unit&&<small> {unit}</small>}</>:unavailable}
 </span>;
}
function PeriodTable({rows}){
 return <details className="activitySeriesTable"><summary>جدول الفترات</summary>
  <div className="activityTableScroll" tabIndex={0} role="region" aria-label="تفاصيل المبيعات وربح الشركة لكل فترة">
   <table><thead><tr><th scope="col">الفترة</th><th scope="col">الفواتير</th><th scope="col">المبيعات · د.ع</th><th scope="col">ربح الشركة · د.ع</th></tr></thead>
    <tbody>{rows.map(row=><tr key={row.start} data-start={row.start} data-end={row.end}><th scope="row"><bdi>{row.start}</bdi>{row.start!==row.end&&<> إلى <bdi>{row.end}</bdi></>}</th>
     {['invoiceCount','salesIQD','companyProfitIQD'].map(key=><td data-column={key} key={key}><bdi dir="ltr">{formatMoney(row[key])}</bdi></td>)}</tr>)}</tbody>
   </table>
  </div>
 </details>;
}

function Chart({performance}){
 const [metric,setMetric]=useState('salesIQD'),[picked,setPicked]=useState(null),chartId=useId();
 const rows=performance.series,granularity=performance.granularity;
 const label=seriesChoices.find(([id])=>id===metric)[1];
 const active=rows.find(r=>r.start===picked)||rows.at(-1);
 const activeIndex=active?rows.indexOf(active):0,values=rows.map(r=>Number(r[metric]));
 const maximum=Math.max(0,...values),minimum=Math.min(0,...values);
 const extent=maximum-minimum||1,zero=100*maximum/extent;
 const barTone=metric==='salesIQD'?'#087e77':'#79549a';
 const hasInvoices=rows.some(row=>Number(row.invoiceCount)>0);
 return <section className="activityChartPanel" aria-labelledby={chartId}>
  <header className="activityChartHead"><div><h3 id={chartId}>حركة المبيعات وربح الشركة</h3><small>تجميع {grouping[granularity]} · دينار عراقي</small></div>
   <div role="group" aria-label="مؤشر الرسم البياني" className="activityChartSwitch">{seriesChoices.map(([id,name])=><button type="button" key={id} aria-pressed={metric===id} onClick={()=>setMetric(id)}>{name}</button>)}</div>
  </header>
  {!rows.length||!hasInvoices?<p className="activityChartEmpty" role="status">لا توجد فواتير بيع ضمن الفترة المختارة.</p>:<>
   {maximum===0&&minimum===0?<p className="activityChartEmpty" role="status">{metric==='companyProfitIQD'?'ربح الشركة المحقّق يساوي صفراً في كل فترات الرسم.':'قيمة المبيعات تساوي صفراً في كل فترات الرسم.'}</p>:
    <div className="activityPlot" data-performance-chart data-series={metric} style={{'--activity-zero':zero+'%','--activity-series':barTone}}>
     <div className="activityPlotAxis" aria-hidden="true"><span>{compactMoney.format(maximum)}</span>{minimum<0&&maximum>0&&zero>=14&&zero<=86&&<span className="activityAxisZero">٠</span>}<span>{compactMoney.format(minimum)}</span></div>
     <div className="activityPlotField">
      <div className="activityBars" role="img" aria-label={'مخطط '+label+' حسب تاريخ الفاتورة. التفاصيل في جدول الفترات.'}>
       <i className="activityZeroLine"/>{values.map((v,i)=>{
        const y=100*(maximum-v)/extent;
        return <div aria-hidden="true" className={'activityBarSpace'+(i===activeIndex?' isSelected':'')} key={rows[i].start} onPointerEnter={e=>{if(e.pointerType==='mouse')setPicked(rows[i].start);}} onClick={()=>setPicked(rows[i].start)}>
         <i className={v<0?'negative':''} style={{top:Math.min(y,zero)+'%',height:Math.abs(v)/extent*100+'%'}}/>
        </div>;
       })}
      </div>
      <div className="activityPlotDates" aria-hidden="true"><span>{shortDate(rows[0].start,granularity)}</span>{rows.length>1&&<span>{shortDate(rows.at(-1).start,granularity)}</span>}</div>
     </div>
    </div>}
   <div className="activityBucket">
    <div aria-live="polite"><small>{label} من <bdi>{active.start}</bdi>{active.end!==active.start&&<> إلى <bdi>{active.end}</bdi></>}</small><strong className={Number(active[metric])<0?'performanceNegative':undefined}><bdi dir="ltr">{formatMoney(active[metric])}</bdi> د.ع</strong></div>
    {rows.length>1&&<div className="activityBucketButtons"><button type="button" aria-label="الفترة السابقة في الرسم" disabled={activeIndex===0} onClick={()=>setPicked(rows[activeIndex-1].start)}>السابق</button><button type="button" aria-label="الفترة التالية في الرسم" disabled={activeIndex===rows.length-1} onClick={()=>setPicked(rows[activeIndex+1].start)}>التالي</button></div>}
   </div>
  </>}
  {rows.length>0&&<PeriodTable rows={rows}/>}
 </section>;
}

export {usablePerformance};
export default function ActivityPerformance({data}){
 const p=data.performance;
 if(!usablePerformance(p))return <p className="activityFeedback" role="status">تفاصيل أداء المبيعات غير متاحة لهذه الفترة.</p>;
 const average=isNumber(data.sales?.totalIQD)&&isNumber(data.sales?.count)&&Number(data.sales.count)>0?Number(data.sales.totalIQD)/Number(data.sales.count):null;
 return <section className="activityPerformance" aria-label="أداء المبيعات والأرباح">
  <dl className="activityPerformanceCards">
   <div className="performanceSales"><dt>إجمالي مبيعات المستخدم</dt><dd><DataValue value={data.sales?.totalIQD} metric="salesIQD" activityMetric="sales.totalIQD" unit="د.ع"/></dd>
    <dd className="activityKpiFoot">عدد الفواتير <DataValue value={data.sales?.count} metric="invoiceCount" activityMetric="sales.count"/></dd></div>
   <div className="performanceCompany"><dt>ربح الشركة من فواتير المستخدم</dt><dd><DataValue value={p.companyProfitIQD} metric="companyProfitIQD" unit="د.ع"/></dd>
    <dd className="activityKpiFoot">هامش ربح الفواتير المؤهلة <DataValue value={p.marginPercent} metric="marginPercent" unit="%" unavailable="غير محتسب"/></dd></div>
   <div className="performanceShare"><dt>حصة المستخدم المعتمدة بالتسويات</dt><dd><DataValue value={p.approvedShareIQD} metric="approvedShareIQD" unit="د.ع"/></dd>
    <dd className="activityKpiFoot">نسبته من أرباح التسويات <DataValue value={p.approvedSharePercent} metric="approvedSharePercent" unit="%" unavailable="غير محتسبة"/></dd></div>
   <div className="performanceMean"><dt>متوسط قيمة الفاتورة</dt><dd><DataValue value={average} metric="averageInvoiceIQD" unit="د.ع" unavailable="غير محتسب"/></dd></div>
  </dl>
  <Chart performance={p}/>
  <details className="activityPerformanceBasis"><summary>كيف تُحسب الأرباح والحصص؟</summary>
   <p>يُحسب هامش الشركة بقسمة ربح مبيعات المستخدم على قيمة المبيعات الداخلة بحساب الربح، وهي <DataValue value={p.eligibleSalesIQD} metric="eligibleSalesIQD" unit="د.ع"/>. يشمل الأساس قيمة مواد الجملة بعد استبعاد المصاريف المحمّلة على الزبون، وقيمة فواتير المنظومات المغلقة.</p>
   <p>تظهر المبيعات وأرباحها حسب تاريخ الفاتورة. يدخل ربح المنظومة بعد إغلاقها. حصة المستخدم هي مجموع المبالغ المعتمدة له حسب تاريخ اعتماد التسوية.</p>
   <p>تُحسب نسبة حصة المستخدم من أرباح التسويات المعتمدة بقسمة حصته على مجموع أرباح تلك التسويات، وهو <DataValue value={p.approvedShareBaseIQD} metric="approvedShareBaseIQD" unit="د.ع"/>. عدد التسويات المعتمدة في الفترة <DataValue value={p.approvedShareCount} metric="approvedShareCount"/>.</p>
  </details>
 </section>;
}
