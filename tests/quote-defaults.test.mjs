import test from 'node:test';
import assert from 'node:assert/strict';
import {newQuote,calculateQuote} from '../app/tahseel-utils.mjs';
import {QUOTE_EXPENSE_FIELDS,applyQuoteDefaults,quoteDefaultValues,quoteDefaultsError,quoteDefaultsAttempt} from '../app/quote-defaults-utils.mjs';
import {canManageQuoteDefaults} from '../app/access-utils.mjs';
test('requested expense amounts include per-panel cost and exactly one representative commission',()=>{
 const f={...newQuote(),day:'66.65',night:'0',inverter:{name:'8KW',cost:'500000'},panel:{name:'600W',cost:'100000'}};
 assert.equal(f.perPanel,'45000');assert.deepEqual(f.expenses,{crane:'40000',worker:'25000',programmer:'40000',delivery:'25000',electrical:'200000',commission:'75000'});
 const q=calculateQuote(f);assert.equal(q.panelQty,31);assert.equal(q.expenses[0].total,1395000);assert.equal(q.expensesTotal,1800000);assert.equal(q.expenses.find(x=>x.key==='commission').total,75000);assert.deepEqual(q.errors,[]);
 const legacy={...f,schema:4,perPanel:'30000',expenses:{crane:'25000',worker:'20000',programmer:'35000',delivery:'25000',electrical:'150000'}};
 assert.equal(calculateQuote(legacy).expensesTotal,1215000);assert.equal(calculateQuote(legacy).expenses.find(x=>x.key==='commission').total,0);
});
test('saved shared defaults apply to new quotes or an explicit adoption, preserving existing notes and quantities',()=>{
 const defaults={revision:2,perPanel:'50000',expenses:Object.fromEntries(QUOTE_EXPENSE_FIELDS.map(([key,,v])=>[key,String(v)]))};
 const f={...newQuote(),customer:'زبون',inverterQty:'3',notes:'ملاحظات محفوظة'};const before=JSON.stringify(f);const adopted=applyQuoteDefaults(f,defaults);
 assert.equal(JSON.stringify(f),before);assert.equal(adopted.customer,'زبون');assert.equal(adopted.inverterQty,'3');assert.equal(adopted.notes,f.notes);assert.equal(adopted.expenseDefaultsRevision,2);assert.equal(adopted.perPanel,'50000');assert.equal(newQuote(15,defaults).perPanel,'50000');
 assert.equal(quoteDefaultsError(quoteDefaultValues(adopted)),'');
 for(const value of['',-1,'NaN','Infinity','1.001',true,'10000000001'])assert.ok(quoteDefaultsError({...quoteDefaultValues(f),perPanel:value}),String(value));
 assert.equal(quoteDefaultsError({...quoteDefaultValues(f),perPanel:'0',expenses:{...f.expenses,commission:'0'}}),'');
});
test('pending shared-default saves persist exact request data and remain isolated by user',()=>{
 const memory=new Map(),storage={getItem:k=>memory.get(k),setItem:(k,v)=>memory.set(k,v),removeItem:k=>memory.delete(k)},a=quoteDefaultsAttempt(storage,'a'),b=quoteDefaultsAttempt(storage,'b'),request={id:'nonce',payload:{expectedRevision:1,...quoteDefaultValues(newQuote())}};
 a.write(request);assert.deepEqual(a.read(),request);assert.equal(b.read(),null);b.write({...request,id:'other'});a.clear();assert.equal(a.read(),null);assert.equal(b.read().id,'other');
});
test('global expense editing requires its own permission and full quote access within an active financial role',()=>{
 const p={active:true,user_type:'admin_staff',is_admin:false,permissions:{tahseel:true,tahseelFull:true}};
 assert.equal(canManageQuoteDefaults(p),false);assert.equal(canManageQuoteDefaults({...p,permissions:{...p.permissions,tahseelDefaults:true}}),true);assert.equal(canManageQuoteDefaults({...p,is_admin:true}),true);
 for(const changes of[{active:false},{user_type:'warehouse',is_admin:true},{user_type:'installer',is_admin:true},{permissions:{tahseel:true,tahseelDefaults:true}},{permissions:{tahseel:false,tahseelFull:true,tahseelDefaults:true}}])assert.equal(canManageQuoteDefaults({...p,...changes}),false);
});


test('new sizing is exact at decimal boundaries while untouched full snapshots retain their saved pricing rules',()=>{
 const old={...newQuote(),schema:4,day:'66.65',night:'0',inverter:{name:'8KW',cost:'500000'},panel:{name:'600W',cost:'100000'}};
 assert.equal(calculateQuote(old).panelQty,32);
 const fresh=applyQuoteDefaults(old,{revision:1,perPanel:'45000',expenses:newQuote().expenses});
 assert.equal(fresh.schema,5);assert.equal(calculateQuote(fresh).panelQty,31);assert.equal(calculateQuote(fresh).expensesTotal,1800000);assert.equal(old.schema,4);
});
