import assert from 'node:assert/strict';
import {systemPaymentDocument} from '../app/system-payment-utils.mjs';
const receipt={party:'كوبا <كافي>',total:1500000,oldBalance:18000000,remaining:16500000,mode:'payment',date:'2026-10-17',notes:'بيد <المستلم>',receiptNo:7};
let doc=systemPaymentDocument(receipt);
assert.ok(doc.body.includes('الحساب العام / الرصيد الافتتاحي'));assert.ok(doc.body.includes('16,500,000'));assert.ok(doc.body.includes('كوبا &lt;كافي&gt;'));assert.ok(!doc.body.includes('بيد <المستلم>'));assert.equal(doc.total,'1,500,000 د.ع');
doc=systemPaymentDocument({...receipt,invoice:{id:1,receiptNo:3,items:[{name:'بطارية <اختبار>',qty:2}]},invoiceBefore:3000000,invoiceAfter:1500000});
assert.ok(doc.body.includes('المنظومة #3'));assert.ok(doc.body.includes('بطارية &lt;اختبار&gt;'));assert.ok(doc.body.includes('رصيد المنظومة بعد الحركة'));
doc=systemPaymentDocument({...receipt,total:-250000,mode:'charge_old_balance'});assert.ok(doc.body.includes('حركة غير نقدية'));assert.ok(doc.body.includes('حساب قديم'));assert.equal(doc.total,'250,000 د.ع');
