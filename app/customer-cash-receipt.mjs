import {escapeHtml as e,invoiceDate} from './document-format.mjs';
import {money,receiptNumber} from './supplier-utils.mjs';
import {phoneContactDocument} from './phone-contact-utils.mjs';
const known=value=>value!==null&&value!==undefined&&value!==''&&Number.isFinite(Number(value));
const amount=value=>known(value)?money(value):'غير متوفر';
const balanceLine=(label,value,kind)=>{const text=amount(value);return '<tr class="receiptBalance '+kind+'"><th scope="row">'+label+'</th><td class="receiptBalanceValue'+(text.length>12?' receiptLongAmount':'')+'"><bdi dir="ltr">'+text+'</bdi></td><td class="receiptCurrency">دينار عراقي</td></tr>';};
export function customerCashReceipt(row){
 const number=receiptNumber(row),invoice=row.invoice,wholesale=row.ledgerType==='wholesale';
 const body='<section class="customerReceiptDocument">'+
 '<header class="receiptVoucherHeader"><div class="receiptVoucherTitle"><small>شركة عزم الشرق</small><h2>وصل قبض</h2><span>'+ (wholesale?'تسديد حساب عميل · جملة':'تسديد حساب منظومات')+'</span></div><div class="receiptVoucherMeta"><div class="receiptVoucherNumber"><span>رقم الوصل</span><bdi dir="ltr">'+e(number)+'</bdi></div><time class="receiptVoucherDate" dir="ltr">'+invoiceDate(row.date)+'</time><small>'+ (row.draft?'مسودة — غير محفوظة':'وصل محفوظ')+'</small></div></header>'+
 '<div class="receiptVoucherGrid"><div class="receiptVoucherCustomer"><span>استلمت من السيد</span><strong>'+e(row.party||'—')+'</strong></div><table class="receiptBalanceTable" aria-label="الحساب السابق والتسديد والباقي"><colgroup><col style="width:32%"><col style="width:43%"><col style="width:25%"></colgroup><tbody>'+balanceLine('الحساب السابق',row.oldBalance,'receiptPrevious')+balanceLine('المبلغ المسدّد',Math.abs(Number(row.total||0)),'receiptPaid')+balanceLine('المبلغ الباقي',row.remaining,'receiptRemaining')+'</tbody></table></div>'+
 '<div class="receiptVoucherNotes notes" data-pdf-end><span>الملاحظات</span><p>'+e(row.notes||'')+'</p></div>'+
 '<div class="receiptVoucherSignature"><span>التوقيع</span><i aria-hidden="true"></i></div>'+
 '<div class="receiptVoucherContact"><span>المستلم: <b>'+e(row.cashOwnerName||row.creatorName||'—')+'</b></span>'+(row.creatorPhone?'<span>هاتف صاحب الوصل: '+phoneContactDocument(row.creatorPhone)+'</span>':'')+'</div>'+
 '<p class="receiptVoucherAllocation">التخصيص: '+(invoice?'المنظومة #'+e(receiptNumber(invoice)):'الحساب العام / الرصيد الافتتاحي')+(invoice?' · رصيد المنظومة قبل الحركة: '+amount(row.invoiceBefore)+' د.ع · رصيد المنظومة بعد الحركة: '+amount(row.invoiceAfter)+' د.ع':'')+'</p>'+
 (invoice?.items?.length?'<section class="receiptVoucherAppendix"><h3>مواد المنظومة المرتبطة</h3><table class="receiptRelatedItems" data-pdf-paginate><thead><tr><th>المادة</th><th>العدد</th></tr></thead><tbody>'+invoice.items.map(i=>'<tr><td>'+e(i.name)+'<small>'+e([i.brand,i.category].filter(Boolean).join(' · '))+'</small></td><td class="documentNumber">'+money(i.qty)+'</td></tr>').join('')+'</tbody></table></section>':'')+'</section>';
 return {title:'وصل قبض',body,total:money(Math.abs(Number(row.total||0)))+' د.ع',subtitle:(wholesale?'تسديد جملة':'تسديد منظومات')+' · '+(row.draft?'مسودة — غير محفوظة':'وصل محفوظ #'+number)};
}
