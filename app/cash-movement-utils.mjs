import {phoneContactDocument} from './phone-contact-utils.mjs';
import {formatMoney as money,currencyUnit as unit} from './money-format.mjs';
import {escapeHtml as e} from './supplier-utils.mjs';
import {cashTransferDecisionLabel,cashTransferFacts} from './cash-ledger-display.mjs';
export const cashDate=value=>new Date(value).toLocaleString('en-GB',{timeZone:'Asia/Baghdad'});
export function cashLedgerRows(rows=[]){
 const seen=new Set();
 return rows.map(row=>{const reset=row.reconciliation?.mode==='zero',key=row.reconciliation?.id+':'+row.owner_id;
  const showReset=reset&&!seen.has(key);if(reset)seen.add(key);return {...row,showReset};});
}
export const resetTitle=r=>'تصفير قاصة '+(r.ownerName||r.reconciliation?.ownerName||'')+(r.reconciliation?.currency==='IQD'?' · الدينار':r.reconciliation?.currency==='USD'?' · الدولار':' · الدينار والدولار');
export const transferStatus=value=>({pending:'بانتظار الاستلام',accepted:'تم الاستلام',rejected:'مرفوض',cancelled:'ملغى'}[value]||'—');
export const paymentMode=value=>({cash:'نقدي',credit:'آجل',partial:'جزئي',opening_balance:'رصيد افتتاحي',account_reconciliation:'تسوية حساب'}[value]||'—');
export function cashTransferDocumentLines(kind,transfer){
 if(!transfer)return cashTransferFacts(kind,null).map(({label,value})=>label+' '+value);
 const originalRoute=['transfer_refund','transfer_transit','handover_expense'].includes(kind);
 const parts=[(originalRoute?'طلب التسليم الأصلي ':'')+'من '+(transfer.sender||'غير مسجّل')+' إلى '+(transfer.recipient||'غير مسجّل')];
 if(transfer.status)parts.push(transferStatus(transfer.status));
 if(transfer.decidedBy)parts.push(cashTransferDecisionLabel(kind,transfer.status)+': '+transfer.decidedBy);
 if(transfer.amount!=null){
  const currency=transfer.currency||'IQD';
  parts.push('مبلغ التسليم: '+money(transfer.amount,currency)+' '+unit(currency));
 }
 if(Number(transfer.expense)>0)parts.push('مصروف التسليم: '+money(transfer.expense)+' د.ع');
 return parts;
}
export function cashMovementBody(r,label){
 const cur=r.currency,u=unit(cur);
 const balance=value=>value==null?'—':money(value,cur)+' '+u;
 const transit=r.ownerId===null;
 const balances='<table><thead><tr><th>'+(transit?'الرصيد السابق قيد التسليم':'الرصيد السابق للقاصة')+'</th><th>مبلغ الحركة</th><th>'+(transit?'رصيد قيد التسليم بعد الحركة':'رصيد القاصة بعد الحركة')+'</th></tr></thead><tbody><tr><td>'+balance(r.before)+'</td><td>'+(r.delta>0?'+':r.delta<0?'−':'')+money(r.amount,cur)+' '+u+'</td><td><strong>'+balance(r.after)+'</strong></td></tr></tbody></table>';
 const header='<div class="meta"><div>القاصة: '+e(r.ownerName)+'</div><div>الحركة: '+e(r.receiptRestricted?'أثر حسابي':label)+'</div><div>التاريخ: '+e(cashDate(r.date))+'</div>';
 if(r.receiptRestricted)return header+'</div>'+balances;
 const transferLines=cashTransferDocumentLines(r.kind,r.transfer);
 return header+'<div>رقم الوصل: '+e(r.receiptNo||'—')+'</div>'+(r.actorName&&r.actorName!==r.transfer?.decidedBy?'<div>المسجل: '+e(r.actorName)+'</div>':'')+(r.actorPhone?'<div>هاتف المسجل: '+phoneContactDocument(r.actorPhone)+'</div>':'')+(r.party?'<div>الجهة: '+e(r.party)+'</div>':'')+'</div>'+balances+
 (r.document?'<p>'+e(r.document.deleted?'الوصل المحذوف: #':'الوصل المرتبط: #')+e(r.document.receiptNo||'—')+(r.document.warehouse?' · المخزن: '+e(r.document.warehouse):'')+'</p>':'')+
 (transferLines.length?'<section><h3>تسليم القاصة</h3>'+transferLines.map(line=>'<p>'+e(line)+'</p>').join('')+(r.transfer?.note&&r.transfer.note!==r.note?'<p>'+e(r.transfer.note)+'</p>':'')+'</section>':'')+
 (r.exchange?'<p>'+e(r.exchange.mode==='buy_usd'?'شراء دولار':'بيع دولار')+': '+money(r.exchange.amount,'USD')+' $ · الصرف: '+money(r.exchange.rate)+' د.ع لكل دولار</p>':'')+
 (r.reconciliation?'<h3>'+e(r.reconciliation.mode==='zero'?'تصفير القاصة':'تعديل رصيد القاصة')+'</h3><table><thead><tr><th>العملة</th><th>قبل التسوية</th><th>بعد التسوية</th></tr></thead><tbody>'+['IQD','USD'].map(c=>'<tr><td>'+c+'</td><td>'+money(r.reconciliation['before'+c],c)+' '+unit(c)+'</td><td>'+money(r.reconciliation['after'+c],c)+' '+unit(c)+'</td></tr>').join('')+'</tbody></table>':'')+
 ((r.items||[]).length?'<table data-pdf-paginate><thead><tr><th>ت</th><th>المادة</th><th>الكمية</th><th>سعر الوحدة د.ع</th><th>المجموع د.ع</th></tr></thead><tbody>'+r.items.map((i,n)=>'<tr><td>'+(n+1)+'</td><td>'+e(i.name)+'</td><td>'+money(i.qty)+'</td><td>'+money(i.price)+'</td><td>'+money(i.total)+'</td></tr>').join('')+'</tbody></table>':'')+
 '<p>البيان: '+e(r.note||'لا يوجد بيان إضافي')+'</p>';
}
