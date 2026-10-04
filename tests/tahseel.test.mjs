import test from 'node:test';
import assert from 'node:assert/strict';
import {newQuote,calculateQuote,quoteDocument,normalizeNumber} from '../app/tahseel-utils.mjs';
import {canOpenPage} from '../app/access-utils.mjs';
const complete=()=>({...newQuote(),panel:{id:1,name:'لوح 600W',cost:'100000'},battery:{id:2,name:'بطارية 15 كيلو',cost:'2000000'},inverter:{id:3,name:'انفيرتر 6kW',cost:'500000'}});
test('15×15: 7 panels, one battery, 465,000 expenses; 5% includes all costs',()=>{
 const q=calculateQuote(complete());
 assert.deepEqual([q.panelQty,q.batteryQty,q.materialsTotal,q.expensesTotal,q.cost,q.markup,q.price],[7,1,3200000,465000,3665000,183250,3848250]);
 assert.deepEqual(q.errors,[]);
});
test('quantities round UP without floating point error at a panel boundary',()=>{
 assert.equal(calculateQuote({...complete(),day:'15.05'}).panelQty,7);
 assert.equal(calculateQuote({...complete(),day:'15.06',night:'16'}).panelQty,8);
 assert.equal(calculateQuote({...complete(),night:'16'}).batteryQty,2);
});
test('zero night is allowed and has no battery cost, but an empty/invalid demand cannot be quoted',()=>{
 const q=calculateQuote({...complete(),night:'0',battery:null});assert.equal(q.batteryQty,0);assert.equal(q.materialsTotal,1200000);assert.equal(q.errors.length,0);
 for(const day of ['', '-1','NaN','Infinity','1001'])assert.ok(calculateQuote({...complete(),day}).errors.length);
 assert.ok(calculateQuote({...complete(),day:'0',night:'0'}).errors.length);
});
test('missing, negative or zero product cost cannot produce a final quotation',()=>{
 for(const cost of ['', '-1','0','Infinity'])assert.ok(calculateQuote({...complete(),panel:{name:'لوح',cost}}).errors.length);
 assert.throws(()=>quoteDocument(newQuote()));
});
test('editable expenses are counted and cannot be negative',()=>{
 const f=complete();f.expenses.crane='0';assert.equal(calculateQuote(f).expensesTotal,440000);
 f.expenses.crane='-1';assert.ok(calculateQuote(f).errors.length);
});
test('customer copy hides costs and markup, internal copy shows them; all free text escaped',()=>{
 const f=complete();f.customer='<script>alert(1)</script>';f.notes='<img src=x onerror=alert(1)>';f.panel.name='<b>panel</b>';
 const customer=quoteDocument(f),internal=quoteDocument(f,true);
 assert.ok(!customer.includes('<script>'));assert.ok(!customer.includes('<img'));assert.ok(customer.includes('&lt;b&gt;'));
 assert.ok(!customer.includes('183,250'));assert.ok(!customer.includes('2,000,000'));assert.ok(internal.includes('183,250'));assert.ok(internal.includes('2,000,000'));
});
test('Arabic decimal inputs normalize without changing value',()=>assert.equal(normalizeNumber('١٬٢٣٤٫٥'),'1234.5'));
test('quote permissions exclude engineers/warehouse/inactive and respect explicit false',()=>{
 const p={active:true,user_type:'admin_staff',permissions:{system:true}};
 assert.equal(canOpenPage(p,'tahseel'),true);
 assert.equal(canOpenPage({...p,permissions:{system:true,tahseel:false}},'tahseel'),false);
 assert.equal(canOpenPage({...p,permissions:{tahseel:true}},'tahseel'),true);
 for(const user_type of ['installer','warehouse'])assert.equal(canOpenPage({...p,user_type,is_admin:true},'tahseel'),false);
 assert.equal(canOpenPage({...p,active:false},'tahseel'),false);
});
