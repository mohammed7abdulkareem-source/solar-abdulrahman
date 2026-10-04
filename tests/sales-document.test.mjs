import test from 'node:test';
import assert from 'node:assert/strict';
import {salesDocument} from '../app/sales-document.mjs';
import {canOpenPage} from '../app/access-utils.mjs';
const row={id:123,kind:'system',party_name:'<script>alert(1)</script>',created_at:'2026-10-04T10:00:00Z',total:2000000,cost:1700000,expenses:12345,notes:'ملاحظة 777',installation_status:'completed',items:[{product_name:'لوح',qty:12,price:80000,cost:70000}]};
test('warehouse copy includes quantities but no sale prices, totals, costs or financial notes',()=>{
 for(const kind of ['system','sale']){
  const d=salesDocument({...row,kind},false);
  assert.equal(d.total,'');assert.match(d.body,/لوح/);
  for(const value of ['2,000,000','1,700,000','80,000','70,000','12,345','777'])assert.ok(!d.body.includes(value));
  assert.ok(!d.body.includes('<script>'));
 }
});
test('customer system copy shows system total without exposing material costs',()=>{
 const d=salesDocument(row,true);assert.equal(d.total,'2,000,000 د.ع');assert.ok(!d.body.includes('70,000'));
 assert.ok(d.body.includes('&lt;script&gt;'));
});
test('wholesale customer copy uses saved selling prices',()=>{
 const d=salesDocument({...row,kind:'sale'},true);assert.match(d.body,/80,000/);assert.match(d.body,/960,000/);
});
test('closing-all grants workflow and history only, engineers remain blocked from history',()=>{
 const p={active:true,user_type:'admin_staff',permissions:{installationsAll:true}};
 assert.equal(canOpenPage(p,'installations'),true);assert.equal(canOpenPage(p,'salesHistory'),true);
 assert.equal(canOpenPage(p,'cash'),false);assert.equal(canOpenPage(p,'sale'),false);
 assert.equal(canOpenPage({...p,user_type:'installer'},'salesHistory'),false);
});
