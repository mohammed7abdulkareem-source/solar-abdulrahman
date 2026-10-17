import {normalizeSearch} from './party-search-utils.mjs';
export const money=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2});
export const escapeHtml=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const receiptNumber=row=>row?.receiptNo??row?.receipt_no??'مسودة';
export const receiptQuery=value=>normalizeSearch(value).replace(/[#٬,\s]/g,'');
export const matchesReceipt=(row,query)=>!query||receiptQuery(receiptNumber(row)).includes(receiptQuery(query))||normalizeSearch(row.party).includes(normalizeSearch(query));
export const moneyInput=value=>normalizeSearch(value).replace(/[,٬\s]/g,'').replace(/٫/g,'.');
export const supplierEffect=t=>t.kind==='supplier_payment'?-Number(t.total||0):t.cash?0:Number(t.total||0);
export const dateKey=value=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(value));
export function supplierLedger(tx,party,from='',to=''){
 const rows=tx.filter(t=>['purchase','supplier_payment'].includes(t.kind)&&(t.partyId?String(t.partyId)===String(party?.id):t.party===party?.name)).sort((a,b)=>new Date(a.date)-new Date(b.date)||Number(a.id)-Number(b.id));
 let balance=0,opening=0;const data=[];
 for(const t of rows){const date=dateKey(t.date);if(to&&date>to)continue;balance=Math.round((balance+supplierEffect(t))*100)/100;if(from&&date<from){opening=balance;continue;}data.push({...t,balance});}
 return {rows:data,opening,balance};
}
export const supplierIsCharge=t=>(t.kind==='supplier_payment'||!t.kind)&&(Number(t.total)<0||String(t.mode||'').startsWith('charge_'));
export const supplierChargeReason=t=>({charge_extra_expense:'مصروف إضافي',charge_old_balance:'حساب قديم',charge_other:'إضافة أخرى'}[t.mode]||'إضافة على الحساب');
export const supplierLabel=t=>t.kind==='supplier_payment'?(supplierIsCharge(t)?'إضافة على حساب المورد — '+supplierChargeReason(t):'تسديد مورد'):t.cash?'شراء نقدي — مسدد':'شراء آجل';
export function supplierDocument(t){
 const payment=t.kind==='supplier_payment'||!t.kind,charge=payment&&supplierIsCharge(t),e=escapeHtml;
 const accountUnit=t.accountCurrency==='USD'?'$':'د.ع',sourceUnit=t.sourceCurrency==='USD'?'$':'د.ع';
 const fxInfo=t.marketRate>1?'<div class="meta"><div>عملة حساب المورد: '+e(t.accountCurrency||'IQD')+'</div><div>الصرف المثبت: '+money(t.marketRate)+' د.ع لكل دولار</div><div>المبلغ بعملة الحساب: '+money(Math.abs(t.accountAmount??t.total))+' '+accountUnit+'</div>'+(t.cash?'<div>المدفوع من القاصة: '+money(t.cashAmount??t.total)+' '+(t.cashCurrency==='USD'?'$':'د.ع')+'</div>':'')+'</div>':'';
 const meta='<div class="meta"><div><b>'+(payment?'رقم الوصل':'رقم الفاتورة')+':</b> '+e(receiptNumber(t))+'</div><div><b>'+(payment?'المورد':'المجهّز')+':</b> '+e(t.party)+'</div><div><b>التاريخ:</b> '+e(new Date(t.date).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'}))+'</div><div><b>الحركة:</b> '+(payment?(charge?'إضافة على حساب المورد — '+supplierChargeReason(t):'تسديد نقدي للمورد'):supplierLabel(t))+'</div></div>';
 const usd=!payment&&t.sourceCurrency==='USD',unit=usd?'$':'د.ع';
 const originalPrice=i=>usd?Number(i.sourcePrice??i.price):Number(i.price);
 const exchangeInfo=usd?'<div class="meta"><div><b>عملة الشراء:</b> الدولار الأمريكي</div><div><b>الصرف المثبت:</b> '+money(t.exchangeRate)+' د.ع لكل دولار</div><div><b>100 دولار:</b> '+money(Number(t.exchangeRate)*100)+' د.ع</div></div>':'';
 const items=t.items||[],quantity=items.reduce((sum,i)=>sum+Number(i.qty||0),0),subtotal=items.reduce((sum,i)=>sum+Number(i.qty||0)*originalPrice(i),0);
 const table=payment?'':('<table class="purchaseDocument" data-pdf-paginate><colgroup><col style="width:6%"><col style="width:40%"><col style="width:14%"><col style="width:20%"><col style="width:20%"></colgroup><thead><tr><th>ت</th><th>المادة / البراند / الصنف</th><th>العدد</th><th>سعر الوحدة '+unit+'</th><th>المجموع '+unit+'</th></tr></thead><tbody>'+items.map((i,index)=>'<tr style="break-inside:avoid"><td>'+String(index+1)+'</td><td style="text-align:right;color:#000;font-weight:800"><strong>'+e(i.name)+'</strong>'+([i.brand,i.category].filter(Boolean).length?'<br><strong>'+[i.brand,i.category].filter(Boolean).map(e).join(' · ')+'</strong>':'')+'</td><td>'+money(i.qty)+'</td><td>'+money(originalPrice(i))+'</td><td>'+money(Number(i.qty)*originalPrice(i))+'</td></tr>').join('')+'</tbody></table><div data-pdf-end class="meta purchaseCounts" style="break-inside:avoid"><div><b>عدد الفقرات:</b> '+items.length+'</div><div><b>مجموع الكميات:</b> '+money(quantity)+'</div><div><b>مجموع المواد:</b> '+money(subtotal)+' '+unit+'</div><div><b>المصاريف الإضافية:</b> '+money(t.expenses)+' د.ع</div></div>');
 const accountInfo=payment?(charge?'<p class="notes"><b>حركة غير نقدية:</b> تزيد المستحق للمورد ولا تخصم من القاصة.</p>':'')+(t.beforeBalance!=null&&t.afterBalance!=null?'<div class="meta"><div>رصيد المورد السابق: '+money(t.beforeBalance)+' '+accountUnit+'</div><div>رصيد المورد بعد الحركة: '+money(t.afterBalance)+' '+accountUnit+'</div></div>':''):'';
 return {title:payment?(charge?'وصل إضافة على حساب مورد':'وصل تسديد مورد'):'فاتورة شراء',body:meta+fxInfo+exchangeInfo+table+accountInfo+(payment&&Number(t.expenses)>0?'<div class="notes">المصاريف: '+money(t.expenses)+' د.ع</div>':'')+(t.notes?'<div data-pdf-end class="notes">'+e(t.notes)+'</div>':''),total:payment?money(Math.abs(t.sourceSubtotal??t.total))+' '+sourceUnit:money(t.total)+' د.ع',subtitle:!t.draft&&t.id?'وصل محفوظ #'+receiptNumber(t):'مسودة — غير محفوظة'};
}
