import test from 'node:test';
import assert from 'node:assert/strict';
import {systemPaymentDocument} from '../app/system-payment-utils.mjs';
import {a4} from '../app/document-template.mjs';
const receipt={receiptNo:36740,party:'عميل <اختبار>',date:'2026-10-21T22:00:00Z',total:5037000,oldBalance:18715000,remaining:13678000,notes:'ملاحظة <آمنة>\nسطر ثانٍ',creatorPhone:'07701234567',cashOwnerName:'صاحب الوصل'};
test('customer and system vouchers use their own saved balances, correct Baghdad date and escaped fields',()=>{
 for(const ledgerType of ['wholesale','system']){
  const doc=systemPaymentDocument({...receipt,ledgerType,currentBalance:999999});
  assert.equal(doc.title,'وصل قبض');assert.match(doc.body,/18,715,000/);assert.match(doc.body,/5,037,000/);assert.match(doc.body,/13,678,000/);assert.match(doc.body,/22\/10\/2026/);assert.match(doc.body,/عميل &lt;اختبار&gt;/);assert.doesNotMatch(doc.body,/<آمنة>|<اختبار>|999,999/);assert.match(doc.body,/التوقيع/);assert.match(doc.body,/07701234567/);assert.match(doc.body,/دينار عراقي/);assert.doesNotMatch(doc.body,/دولار/);
  const html=a4(doc.title,doc.body,doc.total,doc.subtitle);assert.match(html,/class="sheet receiptSheet"/);assert.match(html,/\.receiptPaid \.receiptBalanceValue\{color:#b42326/);
 }
});
test('zero account balances stay zero while absent historic balances are never invented',()=>{
 let d=systemPaymentDocument({...receipt,oldBalance:0,remaining:0});assert.doesNotMatch(d.body,/غير متوفر/);d=systemPaymentDocument({...receipt,oldBalance:null,remaining:undefined});assert.equal(d.body.match(/غير متوفر/g).length,2);
});
test('non-cash charges retain truthful wording and never become collection vouchers',()=>{
 const d=systemPaymentDocument({...receipt,total:-100,mode:'charge_other'});assert.doesNotMatch(d.body,/customerReceiptDocument|استلمت من السيد/);assert.match(d.body,/حركة غير نقدية/);assert.doesNotMatch(a4(d.title,d.body,d.total,d.subtitle),/class="sheet receiptSheet"/);
});
