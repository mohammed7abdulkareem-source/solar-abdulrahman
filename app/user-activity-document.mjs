import {escapeHtml} from './document-format.mjs';
import {formatMoney,currencyUnit} from './money-format.mjs';

const roleNames={warehouse:'المخزن',installer:'التنصيب'};
const operations={
 warehouse:[['prepared','وصولات جُهّزت'],['edited','تعديلات التجهيز'],['reopened','إعادة فتح التجهيز'],['transfersPrepared','مناقلات مخزنية جُهّزت']],
 installer:[['scheduled','مواعيد التنصيب'],['started','تنصيبات بدأها'],['completed','تقارير إنجاز رفعها'],['closed','ملفات أغلقتها الإدارة']]
};
const periodTypes={day:'اليومية',month:'الشهرية',year:'السنوية'};

function numeric(value){
 if(typeof value!=='number'&&(typeof value!=='string'||!value.trim()))return null;
 return Number.isFinite(Number(value))?Number(value):null;
}
function number(value,currency){
 if(numeric(value)===null)return 'غير متاح';
 return '<bdi dir="ltr">'+formatMoney(value,currency)+'</bdi>'+(currency?' '+currencyUnit(currency):'');
}
function percent(value){
 return numeric(value)===null?'غير محتسب':number(value)+'٪';
}
function metric(label,value){
 return '<div class="reportMetric"><span>'+label+'</span><strong>'+value+'</strong></div>';
}
function table(title,columns,rows){
 const headers=columns.map(label=>'<th scope="col">'+label+'</th>').join('');
 const body=rows.map(cells=>'<tr>'+cells.map(cell=>'<td>'+cell+'</td>').join('')+'</tr>').join('');
 return '<table><caption>'+title+'</caption><thead><tr>'+headers+'</tr></thead><tbody>'+body+'</tbody></table>';
}
function dates(start,end){
 const first=escapeHtml(start||'البداية'),last=escapeHtml(end||'—');
 return '<bdi>'+first+'</bdi>'+(start===end?'':' إلى <bdi>'+last+'</bdi>');
}
function chart(series,key,label,color){
 const values=series.map(point=>numeric(point[key]));
 if(!values.length||values.includes(null))return '';
 // The two plots each have their own range; zero stays visible for losses and flat series.
 const low=values.reduce((min,value)=>Math.min(min,value),0);
 const high=values.reduce((max,value)=>Math.max(max,value),0);
 const width=580,height=76;
 const x=i=>values.length===1?width/2:4+(width-8)*i/(values.length-1);
 const y=value=>high===low?height/2:5+(height-10)*(high-value)/(high-low);
 const coords=values.map((value,i)=>x(i).toFixed(2)+','+y(value).toFixed(2)).join(' ');
 const end=values.length-1,baseline=y(0).toFixed(2);
 return '<figure data-activity-chart="'+key+'"><figcaption><b>'+label+'</b><span>دينار عراقي</span></figcaption>'+
  '<div class="uaPlot"><div class="uaScale"'+(high===low?' style="justify-content:center"':'')+'>'+
  '<bdi>'+formatMoney(high)+'</bdi>'+(high===low?'':'<bdi>'+formatMoney(low)+'</bdi>')+'</div>'+
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 '+width+' '+height+'" preserveAspectRatio="none" role="img" aria-label="'+label+'">'+
  '<line x1="0" x2="'+width+'" y1="'+baseline+'" y2="'+baseline+'" stroke="#81939e" stroke-dasharray="4 3"/>'+
  '<polyline points="'+coords+'" fill="none" stroke="'+color+'" stroke-width="2.7" stroke-linejoin="round"/>'+
  '<circle cx="'+x(0)+'" cy="'+y(values[0])+'" r="3.5" fill="'+color+'"/>'+
  (end?'<circle cx="'+x(end)+'" cy="'+y(values[end])+'" r="3.5" fill="'+color+'"/>':'')+'</svg></div>'+
  '<div class="uaDateAxis"><bdi>'+escapeHtml(series[0].start)+'</bdi><bdi>'+escapeHtml(series[end].end)+'</bdi></div></figure>';
}

export function userActivityDocument(data){
 if(!data?.user?.id||!data.performance||!Array.isArray(data.performance.series))return null;
 const {user,performance:p,sales={},profit={},cash={},debts={},collections={},handovers={},expenses={}}=data;
 const period=dates(data.from,data.to),role=roleNames[user.userType]||'المكتب';
 const count=numeric(sales.count),revenue=numeric(sales.totalIQD);
 const average=count>0&&revenue!==null?number(revenue/count,'IQD'):'غير محتسب';
 const summary='<div class="reportSummary">'+[
  metric('إجمالي المبيعات',number(sales.totalIQD,'IQD')),metric('عدد فواتير البيع',number(sales.count)),metric('متوسط قيمة الفاتورة',average),
  metric('ربح الشركة من فواتير المستخدم',number(p.companyProfitIQD,'IQD')),metric('هامش ربح الفواتير المؤهلة',percent(p.marginPercent)),metric('حصة المستخدم المعتمدة بالتسويات',number(p.approvedShareIQD,'IQD'))
 ].join('')+'</div>';
 const definition='<p class="uaProfitBasis">ربح الشركة هو ربح فواتير الجملة والمنظومات المغلقة التي أصدرها المستخدم، قبل توزيع الأرباح وبحسب تاريخ الفاتورة. '+
  'أساس الهامش هو قيمة بضاعة الجملة وقيمة المنظومات المغلقة، ومجموعهما '+number(p.eligibleSalesIQD,'IQD')+'. حصة المستخدم هي المبلغ المخصّص له في التسويات التي اعتُمِدت خلال الفترة.</p>';
 const series=p.series;
 const plots=chart(series,'salesIQD','المبيعات خلال الفترة','#136597')+chart(series,'companyProfitIQD','ربح الشركة خلال الفترة','#177454');
 const timeline=series.length?table('تفاصيل المبيعات والأرباح '+(periodTypes[p.granularity]||'خلال الفترة'),
  ['الفترة','عدد الفواتير','المبيعات (د.ع)','ربح الشركة (د.ع)'],series.map(row=>[
   dates(row.start,row.end),number(row.invoiceCount),number(row.salesIQD),number(row.companyProfitIQD)
  ])):'<p class="reportEmpty">لا توجد بيانات زمنية للفترة المختارة.</p>';
 const details=table('مبيعات المستخدم خلال الفترة',['نوع البيع','عدد الفواتير','إجمالي المبيعات (د.ع)'],[
  ['جملة',number(sales.wholesaleCount),number(sales.wholesaleIQD)],['منظومات',number(sales.systemCount),number(sales.systemIQD)]
 ]);
 const shares=table('تسويات حصة المستخدم خلال الفترة',['عدد التسويات المعتمدة','الأرباح المشمولة (د.ع)','حصة المستخدم (د.ع)','نسبة الحصة من الأرباح المشمولة'],[
  [number(p.approvedShareCount),number(p.approvedShareBaseIQD),number(p.approvedShareIQD),percent(p.approvedSharePercent)]
 ]);
 const account=table('الأرباح وديون الزبائن',['البند','المبلغ (د.ع)'],[
  ['صافي نتيجة المستخدم خلال الفترة',number(profit.earnedIQD)],['رصيد أرباح المستخدم الآن · كل الفترات',number(profit.remainingIQD)],
  ['ديون الزبائن حتى '+escapeHtml(data.to||'تاريخ التقرير'),number(debts.dueIQD)],['أرصدة لصالح الزبائن حتى نفس التاريخ',number(debts.creditIQD)]
 ]);
 const finance=table('القاصة والتحصيل',['البند','دينار عراقي','دولار أمريكي'],[
  ['رصيد القاصة الآن',number(cash.IQD),number(cash.USD)],
  ['تحصيلات الزبائن خلال الفترة',number(collections.IQD),number(collections.USD)],
  ['المصاريف النقدية خلال الفترة',number(expenses.cash?.IQD),number(expenses.cash?.USD)],
  ['تسليمات للمستخدمين خلال الفترة',number(handovers.outgoing?.IQD),number(handovers.outgoing?.USD)],
  ['استلامات من المستخدمين خلال الفترة',number(handovers.incoming?.IQD),number(handovers.incoming?.USD)]
 ]);
 const fields=operations[user.userType],roleMetrics=data.operations?.[user.userType];
 const operationsTable=fields&&roleMetrics?table('نشاط '+role+' خلال الفترة',['العملية','العدد'],
  fields.map(([key,label])=>[label,number(roleMetrics[key])])):'';
 const body='<section class="activityReportDocument"><style>'+
  '.activityReportDocument{color:#183b4a}.activityReportDocument .reportSummary{grid-template-columns:repeat(3,minmax(0,1fr))}'+
  '.activityReportDocument .uaProfitBasis{color:#334d5b;font-size:12px;line-height:1.8;margin:8px 0 12px}'+
  '.activityReportDocument figure{margin:10px 0 14px;padding:8px 12px;border:1px solid #d5e0e5;border-radius:5px;break-inside:avoid}'+
  '.activityReportDocument figcaption{display:flex;justify-content:space-between;color:#173e4c}.activityReportDocument figcaption span{color:#425a65;font-size:11px}'+
  '.activityReportDocument .uaPlot{display:flex;align-items:stretch;gap:8px;direction:ltr}.activityReportDocument .uaPlot svg{height:76px;width:100%;min-width:0}'+
  '.activityReportDocument .uaScale{min-width:82px;display:flex;flex-direction:column;justify-content:space-between;text-align:right;font-size:11px;color:#405968}'+
  '.activityReportDocument .uaDateAxis{direction:ltr;display:flex;justify-content:space-between;gap:8px;margin-left:90px;font-size:10px;color:#405968}'+
  '.activityReportDocument table{margin:12px 0 0}.activityReportDocument caption{font-weight:bold;text-align:right;color:#173e4c;font-size:14px;padding:6px 0}'+
  '</style>'+summary+definition+plots+details+operationsTable+shares+account+
  '<p class="uaProfitBasis">صافي نتيجة المستخدم هو صافي الحركات المنسوبة إلى حساب أرباحه خلال الفترة.</p>'+finance+timeline+'</section>';
 return {title:'تقرير نشاط المستخدم',subtitle:escapeHtml(user.name)+' · '+role+' · '+period,body,
  filename:['نشاط',user.name,data.from||'البداية',data.to].filter(Boolean).join('-')};
}
