import {money,dateKey,escapeHtml as e} from './supplier-utils.mjs';

export function profitBalanceReport({balance,ownerName,from,to,rows,expenses,fx,externalProfit}){
 if(!balance)return '';
 return '<div class="meta"><div>المستخدم: '+e(ownerName)+'</div><div>فترة العمليات: '+e(from||'البداية')+' — '+e(to||'اليوم')+'</div></div>'+
  '<div class="notes"><b>الأرباح المتبقية بعد التسوية: '+money(balance.remaining)+' د.ع</b><p>الرصيد الحالي لجميع الفترات، بعد حصص المستخدمين وبقية الأرباح المضافة للموردين وتوزيعات الإدارة. مستقل عن رصيد القاصة وعن فلاتر الفترة والمبيعات.</p></div>'+
  '<p>ربح الفترة قبل التسويات: '+money(balance.period.earned)+' د.ع · المسوّى من أرباح الفترة: '+money(balance.period.settled)+' د.ع · غير المسوّى من أرباح الفترة: '+money(balance.period.available)+' د.ع.</p>'+
  '<table data-pdf-paginate><thead><tr><th>التاريخ</th><th>العملية / العميل</th><th>المبيعات د.ع</th><th>الكلفة د.ع</th><th>الربح قبل التسوية</th><th>المسوّى</th><th>غير المسوّى</th></tr></thead><tbody>'+rows.map(t=>'<tr><td>'+e(dateKey(t.date))+'</td><td>'+e(t.kind==='system'?'منظومة':'جملة')+'<br>'+e(t.party||'نقدي')+'</td><td>'+money(t.sales)+'</td><td>'+money(t.cost)+'</td><td>'+money(t.earned)+'</td><td>'+money(t.settled)+'</td><td>'+money(t.available)+'</td></tr>').join('')+'</tbody></table>'+
  '<p>المصاريف التشغيلية للفترة: '+money(expenses)+' د.ع · فرق الصرف المحقق: '+money(fx)+' د.ع · الأرباح الخارجية: '+money(externalProfit)+' د.ع.</p><p>تبقى أرباح المبيعات التاريخية وكلفتها المثبتة محفوظة. المصاريف التشغيلية تستثني حصص تسوية الأرباح حتى لا تُطرح مرتين.</p>';
}
