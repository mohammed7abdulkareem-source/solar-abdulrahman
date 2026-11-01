import {QUOTE_EXPENSE_FIELDS,QUOTE_PANEL_EXPENSE,quoteExpenseValue,applyQuoteDefaults} from './quote-defaults-utils.mjs';
import {refreshMaterialBrands} from './current-brand.mjs';
// Commercial quotation rules supplied by the shop; not an electrical design model.
export const BATTERY_CAPACITIES = [5, 7.5, 10, 15, 25, 30];
// Older saved quotations used a fixed 15-kilo battery.
export const batteryCapacity = form => form.batteryCapacity ?? (form.schema === 1 ? '15' : '');
// Missing quantities in older drafts mean one inverter; an entered invalid
// quantity must remain invalid instead of silently reverting to one.
export const inverterQuantity = form => Object.hasOwn(form, 'inverterQty') ? form.inverterQty : '1';
export const MAX_INVERTERS = 1000;
export const FIXED_EXPENSES = QUOTE_EXPENSE_FIELDS;
export const money = value => Number(value).toLocaleString('en-US', {maximumFractionDigits: 2});
export const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const normalizeNumber = value => String(value ?? '').replace(/[٠-٩]/g, c => String('٠١٢٣٤٥٦٧٨٩'.indexOf(c))).replace(/[۰-۹]/g, c => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(c))).replace(/[,٬\s]/g, '').replace(/٫/g, '.');
export function newQuote(markupPercent=5, defaults=null) {
  const form={schema:5, markupPercent:String(markupPercent), customer:'', phone:'', day:'', night:'', batteryCapacity:'', inverterQty:'1', panel:null, battery:null, inverter:null,
    perPanel:String(QUOTE_PANEL_EXPENSE), expenses:Object.fromEntries(FIXED_EXPENSES.map(([key,,amount])=>[key,String(amount)])), notes:''};
  return defaults?.expenses?applyQuoteDefaults(form,defaults):form;
}
export function productSnapshot(product) {
  return {id:product.id, name:product.name, brand:product.brand || '', cost:Number(product.cost)>0?String(product.cost):''};
}
const valid = (value, max=1e10) => String(value).trim()!=='' && Number.isFinite(Number(value)) && Number(value)>=0 && Number(value)<=max;
const round = value => Math.round((value+Number.EPSILON)*100)/100;
// Keep decimal amp boundaries exact (66.65 A is exactly 31 panels).
function roundedUpRatio(value,numerator,denominator){
  const raw=String(value).trim(),m=raw.match(/^\+?(\d*)(?:\.(\d*))?(?:e([+-]?\d+))?$/i);
  if(!m||!m[1]&&!m[2])return Math.ceil(Number(value)*numerator/denominator);
  const fraction=m[2]||'',scale=fraction.length-Number(m[3]||0);
  if(Math.abs(scale)>60||raw.length>80)return Math.ceil(Number(value)*numerator/denominator);
  let units=BigInt((m[1]||'0')+fraction),divisor=BigInt(denominator);
  if(scale<0)units*=10n**BigInt(-scale);else divisor*=10n**BigInt(scale);
  return Number((units*BigInt(numerator)+divisor-1n)/divisor);
}
export function calculateQuote(form) {
  const errors=[];
  const exactSizing=Number(form.schema)>=5;
  if(!valid(form.day,1000)||!valid(form.night,1000)||Number(form.day)+Number(form.night)<=0) errors.push('أدخل الأمبير النهاري والليلي بشكل صحيح؛ يجب أن يكون أحدهما أكبر من صفر.');
  const panelQty=valid(form.day,1000)?exactSizing?roundedUpRatio(form.day,100,215):Math.ceil(Number(form.day)*100/215):0;
  const capacity=Number(batteryCapacity(form)), capacityValid=BATTERY_CAPACITIES.includes(capacity);
  if(valid(form.night,1000)&&Number(form.night)>0&&!capacityValid)errors.push('اختر سعة البطارية لحساب عدد البطاريات.');
  const batteryQty=valid(form.night,1000)&&capacityValid?exactSizing?roundedUpRatio(form.night,100,capacity*100):Math.ceil(Number(form.night)/capacity):0;
  const quantityValue=inverterQuantity(form),rawQty=String(quantityValue??''),qtyNumber=Number(rawQty);
  const qtyValid=['string','number'].includes(typeof quantityValue)&&rawQty.length<=40&&/^[0-9]+(?:\.[0-9]*)?$/.test(rawQty)&&Number.isInteger(qtyNumber)&&qtyNumber>=1&&qtyNumber<=MAX_INVERTERS;
  if(!qtyValid)errors.push('أدخل عدد الانفيرترات كعدد صحيح من 1 إلى 1000.');
  const inverterQty=qtyValid?qtyNumber:0;
  const materials=[['panel','ألواح 600W',panelQty],['battery','بطارية '+capacity+' كيلو',batteryQty],['inverter','انفيرتر',inverterQty]].map(([key,label,qty])=>{
    const item=form[key];
    if(qty&&(!item?.name||!valid(item.cost)||Number(item.cost)<=0))errors.push('اختر '+label+' وأدخل كلفة الوحدة أكبر من صفر.');
    return {key,label,qty,name:item?.name||label,brand:item?.brand||'',unitCost:valid(item?.cost)?Number(item.cost):0,total:round(qty*(valid(item?.cost)?Number(item.cost):0))};
  });
  if(!valid(form.perPanel))errors.push('أدخل مصروف اللوح بشكل صحيح.');
  const expenses=[{key:'panels',label:'مصاريف الألواح',qty:panelQty,unitCost:valid(form.perPanel)?Number(form.perPanel):0,total:round(panelQty*(valid(form.perPanel)?Number(form.perPanel):0))},...FIXED_EXPENSES.map(([key,label])=>{
    const v=quoteExpenseValue(form,key);if(!valid(v))errors.push('أدخل مصروف '+label+' بشكل صحيح.');
    return {key,label,qty:1,unitCost:valid(v)?Number(v):0,total:valid(v)?Number(v):0};
  })];
  const materialsTotal=round(materials.reduce((s,x)=>s+x.total,0)), expensesTotal=round(expenses.reduce((s,x)=>s+x.total,0));
  const markupPercent=form.markupPercent??'5';
  if(!valid(markupPercent,1000))errors.push('أدخل نسبة الربح من صفر إلى 1000%.');
  const cost=round(materialsTotal+expensesTotal), markup=round(cost*(valid(markupPercent,1000)?Number(markupPercent):0)/100), price=round(cost+markup);
  return {panelQty,batteryQty,inverterQty,batteryCapacity:capacityValid?capacity:null,materials,expenses,materialsTotal,expensesTotal,cost,markupPercent:Number(markupPercent),markup,price,errors};
}
export function quoteDocument(form, internal=false, calculated=null, products=[]) {
  const q=calculated||calculateQuote(form);if(q.errors.length)throw new Error(q.errors[0]);
  const e=escapeHtml;
  const materials=refreshMaterialBrands(q.materials.map(x=>({...x,id:form[x.key]?.id})),products);
  const rows=materials.filter(x=>x.qty).map(x=>'<tr><td>'+e(x.name)+'<br><small>'+e(x.brand)+(x.key==='battery'?' • '+e(x.label):'')+'</small></td><td>'+money(x.qty)+'</td>'+(internal?'<td>'+money(x.unitCost)+'</td><td>'+money(x.total)+'</td>':'')+'</tr>').join('');
  const details=internal?'<h3>المصاريف</h3><table><thead><tr><th>البيان</th><th>المبلغ — د.ع</th></tr></thead><tbody>'+q.expenses.map(x=>'<tr><td>'+e(x.label)+(x.key==='panels'?' ('+money(x.qty)+' × '+money(x.unitCost)+')':'')+'</td><td>'+money(x.total)+'</td></tr>').join('')+'</tbody></table><div class="meta"><div>كلفة المواد: '+money(q.materialsTotal)+' د.ع</div><div>المصاريف: '+money(q.expensesTotal)+' د.ع</div><div>الكلفة الكلية: '+money(q.cost)+' د.ع</div><div>إضافة '+money(q.markupPercent)+'%: '+money(q.markup)+' د.ع</div></div>':'<p>السعر يشمل المواد ومصاريف التجهيز والتنصيب المذكورة في العرض.</p>';
  return '<div class="meta"><div>الزبون: '+e(form.customer||'—')+'</div><div>الهاتف: '+e(form.phone||'—')+'</div><div>نهاري: '+e(form.day)+' أمبير</div><div>ليلي: '+e(form.night)+' أمبير</div></div><h3>مواد المنظومة</h3><table><thead><tr><th>المادة</th><th>العدد</th>'+(internal?'<th>كلفة الوحدة</th><th>الكلفة</th>':'')+'</tr></thead><tbody>'+rows+'</tbody></table>'+details+(form.notes?'<section class="notes"><h3>ملاحظات العرض</h3><p>'+e(form.notes).replace(/\n/g,'<br>')+'</p></section>':'')+'<p><small>عرض سعر تقديري حسب قاعدة احتساب المحل، وليس فاتورة بيع.</small></p>';
}
