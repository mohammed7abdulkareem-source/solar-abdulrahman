import test from 'node:test';
import assert from 'node:assert/strict';
import {supplierAccount,compactPeriod,compactStatementBody} from '../app/compact-party-utils.mjs';
import {cashKind} from '../app/cash-utils.mjs';
import {matchesCashType,cashTypeOptions} from '../app/cash-finance-utils.mjs';

test('cancelled purchase and reversal retain receipt context without becoming active invoices',()=>{
 const archivedPurchase={id:42,receiptNo:32,party:'مورد <تجربة>',notes:'ملاحظة أصلية',cancelledAt:'2026-11-05T12:00Z'};
 const account=supplierAccount({supplierId:1,revision:0,currency:'IQD',rows:[
  {id:1,revision:0,currency:'IQD',delta:560000,created_at:'2026-11-01T12:00Z',transaction:null,archivedPurchase:{...archivedPurchase,entryRole:'original'}},
  {id:2,revision:0,currency:'IQD',delta:-560000,created_at:'2026-11-05T12:00Z',transaction:null,correction_for:42,archivedPurchase:{...archivedPurchase,entryRole:'reversal'}}
 ]},'مورد');
 assert.deepEqual(account.rows.map(r=>r.receiptNo),[32,32]);
 assert.deepEqual(account.rows.map(r=>r.label),['شراء ملغى','إلغاء شراء']);
 assert.ok(account.rows.every(r=>r.original===null&&r.category==='adjustment'));
 assert.equal(compactPeriod(account.rows,'','','invoices').rows.length,0);
 assert.equal(compactPeriod(account.rows,'','2026-11-04').balance,560000);
 const all=compactPeriod(account.rows);assert.equal(all.balance,0);assert.equal(all.invoices,0);
 const html=compactStatementBody(account,all,'','');
 assert.match(html,/شراء ملغى #32/);assert.match(html,/مورد &lt;تجربة&gt;/);assert.match(html,/ملاحظة أصلية/);
});

test('purchase cancellation cash entries have Arabic names and separate type filters',()=>{
 assert.equal(cashKind('purchase_cancelled'),'شراء ملغى');
 assert.equal(cashKind('purchase_refund'),'استرجاع شراء ملغى');
 for(const kind of ['purchase_cancelled','purchase_refund']){
  assert.ok(cashTypeOptions.some(([value])=>value===kind));
  assert.ok(matchesCashType({kind},'expenses'));
  assert.ok(matchesCashType({kind},kind));
 }
 assert.equal(matchesCashType({kind:'purchase_refund'},'purchase_cancelled'),false);
});
