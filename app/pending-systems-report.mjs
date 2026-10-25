import {escapeHtml as e,invoiceDate} from './document-format.mjs';
import {formatMoney as money} from './money-format.mjs';
import {statusLabel} from './sales-document.mjs';
export function pendingSystemsDocument(data){
 const s=data.summary,rows=data.rows||[];
 const body='<div class="meta"><div>منظومات غير مغلقة: '+s.count+'</div><div>المقبوض المرتبط: '+money(s.collected)+' د.ع</div><div>الربح غير النهائي: '+money(s.provisionalProfit)+' د.ع</div><div>مصاريف تنصيب مدفوعة: '+money(s.paidExpenses)+' د.ع</div></div><table data-pdf-paginate><thead><tr><th>الوصل</th><th>الزبون / المسؤول</th><th>قيمة المنظومة</th><th>المقبوض المرتبط</th><th>مصاريف معتمدة</th><th>ربح غير نهائي</th></tr></thead><tbody>'+rows.map(r=>'<tr><td>#'+e(r.receiptNo)+'<br><small>'+invoiceDate(r.date)+'</small></td><td>'+e(r.customer)+'<br><small>'+e(r.creatorName)+' · '+e(statusLabel[r.status]||'غير مغلق')+'</small></td><td>'+money(r.total)+'</td><td>'+money(r.collected)+'</td><td>'+money(r.approvedExpenses)+'</td><td>'+money(r.provisionalProfit)+'</td></tr>').join('')+'</tbody></table><p>الربح قبل الإغلاق يعتمد الكلفة والمصاريف المعتمدة المحفوظة، وقد يتغير عند مراجعة المصاريف. المقبوضات خاصة بهذه الوصولات وتشمل ما سُلّم للإدارة.</p>'+
 ((data.unallocated||[]).length?'<h3>تسديدات غير موزعة لعملاء لديهم منظومات مفتوحة</h3><p>تُعرض مستقلة حتى تُربط بوصولاتها، ولا تُنسب إلى منظومة بالتخمين.</p><table data-pdf-paginate><thead><tr><th>العميل</th><th>عدد التسديدات</th><th>المبلغ د.ع</th></tr></thead><tbody>'+data.unallocated.map(r=>'<tr><td>'+e(r.customer)+'</td><td>'+r.receiptCount+'</td><td>'+money(r.amount)+'</td></tr>').join('')+'</tbody></table>':'');
 return {title:'المنظومات غير المغلقة',body,total:'',subtitle:(data.from||'البداية')+' — '+(data.to||'كل الفترات')};
}
