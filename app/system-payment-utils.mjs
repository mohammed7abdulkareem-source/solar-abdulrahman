import {escapeHtml as e,money,receiptNumber} from './supplier-utils.mjs';
export const paymentReason=mode=>({payment:'تسديد من الزبون',charge_extra_expense:'مصروف إضافي',charge_old_balance:'حساب قديم',charge_other:'إضافة أخرى'}[mode]||'إضافة على الحساب');
export function systemPaymentDocument(row){
 const charge=Number(row.total)<0,wholesale=row.ledgerType==='wholesale',title=charge?(wholesale?'وصل إضافة على حساب جملة':'وصل إضافة على حساب منظومات'):(wholesale?'وصل تسديد جملة':'وصل تسديد منظومات'),invoice=row.invoice;
 const body='<div class="meta"><div><b>العميل:</b> '+e(row.party)+'</div><div><b>رقم الوصل:</b> '+e(receiptNumber(row))+'</div><div><b>التاريخ:</b> '+e(new Date(row.date).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'}))+'</div><div><b>نوع الحركة:</b> '+e(paymentReason(row.mode))+'</div><div><b>التخصيص:</b> '+(invoice?'المنظومة #'+e(receiptNumber(invoice)):'الحساب العام / الرصيد الافتتاحي')+'</div><div><b>المستلم:</b> '+e(row.cashOwnerName||'')+'</div>'+(row.creatorPhone?'<div><b>هاتف صاحب الوصل:</b> <bdi dir="ltr">'+e(row.creatorPhone)+'</bdi></div>':'')+'</div>'+
 '<table><thead><tr><th>رصيد الحساب السابق د.ع</th><th>'+ (charge?'الإضافة':'التسديد')+' د.ع</th><th>رصيد الحساب الجديد د.ع</th></tr></thead><tbody><tr><td>'+money(row.oldBalance)+'</td><td>'+money(Math.abs(row.total))+'</td><td>'+money(row.remaining)+'</td></tr></tbody></table>'+
 (invoice?'<div class="meta"><div>رصيد المنظومة قبل الحركة: '+money(row.invoiceBefore)+' د.ع</div><div>رصيد المنظومة بعد الحركة: '+money(row.invoiceAfter)+' د.ع</div></div>':'')+
 (invoice?.items?.length?'<table data-pdf-paginate><thead><tr><th>مواد المنظومة</th><th>العدد</th></tr></thead><tbody>'+invoice.items.map(i=>'<tr><td>'+e(i.name)+'<br>'+e([i.brand,i.category].filter(Boolean).join(' · '))+'</td><td>'+money(i.qty)+'</td></tr>').join('')+'</tbody></table>':'')+
 (charge?'<p class="notes">حركة غير نقدية؛ تزيد حساب العميل دون إضافة مبلغ إلى القاصة.</p>':'<p class="notes">المبلغ مقبوض بالدينار ومضاف إلى قاصة المستلم.</p>')+
 (row.notes?'<div class="notes">'+e(row.notes)+'</div>':'');
 return {title,body,total:money(Math.abs(row.total))+' د.ع',subtitle:row.draft?'مسودة — غير محفوظة':'وصل محفوظ #'+receiptNumber(row)};
}
