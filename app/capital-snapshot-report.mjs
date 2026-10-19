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

 return {title:s.scope==='company'?'تقرير رأس المال':'ملخص أرصدة المستخدم',total:s.net,body:
  '<p>وقت الاحتساب: '+e(new Date(s.asOf).toLocaleString('en-GB',{timeZone:'Asia/Baghdad'}))+' · '+(s.scope==='company'?'جميع حسابات الشركة':'حركات المستخدم وقاصته والمخازن المسموحة له')+'</p>'+
  '<table><thead><tr><th>البند</th><th>القيمة الدفترية د.ع</th></tr></thead><tbody>'+capitalLines(s).map(([label,value])=>'<tr><td>'+e(label)+'</td><td dir="ltr">'+money(value)+'</td></tr>').join('')+'</tbody></table>'+
  '<p>جميع القيم بالدينار العراقي، وأرصدة الدولار محسوبة بكلفتها الدفترية المثبتة.</p>'};
}
