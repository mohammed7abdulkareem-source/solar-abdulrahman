import {money,dateKey,escapeHtml as e} from './supplier-utils.mjs';

// The saved profit remains authoritative. These labels describe who bore the
// expense; they do not apply a second deduction to the accounting movement.
export function profitInvoiceExpense(breakdown){
 if(breakdown.kind!=='sale'||typeof breakdown.invoiceExpensesOnCustomer!=='boolean')return {label:'مصاريف الفاتورة',amount:breakdown.invoiceExpenses};
 return breakdown.invoiceExpensesOnCustomer
  ?{label:'مصاريف الفاتورة على الزبون',amount:breakdown.customerInvoiceExpenses??breakdown.invoiceExpenses}
  :{label:'مصاريف الفاتورة على الشركة',amount:breakdown.companyInvoiceExpenses??breakdown.invoiceExpenses};
}
export function receiptProfitFigures(b,{provisional=false,showInvoiceExpenses=false}={}){
 const system=b.kind==='system',invoiceExpense=profitInvoiceExpense(b);
 const companyExpense=Number(b.companyInvoiceExpenses??(b.invoiceExpensesOnCustomer===true?0:b.invoiceExpenses)??0);
 const installation=Number(b.installationExpenses??0),gross=Number(b.grossProfit);
 const other=Math.round((Number(b.netProfit)-gross+companyExpense+installation)*100)/100;
 return [
  ['sale',system?'سعر بيع المنظومة':'مبلغ بيع المواد',b.sales],
  ['materials','كلفة المواد عند البيع',b.materialsCost],
  ['gross','مجمل الربح قبل المصاريف',gross],
  ...(showInvoiceExpenses||Number(invoiceExpense.amount)?[['invoice',invoiceExpense.label,invoiceExpense.amount]]:[]),
  ...(system&&(showInvoiceExpenses||companyExpense)?[['beforeInstallation','الربح قبل مصاريف التنصيب',gross-companyExpense]]:[]),
  ...(system||installation?[['installation','مصاريف التنصيب المعتمدة',installation]]:[]),
  ...(Math.abs(other)>=.005?[['adjustment','تعديلات ربح أخرى',other]]:[]),
  ['net',provisional?'صافي الربح غير النهائي':'صافي الربح',b.netProfit],
 ];
}
export function pendingProfitFigures(row){
 const figures=receiptProfitFigures({kind:'system',sales:row.total,materialsCost:row.materialCost,
  grossProfit:Number(row.total)-Number(row.materialCost),invoiceExpenses:row.invoiceExpenses,
  installationExpenses:row.approvedExpenses,netProfit:row.receiptProvisionalProfit??row.provisionalProfit},{provisional:true});
 if(row.profitAttributedElsewhere)figures.push(['contribution','حصة هذا الحساب من الربح غير النهائي',row.provisionalProfit]);
 return figures;
}
export function profitMaterialDocument(breakdown,movement){
 const system=breakdown.kind==='system',items=breakdown.items||[];
 const amount=value=>{const text=money(value);return '<bdi dir="ltr" class="reportNumber'+(text.length>14?' reportNumberLong':'')+'">'+text+'</bdi>'};
 const head='<div class="meta"><div><b>الزبون:</b> '+e(breakdown.party||'زبون نقدي')+'</div><div><b>الوصل:</b> #'+e(breakdown.receiptNo)+'</div><div><b>التاريخ:</b> '+e(dateKey(breakdown.date))+'</div><div><b>منشئ الوصل:</b> '+e(breakdown.creatorName||'—')+'</div>'+(breakdown.responsibleName?'<div><b>المسؤول عن الوصل:</b> '+e(breakdown.responsibleName)+'</div>':'')+'<div><b>مخزن التجهيز:</b> '+e(breakdown.warehouseName||'—')+'</div><div><b>العملة:</b> الدينار العراقي · IQD</div></div>';
 const table='<table data-pdf-paginate><thead><tr><th>المادة / البراند / الفئة</th><th>العدد</th>'+(system?'':'<th>سعر البيع / وحدة</th><th>مبلغ البيع</th>')+'<th>الكلفة / وحدة</th><th>كلفة الفقرة</th>'+(system?'':'<th>ربح الفقرة</th>')+'</tr></thead><tbody>'+items.map(i=>'<tr><td>'+e(i.name)+'<br><small>'+e([i.code&&'كود '+i.code,i.brand,i.category].filter(Boolean).join(' · '))+'</small></td><td>'+amount(i.qty)+'</td>'+(system?'':'<td>'+amount(i.unitPrice)+'</td><td>'+amount(i.lineSales)+'</td>')+'<td>'+amount(i.unitCost)+'</td><td>'+amount(i.lineCost)+'</td>'+(system?'':'<td>'+amount(i.lineProfit)+'</td>')+'</tr>').join('')+'</tbody></table>';
 const summary='<div class="notes">'+receiptProfitFigures(breakdown).map(([,label,value])=>e(label)+': '+money(value)+' د.ع').join('<br>')+'<br>المسوّى سابقًا: '+money(movement.settled)+' د.ع · غير المسوّى: '+money(movement.available)+' د.ع</div>';
 return {title:'تفاصيل أرباح '+(system?'منظومة':'جملة'),body:head+(system?'<p class="notes">سعر المنظومة إجمالي متفق عليه؛ تظهر كلفة كل مادة وربح المنظومة كاملًا.</p>':'<p class="notes">ربح الفقرة = مبلغ بيع الفقرة − كلفتها المحفوظة وقت البيع.</p>')+'<h3 class="reportSectionTitle">تفاصيل المواد · '+items.length+' فقرة</h3>'+table+'<h3 class="reportSectionTitle">مطابقة ربح الحركة والتسويات</h3>'+summary,total:money(breakdown.netProfit)+' د.ع',subtitle:'وصل #'+breakdown.receiptNo};
}
