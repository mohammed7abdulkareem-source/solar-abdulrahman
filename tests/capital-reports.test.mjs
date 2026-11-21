import test from 'node:test';
import assert from 'node:assert/strict';
import {capitalAccounts,capitalStockReport,capitalCashReport,capitalDebtReport} from '../app/capital-reports.mjs';
import {capitalSnapshotReport} from '../app/capital-snapshot-report.mjs';

test('different accounts retain gross debts and credits on both sides',()=>{
 const customer=capitalAccounts([{kind:'sale',partyId:1,total:100},{kind:'customer_payment',partyId:2,total:150}]);
 assert.equal(customer.total,100);assert.equal(customer.credit,150);assert.equal(customer.net,-50);
 const supplier=capitalAccounts([{kind:'purchase',partyId:1,total:100},{kind:'supplier_payment',partyId:2,total:150}],[],true);
 assert.equal(supplier.total,100);assert.equal(supplier.credit,150);assert.equal(supplier.net,-50);
});
test('capital PDF stays neutral for either sign without deficit commentary',()=>{
 const s={scope:'company',asOf:'2026-10-19T12:00:00Z',stock:{value:100},cash:{iqd:0,usdBook:0},customers:{receivable:0,advances:0},suppliers:{prepayments:0,payable:150},assets:100,liabilities:150,net:-50};
 const r=capitalSnapshotReport(s);assert.equal(r.total,-50);assert.match(r.body,/-50/);assert.doesNotMatch(r.body,/مصدر الفرق|عجز|أعلى من الموجودات|الأرصدة القديمة/);
 s.net=50;assert.equal(capitalSnapshotReport(s).total,50);
});

test('stock reserved for an unprepared transfer remains company inventory capital',()=>{
 const r=capitalStockReport([{name:'محجوز',qty:0,reservedQty:5,bookQty:5,cost:100},{name:'متاح',qty:3,reservedQty:2,bookQty:5,cost:200}]);
 assert.equal(r.total,1500);assert.match(r.body,/محجوز/);assert.match(r.body,/مجموع الكميات: 10/);
});

test('capital debt reports include opening/reconciliation and exclude settled cash invoices',()=>{
 const parties=[{id:1,name:'عميل <اختبار>',phone:'123'}];
 const tx=[{kind:'sale',partyId:1,total:1000},{kind:'sale',partyId:1,total:5000,cash:true},{kind:'customer_payment',party:'عميل <اختبار>',total:200},{kind:'customer_payment',partyId:1,mode:'opening_balance',total:-300},{kind:'customer_payment',partyId:1,mode:'account_reconciliation',total:100}];
 const accounts=capitalAccounts(tx,parties);
 assert.equal(accounts.rows.length,1);assert.equal(accounts.total,1000);
 const report=capitalDebtReport(accounts);assert.equal(report.total,1000);assert.match(report.body,/عميل &lt;اختبار&gt;/);assert.doesNotMatch(report.body,/عميل <اختبار>/);
 const suppliers=capitalAccounts([{kind:'purchase',party:'مجهز',total:1000},{kind:'purchase',party:'مجهز',total:5000,cash:true},{kind:'supplier_payment',party:'مجهز',total:200}],[],true);
 assert.equal(capitalDebtReport(suppliers,true).total,800);
 const credit=capitalAccounts([{kind:'customer_payment',party:'عميل',total:100}]);assert.equal(credit.total,0);assert.equal(credit.net,-100);assert.match(capitalDebtReport(credit).body,/-100/);
});
test('cash snapshot lists only current balances in the selected currency and names both parties to open handovers',()=>{
 const holder=(ownerName,iqd,usd=0,usdBook=0,kind='owner')=>({kind,ownerName,iqd,usd,usdBook});
 const cash={iqd:102,usd:2,usdBook:2900,allocations:[
  holder('قاصة <أحمد>',110),holder('علي',-10),holder('رصيد صفري',0),holder('دولار فقط',0,2,2900),holder('',2,0,0,'transit')],
  pendingHandovers:[{senderName:'مرسل <م>',recipientName:'مستلم & شريك',amount:2,currency:'IQD'}]};
 const company=capitalCashReport({scope:'company',cash});
 assert.equal(company.total,102);
 for(const text of ['قاصة &lt;أحمد&gt;','علي','-10','مرسل &lt;م&gt;','مستلم &amp; شريك','مبالغ قيد الاستلام'])assert.ok(company.body.includes(text),text);
 assert.match(company.body,/المتاح في قاصات المستخدمين<\/span><strong>100 د.ع/);
 assert.doesNotMatch(company.body,/رصيد صفري|دولار فقط|إجمالي الداخل|الرصيد بعد الحركة/);
 const usd=capitalCashReport({scope:'company',cash},'USD');
 assert.equal(usd.total,2900);assert.match(usd.body,/دولار فقط/);assert.match(usd.body,/2,900/);
 assert.doesNotMatch(usd.body,/مبالغ قيد الاستلام|علي|مرسل/);
 const own=capitalCashReport({scope:'own',cash:{...cash,iqd:0,allocations:[]}});
 assert.equal(own.total,0);assert.match(own.body,/لا توجد قاصات/);assert.match(own.body,/مستلم &amp; شريك/);
 assert.doesNotMatch(capitalCashReport({scope:'own',cash:{...cash,allocations:[],pendingHandovers:[]}}).body,/مبالغ قيد الاستلام/);
});
test('stock report counts stocked products and preserves escaped names and brands',()=>{
 const report=capitalStockReport([{name:'بطارية',brand:'A&B',category:'بطارية',qty:2,cost:1500},{name:'فارغ',qty:0,cost:5000}]);
 assert.equal(report.total,3000);assert.match(report.body,/A&amp;B/);assert.doesNotMatch(report.body,/فارغ/);assert.match(capitalStockReport([]).body,/لا توجد بيانات/);
});
test('capital snapshot explains scope and historical IQD value while retaining the original USD amount',()=>{
 const snapshot={scope:'own',asOf:'2026-11-08T12:00:00Z',stock:{value:100},cash:{iqd:0,usd:10,usdBook:15670},customers:{receivable:0,advances:0},suppliers:{prepayments:0,payable:100},assets:15770,liabilities:100,net:15670},before=JSON.stringify(snapshot);
 const report=capitalSnapshotReport(snapshot);
 assert.equal(report.total,15670);assert.match(report.body,/توقيت بغداد/);assert.match(report.body,/حركات المستخدم وقاصته والمخازن المسموحة له/);
 assert.doesNotMatch(report.body,/جميع حسابات الشركة/);assert.match(report.body,/الصافي · الموجودات − المطلوبات/);
 assert.match(report.body,/رصيد قاصة الدولار الأصلي: <b>10 USD/);assert.match(report.body,/قيمته الدفترية المدرجة أعلاه: <b>15,670 د\.ع/);
 assert.equal(JSON.stringify(snapshot),before);
});
test('supplier debt report labels source currency and IQD book value separately',()=>{
 const accounts={rows:[{name:'مورد',phone:'',currency:'USD',amount:100,balance:146000}],total:146000,net:146000};
 const report=capitalDebtReport(accounts,true);
 assert.equal(report.total,146000);assert.match(report.body,/100 \$/);assert.match(report.body,/146,000/);
 assert.match(report.body,/عملة المجاميع والقيمة الدفترية: الدينار العراقي · IQD/);
 assert.match(report.body,/يعرض العملة الأصلية لكل حساب/);assert.match(report.body,/الموجب مستحق للموردين، والسالب سلف وأرصدة لنا عندهم/);
});

test('personal stock report includes quantities for unpriced materials without treating the missing price as zero',()=>{
 const result=capitalStockReport([{name:'أ',qty:3,cost:40},{name:'ب',qty:5,cost:null}],true);
 assert.equal(result.total,120);
 assert.match(result.title,/بأسعار الجملة المحددة/);
 assert.match(result.body,/غير محدد/);
 assert.match(result.body,/مجموع الكميات: 8/);
 assert.doesNotMatch(result.body,/كلفة الوحدة/);
});
