import test from 'node:test';
import assert from 'node:assert/strict';
import {capitalAccounts,capitalStockReport,capitalCashReport,capitalDebtReport} from '../app/capital-reports.mjs';
import {cashRowsFor,cashBalance} from '../app/access-utils.mjs';
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
test('cash report uses cash owner scope and explicit transfer deltas just like tile',()=>{
 const tx=[{id:1,date:'2026-10-01',kind:'cash_income',cash:true,total:1000,createdBy:'admin',cashboxUserId:'staff'},{id:2,date:'2026-10-02',kind:'transfer_out',cash:true,total:250,cashDelta:-250,createdBy:'staff'},{id:3,date:'2026-10-03',kind:'cash_income',cash:true,total:9999,createdBy:'other'}];
 const report=capitalCashReport(cashRowsFor(tx,'staff'));
 assert.equal(report.total,750);assert.equal(report.total,cashBalance(tx,'staff'));assert.doesNotMatch(report.body,/9,999/);
 assert.equal(capitalCashReport(cashRowsFor(tx,null,true)).total,cashBalance(tx,null,true));
});
test('stock report counts stocked products and preserves escaped names and brands',()=>{
 const report=capitalStockReport([{name:'بطارية',brand:'A&B',category:'بطارية',qty:2,cost:1500},{name:'فارغ',qty:0,cost:5000}]);
 assert.equal(report.total,3000);assert.match(report.body,/A&amp;B/);assert.doesNotMatch(report.body,/فارغ/);assert.match(capitalStockReport([]).body,/لا توجد بيانات/);
});
