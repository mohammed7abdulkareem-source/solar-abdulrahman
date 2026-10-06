import {accountEffect} from './reconciliation-utils.mjs';
import {supplierEffect,money,receiptNumber} from './supplier-utils.mjs';
import {escapeHtml as e,warehouseDate} from './warehouse-utils.mjs';
import {cashOwner} from './access-utils.mjs';

const rounded=n=>Math.round((n+Number.EPSILON)*100)/100;
const table=(headers,rows,widths=[])=>'<table data-pdf-paginate>'+(widths.length?'<colgroup>'+widths.map(w=>'<col style="width:'+w+'%">').join('')+'</colgroup>':'')+'<thead><tr>'+headers.map(h=>'<th>'+e(h)+'</th>').join('')+'</tr></thead><tbody>'+(rows.length?rows.map(cells=>'<tr>'+cells.map(c=>'<td>'+c+'</td>').join('')+'</tr>').join(''):'<tr><td colspan="'+headers.length+'">لا توجد بيانات</td></tr>')+'</tbody></table>';
export function capitalAccounts(tx,parties=[],supplier=false){
 const kinds=supplier?['purchase','supplier_payment']:['sale','system','customer_payment','system_payment'];
 const accounts=new Map();
 for(const t of tx.filter(t=>kinds.includes(t.kind))){
  const value=supplier?supplierEffect(t):accountEffect(t);if(!value)continue;
  const named=parties.filter(p=>p.name===t.party);
  const party=t.partyId?parties.find(p=>String(p.id)===String(t.partyId)):named.length===1?named[0]:null;
  const key=t.partyId?'id:'+t.partyId:party?'id:'+party.id:'name:'+(t.party||'غير محدد');
  const account=accounts.get(key)||{name:party?.name||t.party||'غير محدد',phone:party?.phone||'',balance:0};
  account.balance=rounded(account.balance+value);accounts.set(key,account);
 }
 const rows=[...accounts.values()].filter(r=>r.balance!==0).sort((a,b)=>b.balance-a.balance||a.name.localeCompare(b.name,'ar'));
 const net=rounded(rows.reduce((sum,r)=>sum+r.balance,0));
 return {rows,net,total:Math.max(0,net)};
}
export function capitalStockReport(products){
 const rows=products.filter(p=>Number(p.qty)>0),total=rows.reduce((sum,p)=>sum+Number(p.qty)*Number(p.cost||0),0);
 return {title:'كشف المخزون بالكلفة',total,body:table(['ت','الكود','المادة / البراند / الصنف','العدد','الكلفة د.ع','المجموع د.ع'],rows.map((p,i)=>[i+1,e(p.code),'<strong>'+e(p.name)+'</strong><br>'+e([p.brand,p.category].filter(Boolean).join(' • ')),money(p.qty),money(p.cost),money(Number(p.qty)*Number(p.cost||0))]),[5,10,30,10,21,24])+'<div data-pdf-end class="documentCounts">عدد الأصناف: '+rows.length+' • مجموع الكميات: '+money(rows.reduce((sum,p)=>sum+Number(p.qty),0))+'</div>'};
}
export function capitalDebtReport(accounts,supplier=false){
 const title=supplier?'كشف ديون الموردين علينا':'كشف ديون العملاء لنا';
 return {title,total:accounts.total,body:table(['ت',supplier?'المورد':'العميل','الهاتف',supplier?'علينا د.ع':'لنا د.ع',supplier?'لنا د.ع':'للعميل د.ع'],accounts.rows.map((r,i)=>[i+1,e(r.name),e(r.phone),money(Math.max(0,r.balance)),money(Math.max(0,-r.balance))]),[5,32,17,23,23])+'<div data-pdf-end class="notes">عدد الحسابات: '+accounts.rows.length+'<br>صافي الأرصدة: '+money(accounts.net)+' د.ع<br>المبلغ في رأس المال هو صافي الأرصدة الموجب بعد طرح الأرصدة الدائنة. الفواتير النقدية المسددة لا تدخل ضمن الديون.</div>'};
}
const cashLabels={sale:'بيع نقدي',system:'بيع منظومة',purchase:'شراء نقدي',customer_payment:'تسديد عميل',system_payment:'تسديد منظومة',supplier_payment:'تسديد مورد',cash_income:'إيداع بالصندوق',cash_expense:'مصروف من الصندوق',capital:'رأس مال',profit_distribution:'توزيع أرباح',installation_payout:'دفع مصاريف تنصيب',installation_refund:'استرجاع فرق التنصيب',handover_expense:'مصروف قبل تسليم القاصة',transfer_out:'إرسال أموال',transfer_in:'استلام أموال',transfer_refund:'إرجاع تحويل',transfer_transit:'أموال قيد التسليم'};
// Receives the same cash-owner-scoped rows used by the capital tile.
export function capitalCashReport(rows,staff=[]){
 let total=0,incoming=0,outgoing=0;
 const data=[...rows].sort((a,b)=>new Date(a.date)-new Date(b.date)||String(a.id).localeCompare(String(b.id))).map((t,i)=>{
  const delta=t.cashDelta!==undefined?Number(t.cashDelta):(['purchase','supplier_payment','cash_expense','profit_distribution'].includes(t.kind)?-1:1)*Number(t.total||0);
  total+=delta;incoming+=Math.max(0,delta);outgoing+=Math.max(0,-delta);
  const owner=staff.find(u=>u.id===cashOwner(t));
  return [i+1,e(warehouseDate(t.date)),e(cashLabels[t.kind]||t.kind)+'<br>'+e(t.party||t.notes||'')+(owner?'<br>'+e(owner.display_name||owner.username||''):''),t.systemCash?'—':e(receiptNumber(t)),money(Math.max(0,delta)),money(Math.max(0,-delta)),money(total)];
 });
 return {title:'كشف الصندوق',total,body:table(['ت','التاريخ','البيان / القاصة','الوصل','داخل د.ع','خارج د.ع','الرصيد د.ع'],data,[5,12,25,10,16,16,16])+'<div data-pdf-end class="documentCounts">عدد الحركات: '+data.length+' • الداخل: '+money(incoming)+' د.ع • الخارج: '+money(outgoing)+' د.ع</div>'};
}
