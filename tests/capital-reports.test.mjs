import test from 'node:test';
import assert from 'node:assert/strict';
import {capitalAccounts,capitalStockReport,capitalCashReport,capitalDebtReport} from '../app/capital-reports.mjs';
import {cashRowsFor,cashBalance} from '../app/access-utils.mjs';

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
