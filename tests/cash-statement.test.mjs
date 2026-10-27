import test from 'node:test';
import assert from 'node:assert/strict';
import {cashStatementDetails,cashStatementNotes,cashStatementDocument} from '../app/cash-statement-report.mjs';
import {a4} from '../app/document-template.mjs';
test('statement includes all notes, linked details and independent owner/currency tables, escaping user content',()=>{
 const row={id:'entry:1',created_at:'2026-10-02T10:00Z',kind:'installation_payout',delta:-2000000,balance:-1000000,note:'أحمد <script>alert(1)</script>',party:'عميل <x>',receipt_no:4,actor_name:'المسؤول',job_receipt:4,warehouse_name:'الرئيسي',transfer_note:'تم التسليم',expense_note:'أجرة نقل'};
 assert.equal(cashStatementNotes(row),'أحمد <script>alert(1)</script>\nتم التسليم\nأجرة نقل');assert.ok(cashStatementDetails(row).includes('وصل #4'));
 const data={asOf:'2026-10-27T10:00Z',from:'2026-10-01',to:'2026-10-31',ownerName:'جميع القاصات',count:1,ledgers:[{ownerId:'1',ownerName:'أحمد',currency:'IQD',opening:1000000,incoming:0,outgoing:2000000,closing:-1000000,rows:[row]},{ownerId:'2',ownerName:'سفيان',currency:'USD',opening:80.25,incoming:0,outgoing:0,closing:80.25,rows:[]}]};
 const html=cashStatementDocument(data,a4);assert.match(html,/01\/10\/2026/);assert.match(html,/31\/10\/2026/);assert.match(html,/1,000,000/);assert.match(html,/2,000,000/);assert.match(html,/80.25/);assert.equal((html.match(/<table class="cashStatementTable"/g)||[]).length,2);assert.match(html,/أجرة نقل/);assert.match(html,/تم التسليم/);assert.match(html,/&lt;script&gt;/);assert.ok(!html.includes('<script>alert'));assert.match(html,/المسؤول/);assert.match(html,/الرصيد السابق قبل بداية الفترة/);
});
