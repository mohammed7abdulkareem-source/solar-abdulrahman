import {phoneContactDocument} from './phone-contact-utils.mjs';
import {formatMoney as money,currencyUnit as unit} from './money-format.mjs';
import {escapeHtml as e} from './supplier-utils.mjs';
export const cashDate=value=>new Date(value).toLocaleString('en-GB',{timeZone:'Asia/Baghdad'});
export function cashLedgerRows(rows=[]){
 const seen=new Set();
 return rows.map(row=>{const reset=row.reconciliation?.mode==='zero',key=row.reconciliation?.id+':'+row.owner_id;
  const showReset=reset&&!seen.has(key);if(reset)seen.add(key);return {...row,showReset};});
}
export const resetTitle=r=>'تصفير قاصة '+(r.ownerName||r.reconciliation?.ownerName||'')+(r.reconciliation?.currency==='IQD'?' · الدينار':r.reconciliation?.currency==='USD'?' · الدولار':' · الدينار والدولار');
export const transferStatus=value=>({pending:'بانتظار الاستلام',accepted:'تم الاستلام',rejected:'مرفوض',cancelled:'ملغى'}[value]||'—');
export const paymentMode=value=>({cash:'نقدي',credit:'آجل',partial:'جزئي',opening_balance:'رصيد افتتاحي',account_reconciliation:'تسوية حساب'}[value]||'—');
export function cashMovementBody(r,label){
 const cur=r.currency,u=unit(cur);
 return '<div class="meta"><div>القاصة: '+e(r.ownerName)+'</div><div>الحركة: '+e(label)+'</div><div>التاريخ: '+e(cashDate(r.date))+'</div><div>رقم الوصل: '+e(r.receiptNo||'—')+'</div>'+(r.actorName?'<div>المسجل: '+e(r.actorName)+'</div>':'')+(r.actorPhone?'<div>هاتف المسجل: '+phoneContactDocument(r.actorPhone)+'</div>':'')+(r.party?'<div>الجهة: '+e(r.party)+'</div>':'')+'</div><table><thead><tr><th>الرصيد السابق للقاصة</th><th>مبلغ الحركة</th><th>رصيد القاصة بعد الحركة</th></tr></thead><tbody><tr><td>'+money(r.before,cur)+' '+u+'</td><td>'+(r.delta>0?'+':r.delta<0?'−':'')+money(r.amount,cur)+' '+u+'</td><td>'+money(r.after,cur)+' '+u+'</td></tr></tbody></table>'+
 (r.document?'<p>'+e(r.document.deleted?'الوصل المحذوف: #':'الوصل المرتبط: #')+e(r.document.receiptNo||'—')+(r.document.warehouse?' · المخزن: '+e(r.document.warehouse):'')+'</p>':'')+
 (r.transfer?'<p>تسليم القاصة من '+e(r.transfer.sender)+' إلى '+e(r.transfer.recipient)+' · '+e(transferStatus(r.transfer.status))+'</p><p>مبلغ التسليم: '+money(r.transfer.amount)+' د.ع · المصروف: '+money(r.transfer.expense)+' د.ع</p><p>'+e(r.transfer.note||'')+'</p>':'')+
 (r.exchange?'<p>'+e(r.exchange.mode==='buy_usd'?'شراء دولار':'بيع دولار')+': '+money(r.exchange.amount,'USD')+' $ · الصرف: '+money(r.exchange.rate)+' د.ع لكل دولار</p>':'')+
 (r.reconciliation?'<h3>'+e(r.reconciliation.mode==='zero'?'تصفير القاصة':'تعديل رصيد القاصة')+'</h3><table><thead><tr><th>العملة</th><th>قبل التسوية</th><th>بعد التسوية</th></tr></thead><tbody>'+['IQD','USD'].map(c=>'<tr><td>'+c+'</td><td>'+money(r.reconciliation['before'+c],c)+' '+unit(c)+'</td><td>'+money(r.reconciliation['after'+c],c)+' '+unit(c)+'</td></tr>').join('')+'</tbody></table>':'')+
 ((r.items||[]).length?'<table data-pdf-paginate><thead><tr><th>ت</th><th>المادة</th><th>الكمية</th><th>سعر الوحدة د.ع</th><th>المجموع د.ع</th></tr></thead><tbody>'+r.items.map((i,n)=>'<tr><td>'+(n+1)+'</td><td>'+e(i.name)+'</td><td>'+money(i.qty)+'</td><td>'+money(i.price)+'</td><td>'+money(i.total)+'</td></tr>').join('')+'</tbody></table>':'')+
 '<p>البيان: '+e(r.note||'لا يوجد بيان إضافي')+'</p>';
}
