import test from 'node:test';
import assert from 'node:assert/strict';
import {approvedExpenseValue,installationExpenseDifference,operatingExpenseAmount} from '../app/expense-review.mjs';
import {pendingSystemsDocument} from '../app/pending-systems-report.mjs';
test('cancelled approval stays zero even with an old engineer proposal',()=>{const job={installationExpenses:0,installationPaidExpenses:0,installationReport:{expenseTotal:479000}};assert.equal(approvedExpenseValue(job),'0');assert.equal(installationExpenseDifference(job,0),0);});
test('review shows only added expense or refund, excluding already paid amounts',()=>{const job={installationExpenses:479000,installationPaidExpenses:479000};assert.equal(installationExpenseDifference(job,479000),0);assert.equal(installationExpenseDifference(job,500000),21000);assert.equal(installationExpenseDifference(job,400000),-79000);assert.equal(installationExpenseDifference(job,0),-479000);});
test('handover refunds reduce operating expense without double counting installation payouts',()=>{assert.equal([{kind:'handover_expense',total:100,cashDelta:-100},{kind:'handover_expense',total:50,cashDelta:50},{kind:'installation_payout',total:479000,cashDelta:-479000},{kind:'installation_refund',total:479000,cashDelta:479000}].reduce((n,r)=>n+operatingExpenseAmount(r),0),50);});
test('pending report separates customer accounts from invoice profit and escapes labels',()=>{const doc=pendingSystemsDocument({summary:{count:1,accountCollections:200,provisionalProfit:300,paidExpenses:50},rows:[{receiptNo:4,customer:'<img onerror=alert(1)>',creatorName:'A & B',date:'2026-10-25T12:00Z',total:1000,approvedExpenses:50,provisionalProfit:300,status:'completed'}],accounts:[{customer:'<script>',openCount:1,receiptCount:1,collected:200,balance:800}]});assert.ok(!doc.body.includes('<img'));assert.ok(!doc.body.includes('<script>'));assert.ok(doc.body.includes('&lt;img'));assert.ok(doc.body.includes('مقبوضات حسابات العملاء'));assert.ok(doc.body.includes('الربح غير النهائي'));assert.ok(!doc.body.includes('غير موزعة'));assert.ok(!doc.body.includes('المقبوض المرتبط'));});
test('pending report distinguishes sale-period estimates from current account collections without changing amounts',()=>{
 const data={scope:'own',asOf:'2026-11-08T12:00:00Z',from:'2026-10-01',to:'2026-10-31',summary:{count:1,accountCollections:2000,provisionalProfit:300,paidExpenses:50},rows:[{receiptNo:4,customer:'عميل',creatorName:'مسؤول',date:'2026-10-25T12:00Z',total:1000,approvedExpenses:50,provisionalProfit:300,status:'completed'}],accounts:[{customer:'عميل',openCount:1,receiptCount:3,collected:2000,balance:-100}]},before=JSON.stringify(data);
 const report=pendingSystemsDocument(data);
 assert.match(report.body,/فترة بيع المنظومات: من 2026-10-01 إلى 2026-10-31/);assert.match(report.body,/عملة التقرير: الدينار العراقي · IQD/);
 assert.match(report.body,/توقيت بغداد/);assert.match(report.body,/ولا يمثل نقدًا متاحًا للتوزيع/);
 assert.match(report.body,/المقبوضات والرصيد حسب الحساب الحالي، وليسا مقصورين على فترة بيع المنظومات/);
 assert.ok(report.body.indexOf('٢. مقبوضات حسابات العملاء')>report.body.indexOf('</table>'));
 assert.match(report.body,/2,000 د\.ع/);assert.match(report.body,/300 د\.ع/);assert.match(report.body,/-100/);
 assert.match(report.body,/السالب رصيد للعميل عندنا/);assert.equal(JSON.stringify(data),before);
});
