import {escapeHtml as e} from './warehouse-utils.mjs';
import {money} from './supplier-utils.mjs';

export function capitalLines(s){
 return [
  ['المخزون بالكلفة',s.stock.value],['الصندوق بالدينار',s.cash.iqd],['قاصة الدولار بالقيمة الدفترية',s.cash.usdBook],
  ['ديون العملاء لنا',s.customers.receivable],['سلفنا لدى الموردين',s.suppliers.prepayments],['إجمالي الموجودات',s.assets],
  ['ديون الموردين علينا',s.suppliers.payable],['أرصدة العملاء الدائنة',s.customers.advances],['إجمالي المطلوبات',s.liabilities],
  ['صافي قيمة النشاط',s.net]
 ];
}
export function capitalSnapshotReport(s){
 const scope=s.scope==='company'?'جميع حسابات الشركة':'حركات المستخدم وقاصته والمخازن المسموحة له';
 const metric=(label,value)=>'<div class="reportMetric"><span>'+e(label)+'</span><strong>'+money(value)+' د.ع</strong></div>';
 return {title:s.scope==='company'?'تقرير رأس المال':'ملخص أرصدة المستخدم',total:s.net,body:
  '<div class="meta"><div>وقت الاحتساب: '+e(new Date(s.asOf).toLocaleString('en-GB',{timeZone:'Asia/Baghdad'}))+' · توقيت بغداد</div><div>نطاق التقرير: '+scope+'</div><div>عملة القيم الدفترية: الدينار العراقي · IQD</div><div>الأرصدة حتى وقت الاحتساب</div></div>'+
  '<div class="reportSummary">'+metric('إجمالي الموجودات',s.assets)+metric('إجمالي المطلوبات',s.liabilities)+metric('الصافي · الموجودات − المطلوبات',s.net)+'</div>'+
  '<h3 class="reportSectionTitle">تفاصيل الموجودات والمطلوبات</h3><table data-pdf-paginate><thead><tr><th>البند</th><th>القيمة الدفترية · د.ع</th></tr></thead><tbody>'+capitalLines(s).map(([label,value])=>'<tr><td>'+e(label)+'</td><td dir="ltr">'+money(value)+'</td></tr>').join('')+'</tbody></table>'+
  '<p>جميع القيم في الملخص والجدول بالدينار العراقي. تدخل أرصدة الدولار في الموجودات والمطلوبات بقيمتها الدفترية المثبتة بالدينار.</p>'+
  (s.cash.usd!=null?'<p>رصيد قاصة الدولار الأصلي: <b>'+money(s.cash.usd)+' USD</b> · قيمته الدفترية المدرجة أعلاه: <b>'+money(s.cash.usdBook)+' د.ع</b>.</p>':'')};
}
