import {escapeHtml as e} from './supplier-utils.mjs';
import {formatMoney as money,currencyUnit as unit} from './money-format.mjs';

const numeric=value=>value!==null&&value!==undefined&&value!==''&&Number.isFinite(Number(value))?Number(value):null;

// Prices belong to the original invoice currency, not necessarily the account currency.
export function invoiceLines(account,row,documents={}){
 const supplier=account.type==='supplier';
 const document=supplier?row.original:documents[String(row.id)];
 if(!document)return {available:false,items:[],currency:supplier?(row.original?.sourceCurrency||'IQD'):'IQD'};
 const currency=supplier?(document.sourceCurrency||'IQD'):'IQD';
 const items=(document.items||[]).map(item=>{
  const qty=numeric(item.qty),price=supplier?(currency==='USD'?numeric(item.sourcePrice):numeric(item.price)):(document.kind==='sale'?numeric(item.price):null);
  return {name:item.product_name||item.name||'مادة',brand:item.brand_name||item.brand||'',category:item.category||'',qty,price,
   total:qty!==null&&price!==null?Math.round((qty*price+Number.EPSILON)*100)/100:null};
 });
 return {available:true,items,currency};
}

export function groupedInvoicesBody(account,period,from,to,documents={}){
 const supplier=account.type==='supplier',accountCurrency=account.currency;
 const header='<style>.invoiceReport table{border:1px solid #7b90a0!important;margin:12px 0;table-layout:fixed}.invoiceReport th,.invoiceReport td{border:1px solid #9cabb6!important;padding:5px 6px;font-size:11px;line-height:1.6}.invoiceReport th{background:#e0ebf7!important;color:#143e5a!important;font-weight:700!important}.invoiceReport thead .invoiceHeading{background:#c5d9ef!important;font-size:12px;text-align:right}.invoiceReport td{color:#172f3d!important}.invoiceReport .material{text-align:right;overflow-wrap:anywhere}.invoiceReport .number{direction:ltr;unicode-bidi:isolate;overflow-wrap:anywhere}.invoiceReport tfoot th{text-align:right;background:#f3f7fb!important}.invoiceReport p{font-size:11px;line-height:1.8}</style><section class="invoiceReport"><div class="meta"><div>'+(supplier?'المورد':'العميل')+': '+e(account.name)+'</div><div>عملة الحساب: '+e(accountCurrency)+'</div><div>من '+e(from||'بداية التعامل')+' إلى '+e(to||'آخر حركة')+'</div><div>عدد الفواتير: '+period.rows.length+'</div></div>';
 const tables=period.rows.map(row=>{
  const lines=invoiceLines(account,row,documents),currency=lines.currency,original=row.original||{};
  const date=e(new Date(row.date).toLocaleDateString('en-GB',{timeZone:'Asia/Baghdad'}));
  const heading=(supplier?'فاتورة شراء':'فاتورة بيع')+' #'+e(row.receiptNo??'—')+' · '+date;
  const rows=lines.available?(lines.items.length?lines.items.map(item=>'<tr><td class="material">'+e(item.name)+([item.brand,item.category].filter(Boolean).length?'<br><small>'+[item.brand,item.category].filter(Boolean).map(e).join(' · ')+'</small>':'')+'</td><td class="number">'+(item.qty===null?'—':money(item.qty))+'</td><td class="number">'+(item.price===null?'—':money(item.price,currency))+'</td><td class="number">'+(item.total===null?'—':money(item.total,currency))+'</td></tr>').join(''):'<tr><td colspan="4">لا توجد مواد محفوظة لهذه الفاتورة.</td></tr>'):'<tr><td colspan="4">تفاصيل المواد غير متاحة ضمن صلاحيات الحساب.</td></tr>';
  const subtotal=lines.items.length&&lines.items.every(i=>i.total!==null)?lines.items.reduce((s,i)=>s+i.total,0):null;
  const invoiceAmount=supplier?numeric(original.accountAmount):numeric(row.amount);
  const savedSource=supplier?numeric(original.sourceSubtotal):null,expenses=supplier?numeric(original.expenses):null;
  const extra=(subtotal===null?'':'مجموع المواد: '+money(subtotal,currency)+' '+unit(currency)+' · ')+(savedSource===null?'':'قيمة المواد المثبتة: '+money(savedSource,currency)+' '+unit(currency)+' · ')+(expenses?'المصاريف: '+money(expenses,'IQD')+' د.ع · ':'')+(invoiceAmount===null?'':'مبلغ الفاتورة بعملة الحساب: '+money(Math.abs(invoiceAmount),accountCurrency)+' '+unit(accountCurrency)+' · ')+'أثرها على الحساب: '+money(row.effect,accountCurrency)+' '+unit(accountCurrency)+' · الرصيد بعدها: '+money(row.balance,accountCurrency)+' '+unit(accountCurrency);
  return '<table data-pdf-paginate data-pdf-keep-footer-with-row><colgroup><col style="width:40%"><col style="width:14%"><col style="width:23%"><col style="width:23%"></colgroup><thead><tr><th class="invoiceHeading" colspan="4">'+heading+'</th></tr><tr><th>المادة / البراند</th><th>العدد</th><th>السعر '+e(unit(currency))+'</th><th>المجموع '+e(unit(currency))+'</th></tr></thead><tbody>'+rows+'</tbody><tfoot><tr><th colspan="4">'+e(extra)+'</th></tr></tfoot></table>';
 }).join('');
 return header+tables+(period.rows.length?'':'<p>لا توجد فواتير ضمن الاختيارات.</p>')+'<p>الرصيد بعد كل فاتورة يشمل جميع حركات الحساب، بما فيها التسديدات. الأسعار حسب عملة الفاتورة، والرصيد حسب عملة الحساب.</p></section>';
}
