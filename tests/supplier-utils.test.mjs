import test from 'node:test';
import assert from 'node:assert/strict';
import {supplierLedger,matchesReceipt,moneyInput,supplierDocument} from '../app/supplier-utils.mjs';
const supplier={id:9,name:'مورد'};
const rows=[
 {id:1,party:'مورد',kind:'purchase',total:1000,cash:false,date:'2026-09-30T09:00:00Z'},
 {id:2,party:'مورد',kind:'supplier_payment',total:200,date:'2026-10-01T09:00:00Z'},
 {id:3,party:'مورد',kind:'purchase',total:500,cash:true,date:'2026-10-02T09:00:00Z'},
 {id:4,party:'مورد',kind:'purchase',total:300,cash:false,date:'2026-10-03T09:00:00Z'},
 {id:5,party:'آخر',kind:'supplier_payment',total:999,date:'2026-10-03T09:00:00Z'},
];
test('supplier opening balance carries forward; cash purchase adds no debt',()=>{
 const result=supplierLedger(rows,supplier,'2026-10-01','2026-10-03');
 assert.equal(result.opening,1000);assert.equal(result.balance,1100);
 assert.deepEqual(result.rows.map(t=>t.balance),[800,800,1100]);
 const empty=supplierLedger(rows,supplier,'2026-10-04','2026-10-05');
 assert.equal(empty.opening,1100);assert.equal(empty.balance,1100);assert.equal(empty.rows.length,0);
});
test('supplier ID keeps renamed accounts together without matching a different ID',()=>{
 const result=supplierLedger([{...rows[0],party:'اسم سابق',partyId:9},{...rows[0],partyId:10}],supplier);
 assert.equal(result.balance,1000);assert.equal(result.rows.length,1);
});
test('dates follow Baghdad and supplier advances remain visible as negative balances',()=>{
 const result=supplierLedger([{...rows[1],total:100,date:'2026-09-30T22:00:00Z'}],supplier,'2026-10-01','2026-10-01');
 assert.equal(result.rows.length,1);assert.equal(result.balance,-100);
});
test('receipt search accepts Arabic digits, separators and receipt prefix',()=>{
 assert.equal(matchesReceipt({id:1791112349592,party:'مورد'},'#١,٧٩١,١١٢,٣٤٩,٥٩٢'),true);
 assert.equal(matchesReceipt({id:1791112349592,party:'مورد'},'349592'),true);
 assert.equal(matchesReceipt({id:123,party:'إبراهيم'},'ابراهيم'),true);
 assert.equal(matchesReceipt({id:123,party:'مورد'},'999'),false);
 assert.equal(moneyInput('١٬٠٠٠٫٥'),'1000.5');
});
test('payment receipt escapes user text and distinguishes an edited draft',()=>{
 const doc=supplierDocument({id:12,draft:true,party:'<script>alert(1)</script>',notes:'<b>note</b>',total:1000,date:'2026-10-01'});
 assert.match(doc.subtitle,/مسودة/);assert.match(doc.total,/1,000/);assert.ok(!doc.body.includes('<script>'));assert.match(doc.body,/&lt;b&gt;/);
});
