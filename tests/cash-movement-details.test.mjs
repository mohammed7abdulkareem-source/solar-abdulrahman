import test from 'node:test';
import assert from 'node:assert/strict';
import {cashLedgerRows,cashMovementBody} from '../app/cash-movement-utils.mjs';
import {cashLedgerBody} from '../app/cash-utils.mjs';

test('a dual-currency reset has one boundary per owner and separate resets remain visible',()=>{
 const reset=(id,owner,currency)=>({id:id+owner+currency,owner_id:owner,ownerName:owner,currency,reconciliation:{id,mode:'zero',receiptNo:3,currency:'both'}});
 const source=[reset('second','A','IQD'),reset('first','A','USD'),reset('first','A','IQD'),reset('first','B','IQD'),{id:'adjustment',reconciliation:{id:'set',mode:'set'}}];
 const rows=cashLedgerRows(source);
 assert.deepEqual(rows.map(r=>r.showReset),[true,true,false,true,false]);
 assert.equal(source.some(r=>Object.hasOwn(r,'showReset')),false);
 // A second page containing the second currency still identifies the reset.
 assert.equal(cashLedgerRows([source[2]])[0].showReset,true);
});
test('cash exports preserve historical reset boundaries and escape notes and names',()=>{
 const html=cashLedgerBody({ownerId:'A',ownerName:'<قاصة>',summary:{},rows:[{id:'fx:1',owner_id:'A',ownerName:'<قاصة>',created_at:'2026-10-21T09:00:00Z',currency:'IQD',delta:-100,balance:999,kind:'cash_reconcile',note:'<script>x</script>',reconciliation:{id:'r',mode:'zero',receiptNo:1,currency:'IQD',afterIQD:0}}]},{});
 assert.match(html,/تصفير قاصة &lt;قاصة&gt;/);assert.match(html,/colspan="6"/);assert.doesNotMatch(html,/<script>/);assert.doesNotMatch(html,/>999<\/td>/);
});
test('movement documents show before/after, direction, transfer parties, and only supplied item fields',()=>{
 const html=cashMovementBody({currency:'IQD',ownerName:'مكتب',date:'2026-10-21T09:00:00Z',delta:-3000,amount:3000,before:10000,after:7000,note:'<رفض>',items:[],transfer:{sender:'صاحب القاصة',recipient:'الإدارة',amount:3000,expense:0,status:'accepted'}},'تحويل صادر');
 assert.match(html,/10,000/);assert.match(html,/7,000/);assert.match(html,/−3,000/);assert.match(html,/من صاحب القاصة إلى الإدارة/);assert.match(html,/تم الاستلام/);assert.match(html,/&lt;رفض&gt;/);
});
