import {warrantyDocument,warrantyQrSvg} from './warranty-utils.mjs';
import {receiptNumber} from './supplier-utils.mjs';
import {escapeHtml as escape,invoiceDate} from './document-format.mjs';
export const formatMoney=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2});
export const statusLabel={pending:'بانتظار التنصيب',in_progress:'جاري التنصيب',completed:'بانتظار الغلق',closed:'ملف مغلق'};
const money=value=>'<span class="documentNumber" dir="ltr">'+formatMoney(value)+'</span> <small>د.ع</small>';
export function invoiceAccountDocument(row){
 const a=row.invoiceAccount||row.invoice_account;
 if(row.draft||!a)return '<div class="accountUnavailable">'+(row.draft?'ملخص الحساب وآخر تسديد يظهران بعد حفظ الفاتورة.':'تعذّر تحميل ملخص الحساب. حدّث البيانات ثم افتح الوصل مجددًا.')+'</div>';
 const line=(label,value,cls='')=>'<div class="accountLine '+cls+'"><span>'+label+'</span><b>'+value+'</b></div>';
 const payment=a.lastPayment;
 return '<section class="invoiceAccount"><h3>ملخص حساب الزبون عند إصدار الفاتورة</h3><div class="accountSummaryGrid"><div class="accountBalanceLines">'+
 line('الحساب السابق',a.available?money(a.previousBalance):'غير متاح')+
 line('مبلغ الفاتورة الحالية',money(a.invoiceTotal))+
 line('المدفوع عن هذه الفاتورة',money(a.paidNow))+
 line('الحساب النهائي',a.available?money(a.balanceAfter):'غير متاح','accountFinal')+
 '</div><div class="lastPayment"><h4>آخر تسديد سابق</h4>'+(payment?'<strong>'+money(payment.amount)+'</strong><dl><div><dt>تاريخ التسديد</dt><dd dir="ltr">'+invoiceDate(payment.date)+'</dd></div><div><dt>رقم وصل التسديد</dt><dd dir="ltr">'+escape(payment.receiptNo??'—')+'</dd></div></dl>':'<p>'+(a.available?'لا يوجد تسديد سابق مسجّل.':'التسديد السابق غير متاح لحساب غير مرتبط.')+'</p>')+'</div></div><p class="accountSnapshotNote">'+(!a.available?'تعذّر ربط الحساب السابق بعميل مسجّل.':a.basis==='retained-ledger'?'الرصيد السابق مُعاد بناؤه من الحركات المحفوظة حتى تاريخ الوصل.':'الأرصدة وآخر تسديد ثابتة حسب وقت إصدار الوصل.')+'</p></section>';
}
export function salesDocument(row,customer=true){
 const system=row.kind==='system',items=row.items||[];
 const meta=[['رقم الفاتورة',receiptNumber(row)],['التاريخ',invoiceDate(row.created_at)],['الزبون',row.party_name||'زبون نقدي'],['المسؤول',row.creatorName||'—']];
 const warehouseName=row.warehouseName||row.warehouse_name;
 if(row.draft&&warehouseName)meta.push(['المخزن',warehouseName]);
 if(customer)meta.push(['طريقة الدفع',system?'آجل':row.cash||row.payment_mode==='cash'||row.mode==='cash'?'نقدي':'آجل']);
 if(system)meta.push(['المهندس',row.installerName||'غير محدد'],['الهاتف',row.customer_phone||'—'],['العنوان',row.customer_address||'—'],['الموعد',[row.install_date,row.install_time?.slice(0,5)].filter(Boolean).join(' • ')||'يحدد لاحقاً']);
 if(!row.draft)meta.push([warehouseName?'المخزن':'تجهيز المخزن',[warehouseName,(row.warehouse_status||row.warehouseStatus)==='ready'?'✓ تم التجهيز':'بانتظار التجهيز'].filter(Boolean).join(' • ')]);
 const prices=customer&&!system;
 const safeToken=row.warehouseQrToken||row.warehouse_qr_token,token=customer?(row.warrantyToken||row.warranty_token||safeToken):safeToken;
 const qr=!row.draft&&token?warrantyQrSvg(token):'';
 const rows=items.map((i,index)=>'<tr><td class="documentNumber">'+String(index+1)+'</td><td class="materialName"><b>'+escape(i.product_name)+'</b>'+([i.brand_name,i.category].filter(Boolean).length?'<br><small>'+escape([i.brand_name,i.category].filter(Boolean).join(' • '))+'</small>':'')+'</td><td class="documentNumber">'+formatMoney(i.qty)+'</td>'+(prices?'<td class="documentNumber">'+formatMoney(i.price)+'</td><td class="documentNumber">'+formatMoney(Number(i.qty)*Number(i.price))+'</td>':'')+'</tr>').join('');
 const cols=prices?[6,40,10,22,22]:[7,76,17];
 const body='<section class="salesDocument"><div class="invoiceIntro"><div class="meta">'+meta.map(([k,v])=>'<div><b>'+k+':</b> '+escape(v)+'</div>').join('')+'</div>'+(qr?'<div class="invoiceQr">'+qr+'<b>فحص الفاتورة والضمان</b><small>رقم '+escape(receiptNumber(row))+'</small></div>':'')+'</div><table class="invoiceItems" data-pdf-paginate><colgroup>'+cols.map(n=>'<col style="width:'+n+'%">').join('')+'</colgroup><thead><tr><th>ت</th><th>تفاصيل المادة / البراند</th><th>العدد</th>'+(prices?'<th>سعر الوحدة د.ع</th><th>المجموع د.ع</th>':'')+'</tr></thead><tbody>'+rows+'</tbody></table><div class="documentCounts"><span>عدد الفقرات: <b>'+items.length+'</b></span><span>مجموع الكميات: <b class="documentNumber">'+formatMoney(items.reduce((sum,i)=>sum+Number(i.qty||0),0))+'</b></span></div>'+
 (customer&&!system&&Number(row.expenses)>0?'<div class="notes">المصاريف الإضافية: '+money(row.expenses)+'</div>':'')+
 (customer?invoiceAccountDocument(row):'')+warrantyDocument(row,{hasQr:!!qr})+
 (!customer&&row.preparedBy?'<div class="notes"><b>مسؤول التجهيز:</b> '+escape(row.preparedBy)+'</div>':'')+
 (!customer&&row.note?'<div class="notes" data-pdf-end><b>ملاحظات التجهيز:</b> '+escape(row.note)+'</div>':'')+
 (customer&&row.notes?'<div class="notes" data-pdf-end><b>ملاحظات الفاتورة:</b> '+escape(row.notes)+'</div>':'')+'</section>';
 return {title:customer?(system?'فاتورة بيع منظومة':'فاتورة بيع جملة'):'وصل مخزني — بدون أسعار',body,total:customer?formatMoney(row.total)+' د.ع':'',subtitle:customer?'نسخة الزبون':'نسخة المخزن'};
}
