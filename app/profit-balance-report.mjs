import {money,dateKey,escapeHtml as e} from './supplier-utils.mjs';

export function profitBalanceReport({balance,ownerName,from,to,rows,expenses,fx,externalProfit,type='all'}){
 if(!balance)return '';
 const salesType=type==='sale'?'بيع الجملة':type==='system'?'المنظومات المغلقة':'الجملة والمنظومات المغلقة';
 const amount=value=>{
  if(value==null)return '—';
  const text=money(value);
  return '<bdi dir="ltr" class="reportNumber'+(text.length>14?' reportNumberLong':'')+'">'+text+'</bdi>';
 };
 return '<div class="meta"><div>المستخدم: '+e(ownerName)+'</div><div>فترة العمليات: '+e(from||'البداية')+' — '+e(to||'اليوم')+'</div><div>العملة: الدينار العراقي · IQD</div><div>المبيعات: '+salesType+'</div></div>'+
  '<h3 class="reportSectionTitle">الرصيد الحالي · جميع الفترات</h3><div class="reportCurrentBalance"><strong>الأرباح المتبقية بعد التسوية: '+amount(balance.remaining??0)+' د.ع</strong><p>الرصيد الحالي لجميع الفترات، بعد حصص المستخدمين وبقية الأرباح المضافة للموردين وتوزيعات الإدارة. مستقل عن رصيد القاصة وعن فلاتر الفترة والمبيعات.</p></div>'+
  '<h3 class="reportSectionTitle">نتائج الفترة المختارة · د.ع</h3><div class="reportSummary">'+[
   ['ربح الفترة قبل التسويات',balance.period.earned],['المسوّى من أرباح الفترة',balance.period.settled],['غير المسوّى من أرباح الفترة',balance.period.available]
  ].map(([label,value])=>'<div class="reportMetric"><span>'+label+'</span><strong>'+amount(value)+' د.ع</strong></div>').join('')+'</div>'+
  '<h3 class="reportSectionTitle">تفاصيل المبيعات · '+rows.length+' فاتورة</h3><table data-pdf-paginate><colgroup><col style="width:12%"><col style="width:23%"><col style="width:13%"><col style="width:13%"><col style="width:13%"><col style="width:13%"><col style="width:13%"></colgroup><thead><tr><th>التاريخ</th><th>العملية / العميل / الوصل</th><th>المبيعات د.ع</th><th>الكلفة د.ع</th><th>الربح قبل التسوية</th><th>المسوّى</th><th>غير المسوّى</th></tr></thead><tbody>'+(rows.length?rows.map(t=>'<tr><td>'+e(dateKey(t.date))+'</td><td>'+e(t.kind==='system'?'منظومة':'جملة')+'<br>'+e(t.party||'نقدي')+(t.receiptNo!=null?'<br><small>وصل #'+e(t.receiptNo)+'</small>':'')+'</td><td>'+amount(t.sales)+'</td><td>'+amount(t.cost)+'</td><td>'+amount(t.earned)+'</td><td>'+amount(t.settled)+'</td><td>'+amount(t.available)+'</td></tr>').join(''):'<tr><td colspan="7" class="reportEmpty">لا توجد مبيعات ضمن الفترة والاختيارات.</td></tr>')+'</tbody></table>'+
  '<h3 class="reportSectionTitle">بنود أخرى ضمن الفترة · د.ع</h3><div class="reportSummary">'+[
   ['المصاريف التشغيلية للفترة',expenses],['فرق الصرف المحقق',fx],['الأرباح الخارجية',externalProfit]
  ].map(([label,value])=>'<div class="reportMetric"><span>'+label+'</span><strong>'+amount(value)+' د.ع</strong></div>').join('')+'</div><p class="notes">تبقى أرباح المبيعات التاريخية وكلفتها المثبتة محفوظة. المصاريف التشغيلية تستثني حصص تسوية الأرباح حتى لا تُطرح مرتين. الرمز — يعني أن القيمة غير متاحة في بيانات التقرير.</p>';
}
