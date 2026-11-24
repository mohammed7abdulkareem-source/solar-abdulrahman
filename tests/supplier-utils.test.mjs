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
 assert.equal(matchesReceipt({id:1791112349592,receiptNo:349592,party:'مورد'},'#٣٤٩,٥٩٢'),true);
 assert.equal(matchesReceipt({id:1791112349592,receiptNo:349592,party:'مورد'},'349592'),true);
 assert.equal(matchesReceipt({id:1791112349592,receiptNo:123,party:'إبراهيم'},'ابراهيم'),true);
 assert.equal(matchesReceipt({id:1791112349592,receiptNo:123,party:'مورد'},'999'),false);
 assert.equal(moneyInput('١٬٠٠٠٫٥'),'1000.5');
});
test('payment receipt escapes user text and distinguishes an edited draft',()=>{
 const doc=supplierDocument({id:12,draft:true,party:'<script>alert(1)</script>',notes:'<b>note</b>',total:1000,date:'2026-10-01'});
 assert.match(doc.subtitle,/مسودة/);assert.match(doc.total,/1,000/);assert.ok(!doc.body.includes('<script>'));assert.match(doc.body,/&lt;b&gt;/);
});
test('saved receipts show the assigned number instead of internal timestamp IDs',()=>{
 const row={id:1791112349592,receiptNo:1,party:'مورد',total:1000,date:'2026-10-04'};
 const doc=supplierDocument(row);
 assert.match(doc.subtitle,/#1$/);assert.ok(!doc.body.includes('1791112349592'));
 assert.equal(matchesReceipt(row,'١'),true);
 assert.equal(matchesReceipt(row,'1791112349592'),false);
});

test('non-cash supplier additions increase debt and print as additions, not cash payments',()=>{
 const charge={id:7,receiptNo:3,kind:'supplier_payment',party:'مورد',total:-20000,cash:false,mode:'charge_old_balance',notes:'حساب قديم',date:'2026-10-04',beforeBalance:1100,afterBalance:21100};
 const ledger=supplierLedger([...rows,charge],supplier);assert.equal(ledger.balance,21100);
 const doc=supplierDocument(charge);assert.equal(doc.title,'وصل إضافة على حساب مورد');assert.match(doc.total,/20,000/);assert.ok(doc.body.includes('غير نقدية'));assert.ok(doc.body.includes('لا تخصم من القاصة'));assert.ok(doc.body.includes('21,100'));
});

test('supplier voucher pairs the cash paid, account credit and balances with their own currencies',()=>{
 const doc=supplierDocument({kind:'supplier_payment',id:17,receiptNo:52,party:'شركة المثال',date:'2026-11-24',
  cash:true,cashAmount:3243000,cashCurrency:'IQD',sourceSubtotal:1907.65,sourceCurrency:'USD',
  total:3243000,accountCurrency:'USD',accountAmount:1907.65,marketRate:1700,
  beforeBalance:1817625.97,afterBalance:1815718.32});
 const text=doc.body.replace(/<[^>]+>/g,' ').replace(/\s+/g,' ');
 assert.equal(doc.total,'3,243,000 د.ع');
 assert.match(text,/المدفوع من القاصة\s+3,243,000 د\.ع/);
 assert.match(text,/المبلغ بعملة حساب المورد\s+1,907\.65 \$/);
 assert.match(text,/1,700 د\.ع لكل دولار/);
 assert.match(text,/1,817,625\.97 \$/);
 assert.match(text,/1,815,718\.32 \$/);
});

test('legacy IQD totals do not become foreign cash or foreign account amounts',()=>{
 const doc=supplierDocument({kind:'supplier_payment',id:15,receiptNo:9,cash:true,sourceCurrency:'USD',
  accountCurrency:'USD',marketRate:1700,total:85000,party:'مورد قديم'});
 const text=doc.body.replace(/<[^>]+>/g,' ').replace(/\s+/g,' ');
 assert.equal(doc.total,'85,000 د.ع');
 assert.doesNotMatch(text,/85,000 \$/);
 assert.doesNotMatch(doc.body,/class="svBalances"/);
});

test('same-currency payment prints a recorded zero and an advance without a conversion panel',()=>{
 const doc=supplierDocument({kind:'supplier_payment',id:16,receiptNo:10,cash:true,cashCurrency:'USD',
  cashAmount:50,sourceCurrency:'USD',sourceSubtotal:50,accountCurrency:'USD',accountAmount:50,
  total:85000,marketRate:1700,beforeBalance:0,afterBalance:-50});
 const text=doc.body.replace(/<[^>]+>/g,' ').replace(/\s+/g,' ');
 assert.equal(doc.total,'50 $');
 assert.doesNotMatch(doc.body,/class="svConversion"/);
 assert.match(text,/الرصيد قبل الحركة\s+0 \$/);
 assert.match(text,/الرصيد بعد التسديد\s+-50 \$/);
});
