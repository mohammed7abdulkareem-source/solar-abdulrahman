import test from 'node:test';
import assert from 'node:assert/strict';
import {customerMovementDocument,movementHtml,periodDocumentLabel} from '../app/customer-account-documents.mjs';
import {salesDocument} from '../app/sales-document.mjs';
import {systemPaymentDocument} from '../app/system-payment-utils.mjs';
import {a4} from '../app/document-template.mjs';
const account={id:1,name:'عميل <اختبار>',phone:'07800000000',type:'customer',currency:'IQD'};
const invoice={id:1,kind:'sale',receipt_no:7,created_at:'2026-10-21T09:00:00Z',party_name:account.name,total:300000,cash:false,creatorName:'المسؤول',creatorPhone:'07700000000',items:[{product_id:1,product_name:'انفيرتر <أصلي>',qty:2,price:150000}],warranty:{enabled:true,items:[{id:1,duration:1,unit:'years'}],maintenance:{duration:6,unit:'months'}},warranty_token:'11111111-1111-1111-1111-111111111111',invoice_account:{available:true,previousBalance:50000,invoiceTotal:300000,paidNow:0,balanceAfter:350000,lastPayment:{receiptNo:6,amount:20000,date:'2026-10-20T09:00:00Z'}}};
test('a statement invoice uses the exact original customer formatter with warranty, QR and fixed account',()=>{
 const d=customerMovementDocument({type:'invoice',invoice},account);
 assert.deepEqual(d,salesDocument({...invoice,customer_phone:account.phone},true));
 for(const s of ['انفيرتر &lt;أصلي&gt;','150,000','350,000','آخر تسديد سابق','20,000','invoiceQr','07700000000','07800000000'])assert.ok(d.body.includes(s),s);
 assert.equal(customerMovementDocument({type:'invoice',invoice:{...invoice,kind:'system'}},account).body.includes('سعر الوحدة'),false);
});
test('customer payment documents retain original balances and linked system material details',()=>{
 const receipt={id:2,receiptNo:8,party:account.name,ledgerType:'wholesale',date:'2026-10-21T09:00:00Z',total:100000,mode:'payment',oldBalance:350000,remaining:250000,notes:'بيد <صاحب الوصل>',creatorPhone:'07700000000'};
 assert.deepEqual(customerMovementDocument({type:'payment',receipt},account),systemPaymentDocument(receipt));
 const linked={...receipt,ledgerType:'system',invoice:{receiptNo:3,items:[{name:'بطارية',qty:2}]},invoiceBefore:350000,invoiceAfter:250000};
 const d=customerMovementDocument({type:'payment',receipt:linked},account);assert.match(d.body,/المنظومة #3/);assert.match(d.body,/بطارية/);assert.match(d.body,/250,000/);assert.doesNotMatch(d.body,/بيد <صاحب الوصل>/);
});
test('customer names in adjustment document headings are escaped before A4 composition',()=>{
 const html=movementHtml({type:'adjustment',movement:{id:3,label:'رصيد افتتاحي',receiptNo:2,date:'2026-10-21T09:00:00Z',amount:100,effect:100,balance:100,notes:'<نص>'}},account,a4);
 assert.match(html,/عميل &lt;اختبار&gt;/);assert.doesNotMatch(html,/عميل <اختبار>/);assert.match(html,/&lt;نص&gt;/);
 assert.equal(periodDocumentLabel('invoices'),'مبيعات الفترة');assert.equal(periodDocumentLabel('payments'),'تسديدات الفترة');
});
