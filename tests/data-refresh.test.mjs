import test from 'node:test';
import assert from 'node:assert/strict';
import {createLatestLoader,refreshAfterSave} from '../app/data-refresh.mjs';
import {fullPaymentAmount} from '../app/payment-amount.mjs';
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};
test('concurrent cloud readers share one request, writes invalidate an older snapshot',async()=>{
 const reads=[];const load=createLatestLoader(uid=>{const d=deferred();reads.push({uid,...d});return d.promise;});
 const a=load('alice'),b=load('alice');assert.equal(reads.length,1);assert.equal(a,b);
 const write=load('alice',{fresh:true});reads[0].resolve('before');await Promise.resolve();assert.equal(reads.length,2);reads[1].resolve('after');assert.deepEqual(await Promise.all([a,b,write]),['after','after','after']);
 const next=load('alice');assert.equal(reads.length,3);reads[2].resolve('new');assert.equal(await next,'new');
});
test('different users do not share results and a failed refresh can be retried',async()=>{
 let calls=0;const load=createLatestLoader(async uid=>{if(++calls===1)throw Error('offline');return uid;});
 await assert.rejects(load('alice'));assert.equal(await load('bob'),'bob');assert.equal(await load('alice'),'alice');
});
test('background refresh failure is separate from committed saving',async()=>{
 const d=deferred();let failure;assert.equal(refreshAfterSave(()=>d.promise,e=>failure=e.message),undefined);d.reject(Error('refresh failed'));await new Promise(r=>setImmediate(r));assert.equal(failure,'refresh failed');
});
test('full payment preserves invoice/account limits, zero balances and USD cents',()=>{
 assert.equal(fullPaymentAmount(3707000),'3707000');assert.equal(fullPaymentAmount(Math.min(1000,250)),'250');assert.equal(fullPaymentAmount(0),'');assert.equal(fullPaymentAmount(-100),'');assert.equal(fullPaymentAmount(NaN),'');
 assert.equal(fullPaymentAmount(1000.25,'USD','USD',1660),'1000.25');assert.equal(fullPaymentAmount(1000.25,'USD','IQD',1660),'1660415');assert.equal(fullPaymentAmount(1660415,'IQD','USD',1660),'1000.25');assert.equal(fullPaymentAmount(100,'USD','IQD',0),'');
});

import {saveRequest} from '../app/save-request.mjs';
test('save deadline releases a stalled request as an unknown response without a database error code',async()=>{
 let signal;await assert.rejects(saveRequest(s=>{signal=s;return new Promise(()=>{});},10),e=>e.code===undefined&&e.message.includes('تأكيد'));assert.ok(signal.aborted);
 const result=await saveRequest(async()=>({data:{id:42},error:null}),100);assert.equal(result.data.id,42);
});

import {orderedSections,moveSection} from '../app/section-layout-utils.mjs';
test('saved layout order never introduces unauthorized sections and handles new sections',()=>{
 assert.deepEqual(orderedSections([['sale','بيع'],['stock','مخزن']],['users','stock','stock']).map(r=>r[0]),['stock','sale']);
 assert.deepEqual(moveSection(['sale','stock','cash'],'cash','sale'),['cash','sale','stock']);
 assert.deepEqual(moveSection(['sale','cash'],'unknown','sale'),['sale','cash']);
});
