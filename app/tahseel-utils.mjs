import {QUOTE_EXPENSE_FIELDS,QUOTE_PANEL_EXPENSE,quoteExpenseValue,applyQuoteDefaults} from './quote-defaults-utils.mjs';
import {refreshMaterialBrands} from './current-brand.mjs';
import {iconSvg} from './ui-icons.mjs';
import {quotationDemandArt,quotationProductArt} from './quotation-art.mjs';
// Commercial quotation rules supplied by the shop; not an electrical design model.
export const BATTERY_CAPACITIES = [5, 7.5, 10, 15, 25, 30];
// Older saved quotations used a fixed 15-kilo battery.
export const batteryCapacity = form => form.batteryCapacity ?? (form.schema === 1 ? '15' : '');
// Missing quantities in older drafts mean one inverter; an entered invalid
// quantity must remain invalid instead of silently reverting to one.
export const inverterQuantity = form => Object.hasOwn(form, 'inverterQty') ? form.inverterQty : '1';
export const allInOneQuantity = form => Object.hasOwn(form, 'allInOneQty') ? form.allInOneQty : '1';
export const MAX_INVERTERS = 1000;
export const FIXED_EXPENSES = QUOTE_EXPENSE_FIELDS;
export const money = value => Number(value).toLocaleString('en-US', {maximumFractionDigits: 2});
export const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const normalizeNumber = value => String(value ?? '').replace(/[٠-٩]/g, c => String('٠١٢٣٤٥٦٧٨٩'.indexOf(c))).replace(/[۰-۹]/g, c => String('۰۱۲۳۴۵۶۷۸۹'.indexOf(c))).replace(/[,٬\s]/g, '').replace(/٫/g, '.');
export function newQuote(markupPercent=5, defaults=null) {
  const form={schema:5, systemType:'standard', markupPercent:String(markupPercent), customer:'', phone:'', day:'', night:'', batteryCapacity:'', inverterQty:'1', allInOneQty:'1', allInOnePanelQty:'', panel:null, battery:null, inverter:null, allInOne:null,
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
  const allInOne=form.systemType==='all_in_one';
  const exactSizing=Number(form.schema)>=5;
  const manualPanels=allInOne&&String(form.allInOnePanelQty??'').trim()!=='';
  const panelText=String(form.allInOnePanelQty??''),panelNumber=Number(panelText);
  const manualPanelsValid=manualPanels&&['string','number'].includes(typeof form.allInOnePanelQty)&&panelText.length<=40&&/^[0-9]+(?:\.[0-9]*)?$/.test(panelText)&&Number.isInteger(panelNumber)&&panelNumber>=1&&panelNumber<=1000;
  if(manualPanels){
    if(!manualPanelsValid)errors.push('أدخل عدد الألواح كعدد صحيح من 1 إلى 1000.');
    if((String(form.day??'').trim()!==''&&!valid(form.day,1000))||(String(form.night??'').trim()!==''&&!valid(form.night,1000)))errors.push('أدخل الأمبير النهاري والليلي بشكل صحيح.');
  }else if(allInOne){
    const dayText=String(form.day??'').trim(),nightText=String(form.night??'').trim();
    if((dayText!==''&&!valid(form.day,1000))||(nightText!==''&&!valid(form.night,1000))||Number(dayText||0)+Number(nightText||0)<=0)errors.push('أدخل الأمبير النهاري أو الليلي بشكل صحيح، أو حدّد عدد الألواح.');
  }else if(!valid(form.day,1000)||!valid(form.night,1000)||Number(form.day)+Number(form.night)<=0) errors.push('أدخل الأمبير النهاري والليلي بشكل صحيح؛ يجب أن يكون أحدهما أكبر من صفر.');
  const panelQty=manualPanels?(manualPanelsValid?panelNumber:0):valid(form.day,1000)?exactSizing?roundedUpRatio(form.day,100,215):Math.ceil(Number(form.day)*100/215):0;
  const capacity=Number(batteryCapacity(form)), capacityValid=BATTERY_CAPACITIES.includes(capacity);
  if(!allInOne&&valid(form.night,1000)&&Number(form.night)>0&&!capacityValid)errors.push('اختر سعة البطارية لحساب عدد البطاريات.');
  const batteryQty=!allInOne&&valid(form.night,1000)&&capacityValid?exactSizing?roundedUpRatio(form.night,100,capacity*100):Math.ceil(Number(form.night)/capacity):0;
  const quantityValue=allInOne?allInOneQuantity(form):inverterQuantity(form),rawQty=String(quantityValue??''),qtyNumber=Number(rawQty);
  const qtyValid=['string','number'].includes(typeof quantityValue)&&rawQty.length<=40&&/^[0-9]+(?:\.[0-9]*)?$/.test(rawQty)&&Number.isInteger(qtyNumber)&&qtyNumber>=1&&qtyNumber<=MAX_INVERTERS;
  if(!qtyValid)errors.push(allInOne?'أدخل عدد أجهزة ALL IN ONE كعدد صحيح من 1 إلى 1000.':'أدخل عدد الانفيرترات كعدد صحيح من 1 إلى 1000.');
  const inverterQty=!allInOne&&qtyValid?qtyNumber:0,allInOneQty=allInOne&&qtyValid?qtyNumber:0;
  const materialRows=allInOne?[['panel','ألواح 600W',panelQty],['allInOne','جهاز ALL IN ONE',allInOneQty]]:[['panel','ألواح 600W',panelQty],['battery','بطارية '+capacity+' كيلو',batteryQty],['inverter','انفيرتر',inverterQty]];
  const materials=materialRows.map(([key,label,qty])=>{
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
  return {panelQty,batteryQty,inverterQty,allInOneQty,batteryCapacity:!allInOne&&capacityValid?capacity:null,materials,expenses,materialsTotal,expensesTotal,cost,markupPercent:Number(markupPercent),markup,price,errors};
}
export function quoteDocument(form, internal=false, calculated=null, products=[]) {
  const q=calculated||calculateQuote(form);if(q.errors.length)throw new Error(q.errors[0]);
  const e=escapeHtml;
  const materials=refreshMaterialBrands(q.materials.map(x=>({...x,id:form[x.key]?.id})),products);
  const rows=materials.filter(x=>x.qty).map(x=>'<tr><td><div class="quoteProduct"><span class="quoteProductArt">'+quotationProductArt(x.key)+'</span><div class="quoteProductText"><bdi>'+e(x.name)+'</bdi><small>'+e(x.brand)+(x.key==='battery'?' • '+e(x.label):'')+'</small></div></div></td><td>'+money(x.qty)+'</td>'+(internal?'<td>'+money(x.unitCost)+'</td><td>'+money(x.total)+'</td>':'')+'</tr>').join('');
  const details=internal?'<section class="quoteInternalCosts"><h3 class="quoteInternalHeading">'+iconSvg('coins')+'المصاريف</h3><table class="quoteExpenseTable"><thead><tr><th>البيان</th><th>المبلغ — د.ع</th></tr></thead><tbody>'+q.expenses.map(x=>'<tr><td>'+e(x.label)+(x.key==='panels'?' ('+money(x.qty)+' × '+money(x.unitCost)+')':'')+'</td><td>'+money(x.total)+'</td></tr>').join('')+'</tbody></table></section><div class="quoteCostSummary"><div><span>كلفة المواد</span><b>'+money(q.materialsTotal)+' د.ع</b></div><div><span>المصاريف</span><b>'+money(q.expensesTotal)+' د.ع</b></div><div><span>الكلفة الكلية</span><b>'+money(q.cost)+' د.ع</b></div><div><span>إضافة '+money(q.markupPercent)+'%</span><b>'+money(q.markup)+' د.ع</b></div></div>':'';
  return '<section class="quoteDocument'+(internal?' quoteInternalDocument':'')+'"><div class="quoteCustomer"><div><span class="quoteCustomerIcon">'+iconSvg('user')+'</span><span>الزبون: '+e(form.customer||'—')+'</span></div><div><span class="quoteCustomerIcon">'+iconSvg('phone')+'</span><span>الهاتف: <bdi>'+e(form.phone||'—')+'</bdi></span></div></div><div class="quoteDemandCards"><div class="quoteDemandCard quoteDay">'+quotationDemandArt()+'<div><h3>نهاري</h3><strong><bdi>'+e(form.day==null||String(form.day).trim()===''?'—':form.day)+'</bdi></strong><span>أمبير</span></div></div><div class="quoteDemandCard quoteNight">'+quotationDemandArt(true)+'<div><h3>ليلي</h3><strong><bdi>'+e(form.night==null||String(form.night).trim()===''?'—':form.night)+'</bdi></strong><span>أمبير</span></div></div></div><section class="quoteMaterials"><h3>'+iconSvg('package')+'مواد المنظومة</h3><table><thead><tr><th class="quoteMaterialTitle">'+iconSvg('package')+'المادة</th><th>'+iconSvg('receipt')+'العدد</th>'+(internal?'<th>كلفة الوحدة</th><th>الكلفة</th>':'')+'</tr></thead><tbody>'+rows+'</tbody></table></section>'+details+'<section class="notes"><h3>'+iconSvg('document')+'ملاحظات العرض</h3><p>السعر يشمل المواد ومصاريف التجهيز والتنصيب المذكورة في العرض.</p><p>عرض سعر تقديري حسب قاعدة احتساب المحل، وليس فاتورة بيع.</p>'+(form.notes?'<p class="quoteUserNotes">'+e(form.notes).replace(/\n/g,'<br>')+'</p>':'')+'</section></section>';
}
