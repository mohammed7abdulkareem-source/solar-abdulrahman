import {movementLabel,escapeHtml as e} from './warehouse-utils.mjs';
import {formatMoney} from './money-format.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
export const movementTime=value=>new Date(value).toLocaleString('en-GB',{timeZone:'Asia/Baghdad',hour12:false});
// Quantities are not money: a saved nonzero fraction must never display as 0.
// Format the decimal representation directly, retaining numeric-string precision.
export function materialQuantity(value){
 if(value==null||String(value).trim()==='')return '—';
 const text=String(value).trim(),match=/^([+-]?)(\d+)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/.exec(text);
 if(!match)return '—';
 const exponent=Number(match[4]||0);
 if(!Number.isFinite(exponent)||Math.abs(exponent)>100)return text;
 const digits=match[2]+(match[3]||''),point=match[2].length+exponent;
 let integer=point<=0?'0':point>=digits.length?digits+'0'.repeat(point-digits.length):digits.slice(0,point);
 let fraction=point<=0?'0'.repeat(-point)+digits:point>=digits.length?'':digits.slice(point);
 integer=integer.replace(/^0+(?=\d)/,'');fraction=fraction.replace(/0+$/,'');
 const sign=match[1]==='-'&&(integer!=='0'||fraction)?'−':'';
 return sign+integer.replace(/\B(?=(\d{3})+(?!\d))/g,',')+(fraction?'.'+fraction:'');
}
const quantity=materialQuantity;
export function materialSignedQuantity(row){
 const inQty=Number(row.inQty||0),outQty=Number(row.outQty||0);
 if(!Number.isFinite(inQty)||!Number.isFinite(outQty)||inQty<0||outQty<0)return {direction:'none',text:'—',inQty,outQty};
 const direction=inQty>0&&outQty>0?'mixed':inQty>0?'in':outQty>0?'out':'none';
 const text=direction==='mixed'?'+'+quantity(row.inQty)+' / −'+quantity(row.outQty):direction==='in'?'+'+quantity(row.inQty):direction==='out'?'−'+quantity(row.outQty):'0';
 return {direction,text,inQty,outQty};
}
export function materialLastVisibleBalances(rows){
 const last=new Map();
 for(const row of rows){const key=row.warehouseId!=null?'id:'+row.warehouseId:'name:'+String(row.warehouseName||'');last.set(key,{warehouseId:row.warehouseId??null,warehouseName:row.warehouseName||'غير محدد',balance:row.balance??null});}
 return [...last.values()];
}
export function filterMovementProducts(products,query=''){
 const words=normalizeSearch(query).split(/\s+/).filter(Boolean);
 return products.filter(product=>{const text=normalizeSearch([product.name,product.code,product.brand,product.category].join(' '));return words.every(word=>text.includes(word));});
}
export const materialSelectionLabel=product=>[product?.name,product?.brand,product?.category,product?.code].filter(Boolean).join(' · ');
// A finished response is usable only for the exact selected material and
// applied filters. Actor/permission isolation remains part of the caller key.
export function materialReportMatchesSelection(data,selection){
 if(!data||!selection||selection.productId==null||String(selection.productId)===''||data.product?.id==null||String(data.product.id)!==String(selection.productId))return false;
 if(!Array.isArray(data.rows)||!Array.isArray(data.warehouses))return false;
 if((data.from||'')!==(selection.from||'')||(data.to||'')!==(selection.to||'')||data.withPrices!==(selection.withPrices===true))return false;
 if(data.withPrices===true&&data.canShowPrices===false)return false;
 if(data.rows.some(row=>row.productId==null||String(row.productId)!==String(selection.productId)))return false;
 const warehouse=selection.warehouseId==null?'':String(selection.warehouseId);
 return !warehouse||(data.warehouses.length>0&&data.warehouses.every(item=>String(item.id)===warehouse)&&data.rows.every(row=>String(row.warehouseId)===warehouse));
}
export function materialMovementPresentation(row){
 const kind=row.kind,cancelledReservation=kind==='transfer_out'&&row.preparationStatus==='cancelled'&&!row.preparedAt,isReservation=kind==='transfer_reserved'||kind==='transfer_cancelled'||cancelledReservation;
 const label=cancelledReservation?'حجز نقل ملغى':{purchase:'شراء مواد',sale:'بيع جملة',system:'بيع منظومة',transfer_reserved:'حجز للنقل',transfer_cancelled:'إلغاء حجز النقل',transfer_out:'نقل صادر',transfer_in:'نقل وارد',transfer_return_in:'عكس نقل · إعادة للمصدر',transfer_return_out:'عكس نقل · سحب من الوجهة',stock_adjustment:'تسوية رصيد مخزني'}[kind]||movementLabel[kind]||kind||'حركة مخزنية';
 const partyLabel=kind==='purchase'?'المورّد':['sale','system'].includes(kind)?'العميل':['transfer_reserved','transfer_out','transfer_cancelled'].includes(kind)?'إلى مخزن':kind==='transfer_in'?'من مخزن':'الطرف';
 const preparationApplicable=['sale','system','transfer_reserved','transfer_cancelled','transfer_out','transfer_in','transfer_return_in','transfer_return_out'].includes(kind);
 const preparationLabel=preparationApplicable?({ready:'تم التجهيز',prepared:'تم التجهيز',pending:'بانتظار التجهيز',cancelled:'أُلغي النقل',reversed:'تم عكس النقل'}[row.preparationStatus]||(row.preparedAt?'تم تسجيل التجهيز':'لم يُسجّل تجهيز')):null;
 const stockNote=cancelledReservation?'حجز سابق أُلغي دون تجهيز؛ إعادة الكمية مثبتة بحركة إلغاء الحجز.':kind==='transfer_reserved'?'كمية محجوزة للنقل؛ تقلّل المتاح ولم تُجهّز بعد.':kind==='transfer_cancelled'?'إلغاء الحجز يعيد الكمية إلى المتاح.':kind==='transfer_out'?'خصم المصدر مثبت بتاريخ طلب النقل؛ وقت التجهيز موضح بصورة مستقلة.':['sale','system'].includes(kind)?'خصم البيع من المتاح يُثبت عند تسجيل الفاتورة؛ التجهيز حالة مستقلة.':'';
 return {label,partyLabel,preparerLabel:preparationApplicable?'مسؤول تجهيز المخزن':null,preparationApplicable,preparationLabel,isReservation,stockNote};
}
export function materialVisibleTotals(rows){
 // Only displayed quantity totals are summed here, never a running balance.
 // Decimal addition avoids exposing binary 0.1 + 0.2 artifacts after formatting.
 const sum=values=>{
  const parts=values.map(value=>/^(-?)(\d+)(?:\.(\d+))?$/.exec(quantity(value??0).replace(/,/g,'').replace('−','-')));
  if(parts.some(part=>!part))return values.reduce((total,value)=>total+Number(value||0),0);
  const scale=Math.max(0,...parts.map(part=>(part[3]||'').length));
  const total=parts.reduce((total,part)=>total+(part[1]?-1n:1n)*BigInt(part[2]+(part[3]||'').padEnd(scale,'0')),0n);
  const digits=(total<0n?-total:total).toString().padStart(scale+1,'0');
  return Number((total<0n?'-':'')+(scale?digits.slice(0,-scale)+'.'+digits.slice(-scale):digits));
 };
 return {in:sum(rows.map(row=>row.inQty)),out:sum(rows.map(row=>row.outQty)),count:rows.length,reservedOut:sum(rows.filter(row=>materialMovementPresentation(row).isReservation).map(row=>row.outQty)),reservationReleased:sum(rows.filter(row=>row.kind==='transfer_cancelled').map(row=>row.inQty))};
}
export function filterMaterialRows(rows,direction='all',query=''){
 const words=normalizeSearch(query).replace(/#/g,'').split(/\s+/).filter(Boolean);
 return rows.filter(r=>(direction==='all'||(direction==='in'?Number(r.inQty)>0:Number(r.outQty)>0))&&words.every(w=>normalizeSearch([r.party,r.receiptNo,r.note,r.warehouseName,r.createdByName,r.preparedByName,r.executedByName,movementLabel[r.kind],materialMovementPresentation(r).label].join(' ')).includes(w)));
}
export function materialPrice(row){
 const p=row.pricing;
 if(!p||!['system_total','transfer_cost','purchase','sale'].includes(p.kind))return {label:'لا يوجد سعر متاح لهذا المستند',unit:'—',total:'—'};
 if(p.kind==='system_total')return {label:'سعر المنظومة إجمالي؛ سعر المادة غير موزّع',unit:'—',total:'—'};
 return {label:p.kind==='transfer_cost'?'كلفة نقل مثبتة':p.kind==='purchase'?'سعر شراء مثبت':'سعر بيع مثبت',unit:p.unitPrice==null?'—':formatMoney(p.unitPrice)+' د.ع',total:p.lineTotal==null?'—':formatMoney(p.lineTotal)+' د.ع'};
}
export const materialReportPeriod=(from,to)=>{const date=value=>value?value.split('-').reverse().join('/'):'البداية';return from||to?date(from)+' — '+(to?date(to):'اليوم'):'جميع الفترات';};
const noteParts=value=>{const chars=Array.from(String(value||''));return Array.from({length:Math.ceil(chars.length/260)},(_,i)=>chars.slice(i*260,(i+1)*260).join(''));};
export function materialMovementDocument(data,rows,{direction='all',query=''}={}){
 if(!data)return '';
 const p=data.product,priced=data.withPrices===true,totals=materialVisibleTotals(rows),warehouses=data.warehouses||[],columns=priced?[14,15,10,13,24,9,15]:[16,18,12,28,10,16],lastBalances=materialLastVisibleBalances(rows);
 const number=value=>'<bdi>'+quantity(value)+'</bdi>';
 const css='<style>.materialLedgerReport{color:#18384b}.materialLedgerReport .mlReportHeading{border-inline-start:3px solid #18876e;background:#edf5f7;padding:7px 10px;margin:0 0 6px}.materialLedgerReport .mlReportHeading h2{font-size:16px;line-height:1.4;margin:0 0 3px;overflow-wrap:anywhere;color:#123e50}.materialLedgerReport .mlReportHeading p{font-size:10px;margin:0}.materialLedgerReport .mlReportMeta{font-size:10px;line-height:1.6;margin:5px 0 8px}.materialLedgerReport .mlReportMeta span{display:inline-block;margin-inline-end:12px}.materialLedgerReport table{table-layout:fixed;width:100%;font-size:10px;border:1px solid #9aafbd!important;margin:7px 0}.materialLedgerReport th{font-size:10px;padding:6px 3px;background:#e2edf4!important;color:#173b4f!important;font-weight:800!important;border:1px solid #acbcc7!important;line-height:1.5}.materialLedgerReport td{font-size:10px;line-height:1.55;padding:4px 3px;overflow-wrap:anywhere;border:1px solid #c2ced6!important;vertical-align:middle}.materialLedgerReport bdi{font-variant-numeric:tabular-nums;direction:ltr;unicode-bidi:isolate}.materialLedgerReport .mlReportMain td{font-size:10px}.materialLedgerReport .mlReportMain td small{display:block;font-size:9px;color:#526d7b;line-height:1.4}.materialLedgerReport .mlReportParty{text-align:start}.materialLedgerReport .mlReportDate{white-space:nowrap}.materialLedgerReport h3{font-size:12px;margin:11px 0 5px;color:#123e50}.materialLedgerReport p{font-size:10px;line-height:1.6}.materialLedgerReport .mlReportScope{padding:5px 7px;background:#edf6f3;border-inline-start:3px solid #16866b;margin:5px 0}.materialLedgerReport .mlReportIn,.materialLedgerReport .mlReportIn bdi{color:#086a50!important;font-weight:700!important}.materialLedgerReport .mlReportOut,.materialLedgerReport .mlReportOut bdi{color:#aa3538!important;font-weight:700!important}.materialLedgerReport .mlReportBalance{background:#dceef6!important;font-weight:800!important;color:#123e50!important}.materialLedgerReport .mlSignedQuantity{font-weight:800!important;white-space:nowrap}.materialLedgerReport .mlReportNote{white-space:pre-wrap;text-align:start;font-size:10px;color:#304e5e!important}.materialLedgerReport .mlReportReservation{color:#78520a!important}.materialLedgerReport tfoot td{background:#e9f4f0!important;border-top:2px solid #21846c!important;font-weight:800!important}.materialLedgerReport tfoot span{display:inline-block;margin-inline:10px}.materialLedgerReport tr:nth-child(even) td:not(.mlReportBalance){background:#f8fafb}.materialLedgerReport .mlReportCurrent{background:#e6f4ed!important}.materialLedgerReport .mlLastBalances{font-size:10px;padding:6px 8px;background:#edf5fb;border:1px solid #c2d6e3}.materialLedgerReport .mlLastBalances span{display:inline-block;margin-inline-end:14px;line-height:1.8}.materialLedgerReport .mlDetailReference{font-size:9px;line-height:1.6}.materialLedgerReport .mlDetailsTitle{margin-top:15px}.materialLedgerReport .mlDetailField{display:inline;line-height:1.7}.materialLedgerReport .mlDetailField+.mlDetailField:before{content:" · ";color:#7c919b}</style>';
 const heading='<div class="mlReportHeading"><h2>'+e(p.name)+'</h2><p><b>النوع:</b> '+e(p.category||'غير محدد')+' · <b>البراند:</b> '+e(p.brand||'غير محدد')+' · <b>الكود:</b> '+e(p.code||'—')+'</p></div>';
 const meta='<div class="mlReportMeta"><span><b>الفترة:</b> '+e(materialReportPeriod(data.from,data.to))+'</span><span>'+(priced?'بالأسعار المثبتة · دينار عراقي IQD':'بدون أسعار')+'</span><span><b>المخازن:</b> '+e(warehouses.map(w=>w.name).join(' · '))+'</span><span><b>المعروض:</b> '+e({all:'جميع الاتجاهات',in:'دخول فقط',out:'خروج فقط'}[direction]||'جميع الاتجاهات')+(query?' · البحث: '+e(query):'')+' · '+quantity(rows.length)+' حركة</span></div>';
 const bodyRows=rows.map(row=>{
  const price=priced?materialPrice(row):null,view=materialMovementPresentation(row),signed=materialSignedQuantity(row),date=new Date(row.date),day=date.toLocaleDateString('en-GB',{timeZone:'Asia/Baghdad'}),time=date.toLocaleTimeString('en-GB',{timeZone:'Asia/Baghdad',hour:'2-digit',minute:'2-digit',hour12:false});
  return '<tr data-movement-id="'+e(row.id)+'"><td class="mlReportDate"><bdi>'+e(day)+'</bdi><small><bdi>'+e(time)+'</bdi></small></td><td><b'+(view.isReservation?' class="mlReportReservation"':'')+'>'+e(view.label)+'</b></td><td class="mlSignedQuantity '+(signed.direction==='in'?'mlReportIn':signed.direction==='out'?'mlReportOut':'')+'"><bdi>'+e(signed.text)+'</bdi></td>'+(price?'<td>'+e(price.unit)+'</td>':'')+'<td class="mlReportParty"><b>'+e(view.partyLabel)+': '+e(row.party||'غير مسجل')+'</b><small>'+e(row.warehouseName||'غير محدد')+'</small></td><td><bdi>'+e(row.receiptNo??'—')+'</bdi></td><td class="mlReportBalance">'+number(row.balance)+'</td></tr>';
 }).join('');
 const movements='<table class="mlReportMain" data-pdf-paginate data-pdf-keep-footer-with-row><colgroup>'+columns.map(width=>'<col style="width:'+width+'%">').join('')+'</colgroup><thead><tr><th>التاريخ</th><th>نوع الحركة</th><th>الكمية + / −</th>'+(priced?'<th>سعر الوحدة د.ع</th>':'')+'<th>المورّد / العميل · المخزن</th><th>رقم الوصل</th><th>الرصيد بعد الحركة</th></tr></thead><tbody>'+bodyRows+(!rows.length?'<tr><td colspan="'+columns.length+'">لا توجد حركة مطابقة للفترة والبحث.</td></tr>':'')+'</tbody><tfoot><tr><td colspan="'+columns.length+'">مجاميع الحركات الظاهرة <span class="mlReportIn">إجمالي الداخل: '+number(totals.in)+'</span><span class="mlReportOut">إجمالي الخارج: '+number(totals.out)+'</span></td></tr></tfoot></table>';
 const last='<div class="mlLastBalances"><b>الرصيد بعد آخر حركة ظاهرة:</b> '+(lastBalances.length?lastBalances.map(w=>'<span data-last-warehouse="'+e(w.warehouseId??w.warehouseName)+'">'+e(w.warehouseName)+' '+number(w.balance)+'</span>').join(''):'لا توجد حركة ظاهرة؛ لا يُستنتج رصيد من مجاميع الدخول والخروج.')+'</div>';
 const summary='<h3>ملخص المخازن خلال الفترة · قبل البحث والاتجاه</h3><p>أرصدة أول وآخر حركة مسموحة ضمن الفترة، وليست رصيد بداية ونهاية التاريخ عند وجود حركات غير ظاهرة. المتاح حاليًا رصيد مستقل عن تاريخ نهاية الكشف.</p><table data-pdf-paginate class="mlReportWarehouseSummary"><colgroup>'+[24,16,12,12,16,20].map(width=>'<col style="width:'+width+'%">').join('')+'</colgroup><thead><tr><th>المخزن</th><th>قبل أول حركة بالفترة</th><th>دخول الفترة</th><th>خروج الفترة</th><th>بعد آخر حركة بالفترة</th><th>المتاح حاليًا</th></tr></thead><tbody>'+warehouses.map(w=>'<tr><td>'+e(w.name)+'</td><td>'+number(w.beforeFirst)+'</td><td class="mlReportIn">'+number(w.inQty)+'</td><td class="mlReportOut">'+number(w.outQty)+'</td><td class="mlReportBalance">'+number(w.afterLast)+'</td><td class="mlReportCurrent">'+number(w.currentQty)+'</td></tr>').join('')+'</tbody></table>';
 const detailRows=rows.map(row=>{
  const view=materialMovementPresentation(row),price=priced?materialPrice(row):null,fields=[];
  if(row.createdByName)fields.push('المستخدم: '+row.createdByName);
  if(row.executedByName&&row.executedByName!==row.createdByName)fields.push('منفّذ الحركة: '+row.executedByName);
  if(view.preparationApplicable){
   if(row.preparedByName)fields.push(view.preparerLabel+': '+row.preparedByName);
   if(row.preparationStatus)fields.push('حالة التجهيز: '+view.preparationLabel);
   if(row.preparedAt)fields.push('وقت التجهيز: '+movementTime(row.preparedAt));
  }
  if(price){fields.push(price.label);if(price.total!=='—')fields.push('مبلغ الفقرة: '+price.total);}
  const notes=noteParts(row.note),reference='<b>وصل #'+e(row.receiptNo??'—')+'</b><br>'+e(view.label)+'<br>'+e(row.warehouseName||'غير محدد')+'<br>'+e(movementTime(row.date));
  return (fields.length?'<tr data-detail-for="'+e(row.id)+'"><td class="mlDetailReference">'+reference+'</td><td class="mlReportNote">'+fields.map(field=>'<span class="mlDetailField">'+e(field)+'</span>').join('')+'</td></tr>':'')+notes.map((note,index)=>'<tr data-note-for="'+e(row.id)+'"><td class="mlDetailReference">'+(index?'تكملة البيان<br>':'البيان<br>')+reference+'</td><td class="mlReportNote">'+e(note)+'</td></tr>').join('');
 }).join('');
 const appendix=detailRows?'<h3 class="mlDetailsTitle">ملحق تفاصيل الحركات</h3><p>المستخدم ومسؤول التجهيز والبيان الكامل، بحسب البيانات المثبتة لكل وصل.</p><table class="mlReportDetails" data-pdf-paginate><colgroup><col style="width:26%"><col style="width:74%"></colgroup><thead><tr><th>مرجع الحركة</th><th>التفاصيل والبيان</th></tr></thead><tbody>'+detailRows+'</tbody></table>':'';
 const reservationSummary=totals.reservedOut||totals.reservationReleased?'<p>من ضمن المجاميع الظاهرة: حجز ضمن الخروج '+number(totals.reservedOut)+' · استعادة المتاح بإلغاء الحجز '+number(totals.reservationReleased)+'. هذه كميات تاريخية ظاهرة، وليست رصيد الحجوزات الحالي.</p>':'';
 const legend='<p>+ زيادة المتاح · − تخفيض المتاح. الرصيد بعد كل حركة هو القيمة المثبتة لمخزنها، ولا يعاد احتسابه عند البحث أو التصفية. لكل مخزن رصيد مستقل.</p><p>الحجز يقلّل المتاح قبل تجهيز النقل، وإلغاؤه يعيده؛ الدخول للوجهة يثبت بعد التجهيز. البيع يخصم المتاح عند تسجيل الفاتورة بصورة مستقلة عن التجهيز.</p>';
 return css+'<section class="materialLedgerReport">'+heading+meta+movements+last+legend+(data.scope==='own'?'<p class="mlReportScope">يعرض الكشف وصولاتك المسموحة فقط؛ الرصيد المخزني قد يتأثر بحركات مستخدمين آخرين لا تظهر تفاصيلها.</p>':'')+summary+reservationSummary+appendix+'</section>';
}
