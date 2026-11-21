import {phoneContactDocument} from './phone-contact-utils.mjs';
import {accountEffect} from './reconciliation-utils.mjs';
import {supplierEffect,money} from './supplier-utils.mjs';
import {escapeHtml as e} from './warehouse-utils.mjs';

const rounded=n=>Math.round((n+Number.EPSILON)*100)/100;
const metric=(label,value,unit='د.ع')=>'<div class="reportMetric"><span>'+e(label)+'</span><strong>'+money(value)+' '+unit+'</strong></div>';
const table=(headers,rows,widths=[],nowrapFirst=true)=>'<table data-pdf-paginate>'+(widths.length?'<colgroup>'+widths.map(w=>'<col style="width:'+w+'%">').join('')+'</colgroup>':'')+'<thead><tr>'+headers.map(h=>'<th>'+e(h)+'</th>').join('')+'</tr></thead><tbody>'+(rows.length?rows.map(cells=>'<tr>'+cells.map((c,i)=>'<td'+(nowrapFirst&&i===0?' style="white-space:nowrap"':'')+'>'+c+'</td>').join('')+'</tr>').join(''):'<tr><td colspan="'+headers.length+'">لا توجد بيانات</td></tr>')+'</tbody></table>';
export function capitalAccounts(tx,parties=[],supplier=false){
 const posted=new Set(tx.filter(t=>t.fxAccountEntry&&t.linkedTransaction!=null).map(t=>String(t.linkedTransaction)));
 const kinds=supplier?['purchase','supplier_payment','supplier_fx_book']:['sale','system','customer_payment','system_payment'];
 const accounts=new Map();
 for(const t of tx.filter(t=>kinds.includes(t.kind))){
  if(supplier&&!t.fxAccountEntry&&posted.has(String(t.id)))continue;
  const value=supplier?(t.fxAccountEntry?Number(t.total):supplierEffect(t)):accountEffect(t);if(!value)continue;
  const named=parties.filter(p=>p.name===t.party);
  const party=t.partyId?parties.find(p=>String(p.id)===String(t.partyId)):named.length===1?named[0]:null;
  const key=t.partyId?'id:'+t.partyId:party?'id:'+party.id:'name:'+(t.party||'غير محدد');
  const account=accounts.get(key)||{name:party?.name||t.party||'غير محدد',phone:party?.phone||'',balance:0};
  account.balance=rounded(account.balance+value);accounts.set(key,account);
 }
 const rows=[...accounts.values()].filter(r=>r.balance!==0).sort((a,b)=>b.balance-a.balance||a.name.localeCompare(b.name,'ar'));
 const net=rounded(rows.reduce((sum,r)=>sum+r.balance,0));
 return {rows,net,total:rounded(rows.reduce((sum,r)=>sum+Math.max(0,r.balance),0)),credit:rounded(rows.reduce((sum,r)=>sum+Math.max(0,-r.balance),0))};
}
export function capitalStockReport(products,personalPrices=false){
 const rows=products.map(p=>({...p,qty:p.bookQty??p.qty})).filter(p=>Number(p.qty)>0);
 const total=rows.reduce((sum,p)=>sum+Number(p.qty)*Number(p.cost??0),0);
 const title=personalPrices?'كشف المخزون بأسعار الجملة المحددة':'كشف المخزون بالكلفة';
 const unitLabel=personalPrices?'سعر الجملة د.ع':'كلفة الوحدة د.ع';
 const valueLabel=personalPrices?'القيمة بسعر الجملة د.ع':'القيمة الدفترية د.ع';
 const stockInfo=personalPrices?'تدخل في القيمة المواد التي لها سعر جملة محدد فقط.':'الكلفة هي الكلفة المثبتة للمواد.';
 return {title,total,body:'<div class="meta"><div>نطاق الكشف: المخزون المشمول في بيانات رأس المال</div><div>عملة الكشف: الدينار العراقي · IQD</div></div><div class="reportSummary">'+metric(personalPrices?'إجمالي قيمة المواد المسعّرة':'إجمالي قيمة المخزون الدفترية',total)+'</div><p>الكميات حسب الرصيد الدفتري، ويظل المخزون المحجوز ضمن الموجودات. '+stockInfo+'</p>'+
  table(['ت','الكود','المادة / البراند / الصنف','الكمية الدفترية',unitLabel,valueLabel],rows.map((p,i)=>[i+1,e(p.code),'<strong>'+e(p.name)+'</strong><br>'+e([p.brand,p.category].filter(Boolean).join(' • ')),money(p.qty),p.cost==null?'غير محدد':money(p.cost),p.cost==null?'—':money(Number(p.qty)*Number(p.cost))]),[7,10,28,10,21,24])+
  '<div data-pdf-end class="documentCounts">عدد الأصناف: '+rows.length+' • مجموع الكميات: '+money(rows.reduce((sum,p)=>sum+Number(p.qty),0))+'</div>'};
}
export function capitalDebtReport(accounts,supplier=false){
 const title=supplier?'كشف ديون الموردين علينا':'كشف ديون العملاء لنا';
 const currency=supplier&&accounts.rows.some(r=>r.currency);
 const creditOnly=accounts.rows.length>0&&accounts.rows.every(r=>r.balance<0),totalLabel=creditOnly?(supplier?'سلفنا لدى الموردين':'أرصدة العملاء الدائنة'):(supplier?'ديون الموردين علينا':'ديون العملاء لنا');
 return {title,total:accounts.total,body:'<div class="meta"><div>نطاق الكشف: حسابات '+(supplier?'الموردين':'العملاء')+' المشمولة في بيانات رأس المال</div><div>عملة المجاميع والقيمة الدفترية: الدينار العراقي · IQD</div></div><div class="reportSummary">'+metric(totalLabel,accounts.total)+metric('صافي أرصدة الحسابات',accounts.net)+'</div><p>'+(supplier?'الموجب مستحق للموردين، والسالب سلف وأرصدة لنا عندهم.':'الموجب مستحق لنا على العملاء، والسالب أرصدة للعملاء عندنا.')+(currency?' عمود «الرصيد بعملة الحساب» يعرض العملة الأصلية لكل حساب، وأعمدة الدينار والمجاميع تعرض القيمة الدفترية المثبتة.':'')+'</p>'+table(['ت',supplier?'المورد':'العميل','الهاتف',...(currency?['الرصيد بعملة الحساب']:[]),supplier?'علينا · دفتري د.ع':'لنا · دفتري د.ع',supplier?'لنا · دفتري د.ع':'للعميل · دفتري د.ع'],accounts.rows.map((r,i)=>[i+1,e(r.name),phoneContactDocument(r.phone),...(currency?[money(r.amount)+' '+(r.currency==='USD'?'$':'د.ع')]:[]),money(Math.max(0,r.balance)),money(Math.max(0,-r.balance))]),currency?[6,22,13,19,20,20]:[7,30,17,23,23])+'<div data-pdf-end class="notes">عدد الحسابات: '+accounts.rows.length+'<br>صافي الأرصدة بالقيمة الدفترية: '+money(accounts.net)+' د.ع</div>'};
}
export function capitalCashReport(snapshot,currency='IQD'){
 const {cash,scope}=snapshot;
 const dollar=currency==='USD', unit=dollar?'$':'د.ع';
 const balance=row=>Number(dollar?row.usd:row.iqd);
 const hasBalance=row=>balance(row)!==0||(dollar&&Number(row.usdBook)!==0);
 const allocations=cash.allocations.filter(hasBalance);
 const owners=allocations.filter(row=>row.kind==='owner');
 const pending=cash.pendingHandovers.filter(row=>row.currency===currency);
 const available=owners.reduce((sum,row)=>sum+balance(row),0);
 const held=allocations.find(row=>row.kind==='transit');
 const unassigned=allocations.find(row=>row.kind==='unassigned');
 const amount=value=>'<bdi dir="ltr">'+money(value,currency)+'</bdi>';
 const balanceRow=(label,row)=>[e(label),amount(balance(row)),...(dollar?[money(row.usdBook)]:[])];
 const cashboxes=owners.map(row=>balanceRow(row.ownerName,row));
 if(unassigned)cashboxes.push(balanceRow('رصيد غير مسند إلى قاصة مستخدم',unassigned));

 const summary=[metric('المتاح في قاصات المستخدمين',available,unit)];
 if(unassigned)summary.push(metric('رصيد غير مسند',balance(unassigned),unit));
 if(scope==='company'&&held)summary.push(metric('الرصيد قيد الاستلام',balance(held),unit));
 if(dollar)summary.push(metric('القيمة الدفترية بالدينار',cash.usdBook));

 const sections=[
  '<div class="meta"><div>'+ (scope==='company'?'قاصات الشركة':'قاصتي') +'</div><div>'+ (dollar?'الدولار الأمريكي · USD':'الدينار العراقي · IQD') +'</div></div>',
  '<div class="reportSummary">'+summary.join('')+'</div>',
  '<h3 class="reportSectionTitle">أرصدة القاصات الحالية</h3>',
  cashboxes.length?table(['صاحب القاصة','الرصيد الحالي · '+unit,...(dollar?['القيمة الدفترية · د.ع']:[])],cashboxes,dollar?[44,28,28]:[62,38],false):'<p>لا توجد قاصات برصيد حالي بهذه العملة.</p>'
 ];
 if(pending.length){
  const pendingTotal=pending.reduce((sum,row)=>sum+Number(row.amount),0);
  sections.push('<h3 class="reportSectionTitle">مبالغ قيد الاستلام</h3>',
   table(['من المستخدم','إلى المستخدم','المبلغ · '+unit],pending.map(row=>[e(row.senderName),e(row.recipientName),amount(row.amount)]),[34,34,32],false),
   '<p data-pdf-end>مجموع التسليمات بانتظار الاستلام <b>'+amount(pendingTotal)+' '+unit+'</b></p>');
  if(scope==='own')sections.push('<p>التسليمات المعلّقة معروضة للمتابعة. رصيد قاصتك يعرض المبلغ المتاح حالياً.</p>');
 }
 return {title:dollar?'كشف قاصة الدولار':'كشف الصندوق',total:dollar?cash.usdBook:cash.iqd,body:sections.join('')};
}
