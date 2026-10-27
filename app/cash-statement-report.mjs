import {escapeHtml as e} from './supplier-utils.mjs';
import {formatMoney as money,currencyUnit as unit} from './money-format.mjs';
import {cashKind} from './cash-utils.mjs';
import {cashDate,paymentMode,transferStatus} from './cash-movement-utils.mjs';

export const statementDate=value=>value?value.split('-').reverse().join('/'):'—';
export function cashStatementDetails(r){
 const parts=[];
 if(r.party)parts.push(r.party);
 if(r.receipt_no!=null)parts.push('وصل #'+r.receipt_no);
 if(r.job_receipt!=null&&r.job_receipt!==r.receipt_no)parts.push('منظومة #'+r.job_receipt);
 if(r.warehouse_name)parts.push('المخزن: '+r.warehouse_name);
 if(r.payment_mode)parts.push('طريقة الدفع: '+paymentMode(r.payment_mode));
 if(r.actor_name)parts.push('المسجل: '+r.actor_name);
 if(r.sender_name||r.recipient_name)parts.push('من '+(r.sender_name||'—')+' إلى '+(r.recipient_name||'—')+' · '+transferStatus(r.transfer_status));
 if(r.transfer_amount!=null)parts.push('مبلغ التسليم: '+money(r.transfer_amount)+' د.ع · المصروف: '+money(r.transfer_expense||0)+' د.ع');
 if(r.source_currency==='USD')parts.push('أصل الحركة: '+money(r.source_amount,'USD')+' $ · الصرف المثبت: '+money(r.rate)+' د.ع');
 return parts;
}
export function cashStatementNotes(r){
 return [...new Set([r.note,r.transfer_note,r.expense_note,r.reconciliation?.note].filter(Boolean))].join('\n');
}
// Keep long notes complete without making a single PDF row taller than a page.
export const cashStatementNoteParts=r=>{const chars=Array.from(cashStatementNotes(r)||'—');return Array.from({length:Math.ceil(chars.length/260)},(_,i)=>chars.slice(i*260,(i+1)*260).join(''));};
export const cashStatementKind=r=>r.reconciliation?.mode==='zero'?'تصفير القاصة':cashKind(r.kind);
export function cashStatementTable(g){
 const u=unit(g.currency),amount=v=>e(money(v,g.currency)),label=v=>'<bdi>'+amount(v)+'</bdi>';
 return '<table class="cashStatementTable" data-pdf-paginate><colgroup><col style="width:16%"><col style="width:29%"><col style="width:19%"><col style="width:12%"><col style="width:12%"><col style="width:12%"></colgroup><thead><tr><th colspan="6" class="cashStatementGroup">قاصة '+e(g.ownerName)+' · '+e(u)+'</th></tr><tr><th>التاريخ</th><th>نوع الحركة والتفاصيل</th><th>الملاحظات</th><th>وارد</th><th>صادر</th><th>الرصيد</th></tr></thead><tbody><tr class="cashStatementOpening"><td colspan="5">الرصيد السابق قبل بداية الفترة</td><td>'+label(g.opening)+'</td></tr>'+(g.rows||[]).map(r=>(r.reconciliation?.mode==='zero'?'<tr class="cashStatementReset"><td colspan="6">تصفير القاصة · '+e(cashDate(r.created_at))+' · وصل #'+e(r.reconciliation.receiptNo||r.receipt_no||'—')+'</td></tr>':'')+'<tr data-movement-id="'+e(r.id)+'"><td>'+e(cashDate(r.created_at))+'</td><td><strong>'+e(cashStatementKind(r))+'</strong>'+cashStatementDetails(r).map(d=>'<div>'+e(d)+'</div>').join('')+'</td><td class="cashStatementNotes">'+e(cashStatementNoteParts(r)[0])+'</td><td class="cashStatementIn">'+label(Math.max(0,Number(r.delta)))+'</td><td class="cashStatementOut">'+label(Math.max(0,-Number(r.delta)))+'</td><td class="'+(Number(r.balance)<0?'cashStatementOut':'')+'">'+label(r.balance)+'</td></tr>'+cashStatementNoteParts(r).slice(1).map(part=>'<tr data-note-for="'+e(r.id)+'"><td>تكملة الملاحظات</td><td colspan="5" class="cashStatementNotes">'+e(part)+'</td></tr>').join('')).join('')+(!(g.rows||[]).length?'<tr><td colspan="6">لا توجد حركات خلال الفترة</td></tr>':'')+'<tr class="cashStatementClosing"><td colspan="3">المجاميع ورصيد نهاية الفترة · '+e(u)+'</td><td class="cashStatementIn">'+label(g.incoming)+'</td><td class="cashStatementOut">'+label(g.outgoing)+'</td><td>'+label(g.closing)+'</td></tr></tbody></table>';
}
export function cashStatementDocument(data,a4){
 const title='كشف صندوق حسب الفترة',range=statementDate(data.from)+' — '+statementDate(data.to);
 const body='<section class="cashStatementDocument"><div class="cashStatementHeading"><h2>'+e(data.ownerName)+'</h2><p>للفترة من '+e(statementDate(data.from))+' إلى '+e(statementDate(data.to))+'</p><small>وقت الاحتساب: '+e(cashDate(data.asOf))+' · '+e(data.count)+' حركة</small></div>'+data.ledgers.map(cashStatementTable).join('')+'<p class="cashStatementFootnote">كل قاصة وعملة مستقلة. الرصيد السابق يسبق بداية الفترة، ورصيد النهاية يشمل آخر يوم. يعكس الكشف الحركات الحالية بعد التعديل والحذف وقت الاحتساب.</p></section>';
 return a4(title,body,'',e(range));
}
