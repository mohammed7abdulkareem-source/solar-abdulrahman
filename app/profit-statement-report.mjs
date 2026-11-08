import {money,escapeHtml as e,dateKey} from './supplier-utils.mjs';

export function profitStatementRows(rows,total,{snapshot=false}={}){
 return '<h3 class="reportSectionTitle">'+(snapshot?'الحركات المحفوظة وقت طلب التسوية':'حركات الفترة · جميع المبالغ بالدينار العراقي')+'</h3><table data-pdf-paginate><colgroup><col style="width:15%"><col style="width:34%"><col style="width:17%"><col style="width:17%"><col style="width:17%"></colgroup><thead><tr><th>التاريخ</th><th>الحركة / الوصل</th><th>الربح د.ع</th><th>المسوّى سابقًا</th><th>غير المسوّى</th></tr></thead><tbody>'+(rows.length?rows.map(r=>'<tr><td>'+e(dateKey(r.date))+'</td><td>'+e(r.label)+(r.receiptNo!=null?' #'+e(r.receiptNo):'')+(r.deleted?' · ألغيت الحركة':'')+'</td><td>'+money(r.value)+'</td><td>'+money(r.settled)+'</td><td>'+money(r.available)+'</td></tr>').join(''):'<tr><td colspan="5" class="reportEmpty">لا توجد حركات ضمن الفترة.</td></tr>')+'</tbody></table><p class="notes">'+(snapshot?'الربح المطلوب تسويته وقت الطلب':'غير المسوّى من أرباح الفترة')+': <b>'+money(total)+' د.ع</b>'+(snapshot?' · هذه لقطة محفوظة للطلب، وليست الرصيد الحالي.':'')+'</p>';
}

export function profitStatementDocument(data,from,to){
 const rows=data.rows||[],current=rows.reduce((s,r)=>s+Number(r.value),0),settled=rows.reduce((s,r)=>s+Number(r.settled),0);
 return '<div class="meta"><div>المستخدم: '+e(data.ownerName)+'</div><div>الفترة: '+e(from||'البداية')+' — '+e(to||'اليوم')+'</div><div>العملة: الدينار العراقي · IQD</div><div>عدد الحركات: '+rows.length+'</div></div>'+
  '<h3 class="reportSectionTitle">الرصيد الحالي · جميع الفترات</h3><div class="reportCurrentBalance"><strong>الرصيد المتبقي بعد التسوية: '+money(data.retainedProfit)+' د.ع</strong><p>يشمل جميع الفترات والتوزيعات المعتمدة، ومستقل عن النقد في القاصة.</p></div>'+
  '<h3 class="reportSectionTitle">نتائج الفترة المختارة</h3><div class="reportSummary">'+[['ربح الفترة قبل التسويات',current],['المسوّى من أرباح الفترة',settled],['غير المسوّى من أرباح الفترة',data.available]].map(([label,value])=>'<div class="reportMetric"><span>'+label+'</span><strong>'+money(value)+' د.ع</strong></div>').join('')+'</div>'+profitStatementRows(rows,data.available);
}
