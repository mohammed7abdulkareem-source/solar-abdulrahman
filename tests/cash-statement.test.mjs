import test from 'node:test';
import assert from 'node:assert/strict';
import {cashStatementDetails,cashStatementNotes,cashStatementDocument} from '../app/cash-statement-report.mjs';
import {a4} from '../app/document-template.mjs';
import {cashMovementBody} from '../app/cash-movement-utils.mjs';
test('statement includes all notes, linked details and independent owner/currency tables, escaping user content',()=>{
 const row={id:'entry:1',created_at:'2026-10-02T10:00Z',kind:'installation_payout',delta:-2000000,balance:-1000000,note:'أحمد <script>alert(1)</script>',party:'عميل <x>',receipt_no:4,actor_name:'المسؤول',job_receipt:4,warehouse_name:'الرئيسي',transfer_note:'تم التسليم',expense_note:'أجرة نقل'};
 assert.equal(cashStatementNotes(row),'أحمد <script>alert(1)</script>\nتم التسليم\nأجرة نقل');assert.ok(cashStatementDetails(row).includes('وصل #4'));
 const data={asOf:'2026-10-27T10:00Z',from:'2026-10-01',to:'2026-10-31',ownerName:'جميع القاصات',count:1,ledgers:[{ownerId:'1',ownerName:'أحمد',currency:'IQD',opening:1000000,incoming:0,outgoing:2000000,closing:-1000000,rows:[row]},{ownerId:'2',ownerName:'سفيان',currency:'USD',opening:80.25,incoming:0,outgoing:0,closing:80.25,rows:[]}]};
 const html=cashStatementDocument(data,a4);assert.match(html,/01\/10\/2026/);assert.match(html,/31\/10\/2026/);assert.match(html,/1,000,000/);assert.match(html,/2,000,000/);assert.match(html,/80.25/);assert.equal((html.match(/<table class="cashStatementTable"/g)||[]).length,2);assert.match(html,/أجرة نقل/);assert.match(html,/تم التسليم/);assert.match(html,/&lt;script&gt;/);assert.ok(!html.includes('<script>alert'));assert.match(html,/المسؤول/);assert.match(html,/الرصيد السابق قبل بداية الفترة/);
});

test('transfer statement and movement receipt distinguish names on an approved receipt and a direct handover',()=>{
 const row={kind:'transfer_in',date:'2026-11-27T11:30Z',ownerName:'قاصة الاستلام',currency:'IQD',
  delta:5000,amount:5000,before:1000,after:6000,actorName:'المعتمِد',actor_name:'المعتمِد',
  transfer:{sender:'موظف <أ>',recipient:'موظف ب',decidedBy:'المعتمِد',status:'accepted',amount:5000}};
 const details=cashStatementDetails(row);
 assert.ok(details.includes('من موظف <أ> إلى موظف ب'));
 assert.ok(details.includes('اعتمد الاستلام: المعتمِد'));
 assert.ok(!details.includes('المسجل: المعتمِد'));
 const html=cashMovementBody(row,'تحويل وارد');
 assert.ok(html.includes('من موظف &lt;أ&gt; إلى موظف ب')&&html.includes('اعتمد الاستلام: المعتمِد'));
 const direct={...row,kind:'admin_transfer_in',transfer:{...row.transfer,amount:25,currency:'USD'}};
 assert.ok(cashStatementDetails(direct).includes('نفّذ التحويل: المعتمِد'));
 assert.ok(cashStatementDetails(direct).includes('مبلغ التسليم: 25 $'));
 assert.ok(cashStatementDetails({...row,transfer:undefined,sender_name:'أ',recipient_name:'ب',transfer_status:'accepted',transfer_amount:25}).includes('مبلغ التسليم: 25 د.ع'));
 const redacted=cashMovementBody({...row,receiptRestricted:true},'تحويل وارد');
 assert.ok(redacted.includes('6,000')&&redacted.includes('أثر حسابي'));
 for(const hidden of ['المعتمِد','موظف','تحويل وارد']) assert.ok(!redacted.includes(hidden));
});

test('period statement prints a saved zero reconciliation balance even on tied timestamps',()=>{
 const row={id:'r',kind:'cash_reconcile',delta:-100,balance:999,reconciliation:{mode:'zero',afterIQD:0},created_at:'2026-11-27T11:30Z'};
 const data={asOf:row.created_at,from:'2026-11-27',to:'2026-11-27',ownerName:'قاصتي',count:1,
  ledgers:[{ownerName:'قاصتي',currency:'IQD',opening:100,incoming:0,outgoing:100,closing:0,rows:[row]}]};
 const html=cashStatementDocument(data,a4);
 assert.doesNotMatch(html,/>999</);
 assert.match(html,/class="cashStatementBalance [^"]*"><bdi[^>]*>0</);
});
