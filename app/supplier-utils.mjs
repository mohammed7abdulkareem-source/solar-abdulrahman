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
export const supplierLabel=t=>t.kind==='supplier_payment'?'تسديد مورد':t.cash?'شراء نقدي — مسدد':'شراء آجل';
export function supplierDocument(t){
 const payment=t.kind==='supplier_payment'||!t.kind,e=escapeHtml;
 const meta='<div class="meta"><div><b>'+(payment?'رقم الوصل':'رقم الفاتورة')+':</b> '+e(receiptNumber(t))+'</div><div><b>'+(payment?'المورد':'المجهّز')+':</b> '+e(t.party)+'</div><div><b>التاريخ:</b> '+e(new Date(t.date).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'}))+'</div><div><b>الحركة:</b> '+(payment?'تسديد نقدي للمورد':supplierLabel(t))+'</div></div>';
 const items=t.items||[],quantity=items.reduce((sum,i)=>sum+Number(i.qty||0),0),subtotal=items.reduce((sum,i)=>sum+Number(i.qty||0)*Number(i.price||0),0);
 const table=payment?'':('<table class="purchaseDocument"><colgroup><col style="width:6%"><col style="width:40%"><col style="width:14%"><col style="width:20%"><col style="width:20%"></colgroup><thead><tr><th>ت</th><th>المادة / البراند / الصنف</th><th>العدد</th><th>سعر الوحدة د.ع</th><th>المجموع د.ع</th></tr></thead><tbody>'+items.map((i,index)=>'<tr style="break-inside:avoid"><td>'+String(index+1)+'</td><td style="text-align:right;color:#000;font-weight:800"><strong>'+e(i.name)+'</strong>'+([i.brand,i.category].filter(Boolean).length?'<br><strong>'+[i.brand,i.category].filter(Boolean).map(e).join(' · ')+'</strong>':'')+'</td><td>'+money(i.qty)+'</td><td>'+money(i.price)+'</td><td>'+money(Number(i.qty)*Number(i.price))+'</td></tr>').join('')+'</tbody></table><div class="meta purchaseCounts" style="break-inside:avoid"><div><b>عدد الفقرات:</b> '+items.length+'</div><div><b>مجموع الكميات:</b> '+money(quantity)+'</div><div><b>مجموع المواد:</b> '+money(subtotal)+' د.ع</div><div><b>المصاريف الإضافية:</b> '+money(t.expenses)+' د.ع</div></div>');
 return {title:payment?'وصل تسديد مورد':'فاتورة شراء',body:meta+table+(payment&&Number(t.expenses)>0?'<div class="notes">المصاريف: '+money(t.expenses)+' د.ع</div>':'')+(t.notes?'<div class="notes">'+e(t.notes)+'</div>':''),total:money(t.total)+' د.ع',subtitle:!t.draft&&t.id?'وصل محفوظ #'+receiptNumber(t):'مسودة — غير محفوظة'};
}
