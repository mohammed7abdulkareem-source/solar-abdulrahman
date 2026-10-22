import {phoneContactDocument} from './phone-contact-utils.mjs';
import {accountEffect,accountLabel} from './reconciliation-utils.mjs';
import {supplierLabel,supplierIsCharge,escapeHtml as e,dateKey,receiptNumber} from './supplier-utils.mjs';
import {formatMoney as money,currencyUnit as unit} from './money-format.mjs';
export const partyInitials=name=>String(name||'').trim().split(/\s+/).slice(0,2).map(w=>Array.from(w)[0]).join('').toUpperCase();
export function customerAccount(record){
 return {...record,type:'customer',currency:'IQD',customerType:record.customerType||record.customer_type,ownerName:record.ownerName||record.owner_name,
  rows:(record.rows||[]).map(r=>({...r,date:r.date,effect:accountEffect(r),amount:Math.abs(Number(r.total)),label:accountLabel(r),
   category:r.mode==='opening_balance'?'opening':r.mode==='account_reconciliation'?'adjustment':['sale','system'].includes(r.kind)?'invoices':Number(r.total)>0?'payments':'charges',original:r}))};
}
export function supplierAccount(data,name,transactions=[],revision=data.revision){
 const entries=(data.rows||[]).filter(r=>r.revision===revision),currency=entries[0]?.currency||data.currency;
 const rows=entries.map(r=>{
  const t=r.transaction,original=t?{...transactions.find(x=>String(x.id)===String(t.id)),id:t.id,kind:t.kind,voided:!!t.supplier_payment_voided_at,party:t.party_name,receiptNo:t.receipt_no,notes:t.notes,cash:t.cash,total:Number(t.total),mode:t.payment_mode,sourceCurrency:t.source_currency,sourceSubtotal:t.source_subtotal,marketRate:t.market_rate,exchangeRate:Number(t.exchange_rate),accountCurrency:r.currency,accountAmount:t.account_amount,cashCurrency:t.cash_currency,cashAmount:t.cash_amount,date:t.created_at,expenses:Number(t.expenses),fxPricing:t.fx_pricing,pricingRevision:t.pricing_revision,items:(r.items||[]).map(i=>({id:i.product_id,name:i.product_name,qty:Number(i.qty),price:Number(i.price),sourcePrice:i.source_price,cost:Number(i.cost),brand:i.brand_name,category:i.category}))}:null;
  const category=r.correction_for?'adjustment':!original?((String(r.entry_type).includes('opening')||String(r.note||'').startsWith('تحويل رصيد باتفاق جديد'))?'opening':'adjustment'):original.kind==='purchase'?'invoices':supplierIsCharge(original)?'charges':'payments';
  return {id:r.id,date:r.created_at,effect:Number(r.delta),amount:original?Math.abs(Number(original.accountAmount)):Math.abs(Number(r.delta)),receiptNo:original?receiptNumber(original):null,
   label:original?supplierLabel(original):r.note||'تسوية حساب',notes:original?.notes||r.note||'',category,kind:original?.kind,voided:original?.voided,voidedAt:t?.supplier_payment_voided_at,rate:Number(r.rate),original,revision};
 });
 return {id:data.supplierId||data.id,name,type:'supplier',currency,rows,revision};
}
export function compactPeriod(rows,from='',to='',category='all',query=''){
 let balance=0,opening=0;const period=[];
 const sorted=rows.map((r,index)=>({...r,_order:index})).sort((a,b)=>new Date(a.date)-new Date(b.date)||a._order-b._order);
 for(const r of sorted){const day=dateKey(r.date);if(to&&day>to)continue;balance=Math.round((balance+Number(r.effect))*100)/100;if(from&&day<from){opening=balance;continue;}period.push({...r,balance});}
 const matches=period.filter(r=>(category==='all'||r.category===category||category==='other'&&!['invoices','payments'].includes(r.category))&&(!query||[r.label,r.notes,r.receiptNo].join(' ').toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())));
 return {rows:matches,all:period,opening,balance,
  invoices:period.filter(r=>r.category==='invoices'&&!r.voided).reduce((s,r)=>s+r.amount,0),
  payments:period.filter(r=>r.category==='payments'&&(!r.voided||(to&&r.voidedAt&&dateKey(r.voidedAt)>to))).reduce((s,r)=>s+r.amount,0),
  originalOpening:period.filter(r=>r.category==='opening').reduce((s,r)=>s+r.effect,0)};
}
export function compactStatementBody(account,period,from,to){
 const currency=account.currency;
 return '<div class="meta"><div>'+e(account.type==='supplier'?'المورد':'العميل')+': '+e(account.name)+'</div><div>العملة: '+currency+'</div><div>من '+e(from||'بداية التعامل')+' إلى '+e(to||'اليوم')+'</div><div>رصيد أول المدة: '+money(period.opening,currency)+' '+unit(currency)+'</div></div><table data-pdf-paginate><thead><tr><th>التاريخ</th><th>البيان / الوصل</th><th>مدين</th><th>دائن</th><th>الرصيد</th></tr></thead><tbody>'+period.rows.map(r=>'<tr><td>'+e(new Date(r.date).toLocaleDateString('en-GB',{timeZone:'Asia/Baghdad'}))+'</td><td>'+e(r.label)+(r.receiptNo?' #'+e(r.receiptNo):'')+(r.notes?'<br>'+e(r.notes):'')+'</td><td>'+money(Math.max(0,r.effect),currency)+'</td><td>'+money(Math.max(0,-r.effect),currency)+'</td><td>'+money(r.balance,currency)+'</td></tr>').join('')+'</tbody></table><p>الرصيد الجاري يشمل كل الحركات، حتى عند تصفية نوع الحركة. الموجب '+(account.type==='supplier'?'مستحق للمورد، والسالب رصيد لنا عنده.':'لنا على العميل، والسالب للعميل عندنا.')+'</p>';
}
export function compactMovementBody(account,row){
 return '<div class="meta"><div>'+e(account.name)+'</div><div>'+e(row.label)+'</div><div>وصل #'+e(row.receiptNo||'—')+'</div><div>'+e(new Date(row.date).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'}))+'</div>'+(row.original?.creatorPhone?'<div>صاحب الوصل: '+e(row.original.creatorName||'')+'</div><div>هاتف صاحب الوصل: '+phoneContactDocument(row.original.creatorPhone)+'</div>':'')+'</div><table><thead><tr><th>المبلغ</th><th>أثره على الحساب</th><th>الرصيد بعد الحركة</th></tr></thead><tbody><tr><td>'+money(row.amount,account.currency)+'</td><td>'+money(row.effect,account.currency)+'</td><td>'+money(row.balance,account.currency)+'</td></tr></tbody></table><p>'+e(row.notes||'')+'</p>';
}
