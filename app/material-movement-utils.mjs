import {quantity,movementLabel,escapeHtml as e} from './warehouse-utils.mjs';
import {formatMoney} from './money-format.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
export const movementTime=value=>new Date(value).toLocaleString('en-GB',{timeZone:'Asia/Baghdad',hour12:false});
export function filterMaterialRows(rows,direction='all',query=''){
 const words=normalizeSearch(query).replace(/#/g,'').split(/\s+/).filter(Boolean);
 return rows.filter(r=>(direction==='all'||(direction==='in'?Number(r.inQty)>0:Number(r.outQty)>0))&&words.every(w=>normalizeSearch([r.party,r.receiptNo,r.note,r.warehouseName,r.createdByName,r.preparedByName,r.executedByName,movementLabel[r.kind]].join(' ')).includes(w)));
}
export function materialPrice(row){
 const p=row.pricing;
 if(!p)return {label:'لا يوجد سعر متاح لهذا المستند',unit:'—',total:'—'};
 if(p.kind==='system_total')return {label:'سعر المنظومة إجمالي؛ سعر المادة غير موزّع',unit:'—',total:'—'};
 return {label:p.kind==='transfer_cost'?'كلفة نقل مثبتة':p.kind==='purchase'?'سعر شراء مثبت':'سعر بيع مثبت',unit:p.unitPrice==null?'—':formatMoney(p.unitPrice)+' د.ع',total:p.lineTotal==null?'—':formatMoney(p.lineTotal)+' د.ع'};
}
export function materialMovementDocument(data,rows,{direction='all',query=''}={}){
 if(!data)return '';
 const p=data.product,priced=data.withPrices;
 return '<style>.materialLedgerReport table{table-layout:fixed;width:100%;font-size:10px}.materialLedgerReport th{font-size:9px;padding:6px 4px}.materialLedgerReport td{font-size:10px;line-height:1.45;padding:6px 4px;overflow-wrap:anywhere}.materialLedgerReport .meta{font-size:11px}.materialLedgerReport p{font-size:10px;line-height:1.5}</style><div class="materialLedgerReport"><div class="meta"><div><b>المادة:</b> '+e(p.name)+'</div><div>الكود: '+e(p.code)+' · '+e([p.brand,p.category].filter(Boolean).join(' · '))+'</div><div>الفترة: '+e(data.from||'البداية')+' — '+e(data.to||'اليوم')+'</div><div>الاتجاه: '+e({all:'الكل',in:'دخول',out:'خروج'}[direction])+(query?' · البحث: '+e(query):'')+'</div><div>العرض: '+(priced?'بالأسعار المثبتة بالدينار العراقي':'بدون أسعار')+'</div></div>'+
 '<table data-pdf-paginate><thead><tr><th>المخزن</th><th>قبل أول حركة بالفترة</th><th>دخول الفترة</th><th>خروج الفترة</th><th>بعد آخر حركة بالفترة</th><th>المتاح حاليًا</th></tr></thead><tbody>'+data.warehouses.map(w=>'<tr><td>'+e(w.name)+'</td><td>'+(w.beforeFirst==null?'—':quantity(w.beforeFirst))+'</td><td>'+quantity(w.inQty)+'</td><td>'+quantity(w.outQty)+'</td><td>'+(w.afterLast==null?'—':quantity(w.afterLast))+'</td><td>'+quantity(w.currentQty)+'</td></tr>').join('')+'</tbody></table>'+
 '<table data-pdf-paginate><thead><tr><th>التاريخ / الوصل</th><th>الحركة / الطرف / المخزن</th><th>المستخدم / المجهّز</th><th>داخل</th><th>خارج</th><th>الرصيد بعد الحركة</th>'+(priced?'<th>السعر / مبلغ الفقرة</th>':'')+'</tr></thead><tbody>'+rows.map(r=>{const price=priced?materialPrice(r):null;return '<tr><td>'+e(movementTime(r.date))+'<br>#'+e(r.receiptNo)+'</td><td><b>'+e(movementLabel[r.kind]||r.kind)+'</b><br>'+e(r.party||'غير مسجل')+'<br>'+e(r.warehouseName)+(r.note?'<br>'+e(r.note):'')+'</td><td>المستخدم: '+e(r.createdByName||'غير مسجل')+'<br>المجهّز: '+e(r.preparedByName||'لم يُسجّل تجهيز')+(r.preparedAt?'<br>'+e(movementTime(r.preparedAt)):'')+(r.executedByName&&r.executedByName!==r.createdByName?'<br>منفّذ الحركة: '+e(r.executedByName):'')+'</td><td>'+quantity(r.inQty)+'</td><td>'+quantity(r.outQty)+'</td><td><b>'+quantity(r.balance)+'</b></td>'+(price?'<td>'+e(price.label)+'<br>'+e(price.unit)+'<br>'+e(price.total)+'</td>':'')+'</tr>';}).join('')+'</tbody></table><p>عدد الحركات الظاهرة: '+quantity(rows.length)+'. الرصيد بعد كل حركة يخص مخزنها ويحتسب الحركات السابقة حتى عند تصفية التاريخ أو الاتجاه أو البحث. ملخص المخازن يشمل الفترة المختارة قبل البحث والاتجاه.</p>'+
 (data.scope==='own'?'<p>يعرض الكشف وصولاتك المسموحة فقط؛ الرصيد المخزني قد يتأثر بحركات مستخدمين آخرين لا تظهر تفاصيلها.</p>':'')+
 '<p>حجز النقل يخصم الكمية المتاحة من مخزن المصدر، ويظهر الدخول إلى الوجهة بعد اعتماد التجهيز. كميات كل مخزن مستقلة.</p></div>';
}
