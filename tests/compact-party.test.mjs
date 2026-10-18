import test from 'node:test';
import assert from 'node:assert/strict';
import {customerAccount,supplierAccount,compactPeriod,compactStatementBody} from '../app/compact-party-utils.mjs';
test('customer summary separates opening, paid sales, debts and actual receipts',()=>{
 const a=customerAccount({id:1,name:'عميل',customerType:'wholesale',rows:[
  {id:1,date:'2026-10-01T09:00Z',mode:'opening_balance',kind:'customer_payment',total:-1000},
  {id:2,date:'2026-10-02T09:00Z',kind:'sale',total:500,cash:true},
  {id:3,date:'2026-10-03T09:00Z',kind:'sale',total:300,cash:false},
  {id:4,date:'2026-10-04T09:00Z',kind:'customer_payment',total:200},
  {id:5,date:'2026-10-05T09:00Z',kind:'customer_payment',mode:'charge_other',total:-50}
 ]});
 const p=compactPeriod(a.rows);assert.equal(p.balance,1150);assert.equal(p.invoices,800);assert.equal(p.payments,200);assert.equal(p.originalOpening,1000);
 const filtered=compactPeriod(a.rows,'2026-10-03','2026-10-05','payments');assert.equal(filtered.opening,1000);assert.equal(filtered.balance,1150);assert.equal(filtered.rows.length,1);assert.equal(filtered.rows[0].balance,1100);
 assert.equal(compactPeriod(a.rows,'','','other').rows.length,2);
});
test('supplier keeps revisions/currencies separate and cancellations preserve running balance',()=>{
 const data={revision:1,currency:'USD',rows:[
  {id:1,revision:0,currency:'IQD',created_at:'2026-10-01T00:00Z',delta:150000,entry_type:'opening'},
  {id:2,revision:1,currency:'USD',created_at:'2026-10-02T00:00Z',delta:100,note:'تحويل رصيد باتفاق جديد · اتفاق الدولار'},
  {id:3,revision:1,currency:'USD',created_at:'2026-10-03T00:00Z',delta:0,rate:1500,transaction:{id:11,kind:'purchase',account_amount:20,account_currency:'USD',total:30000,cash:true,source_currency:'USD',source_subtotal:20}},
  {id:4,revision:1,currency:'USD',created_at:'2026-10-04T00:00Z',delta:-10,rate:1500,transaction:{id:12,kind:'supplier_payment',account_amount:10,total:15000,cash:true,supplier_payment_voided_at:'2026-10-05T00:00Z'}},
  {id:5,revision:1,currency:'USD',created_at:'2026-10-05T00:00Z',delta:10,correction_for:4,note:'إلغاء التسديد'},
  {id:6,revision:1,currency:'USD',created_at:'2026-10-06T00:00Z',delta:-2.5,rate:1500,transaction:{id:13,kind:'supplier_payment',account_amount:2.5,total:3750,cash:true}}
 ]};
 const a=supplierAccount(data,'مورد'),p=compactPeriod(a.rows);assert.equal(a.currency,'USD');assert.equal(p.balance,97.5);assert.equal(p.invoices,20);assert.equal(p.payments,2.5);assert.equal(p.originalOpening,100);
 assert.equal(p.rows[2].voided,true);assert.equal(p.rows[3].balance,100);
 assert.equal(compactPeriod(a.rows,'','2026-10-04').payments,10);
 const old=supplierAccount(data,'مورد',[],0);assert.equal(old.currency,'IQD');assert.equal(compactPeriod(old.rows).balance,150000);
 const html=compactStatementBody(a,p,'','');assert.ok(html.includes('USD'));assert.ok(!html.includes('150,000'));
});
test('period uses Baghdad dates and keeps balances when text search hides rows',()=>{
 const rows=[{id:1,date:'2026-10-01T22:00:00Z',effect:100,amount:100,category:'invoices',label:'فاتورة',receiptNo:1},{id:2,date:'2026-10-02T00:00:00Z',effect:-10.25,amount:10.25,category:'payments',label:'تسديد',receiptNo:2}];
 const p=compactPeriod(rows,'2026-10-02','2026-10-02','all','2');assert.equal(p.rows.length,1);assert.equal(p.rows[0].balance,89.75);assert.equal(p.balance,89.75);
});
