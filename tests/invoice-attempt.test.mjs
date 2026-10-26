import test from 'node:test';
import assert from 'node:assert/strict';
import {saveInvoiceAttempt,resolveInvoiceAttempt,restoreInvoiceAttempt,clearInvoiceAttempt} from '../app/invoice-attempt.mjs';
const first={kind:'system',party:'زبون',total:4800000,valuationRevision:1,items:[{id:1,qty:9,price:0}]};
const uid='owner-A',nonce='00000000-0000-0000-0000-000000003760',next='00000000-0000-0000-0000-000000003761';
const storage=()=>{const values=new Map();return {getItem:k=>values.get(k)||null,setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k),values};};
const network={message:'Failed to fetch',code:''};
test('lost ACK survives reload and FX refresh; exact original envelope is replayed once',async()=>{
 const store=storage(),attempt={current:null},calls=[];let committed=0;
 const opts={storage:store,uuid:()=>nonce,currentUser:async()=>uid,resolve:()=>assert.fail('unchanged retry must replay'),send:async r=>{calls.push(structuredClone(r));if(calls.length===1){committed++;return {error:network};}return {data:{id:7,receiptNo:4}};}};
 await assert.rejects(saveInvoiceAttempt(attempt,uid,first,opts));assert.equal(store.values.size,1);
 const reloaded={current:null};restoreInvoiceAttempt(reloaded,uid,store);assert.equal(reloaded.current.requestId,nonce);
 const result=await saveInvoiceAttempt(reloaded,uid,{...first,valuationRevision:2},opts);
 assert.equal(result.id,7);assert.equal(committed,1);assert.deepEqual(calls[0].payload,calls[1].payload);assert.equal(calls[1].requestId,nonce);assert.equal(store.values.size,0);
});
test('changed input resolves and fences an absent attempt before sending a fresh nonce',async()=>{
 const store=storage(),attempt={current:null},order=[];
 await assert.rejects(saveInvoiceAttempt(attempt,uid,first,{storage:store,uuid:()=>nonce,send:async()=>({error:network})}));
 const result=await saveInvoiceAttempt(attempt,uid,{...first,total:4900000},{storage:store,uuid:()=>next,resolve:async r=>{order.push('cancel:'+r.requestId);assert.equal(r.payload.total,4800000);return {data:{state:'not_saved'}};},send:async r=>{order.push('save:'+r.requestId);assert.equal(r.payload.total,4900000);return {data:{id:8}};}});
 assert.equal(result.id,8);assert.deepEqual(order,['cancel:'+nonce,'save:'+next]);assert.equal(store.values.size,0);
});
test('a committed earlier invoice blocks changed input and exposes its receipt for explicit review',async()=>{
 const store=storage(),attempt={current:null};await assert.rejects(saveInvoiceAttempt(attempt,uid,first,{storage:store,uuid:()=>nonce,send:async()=>({error:network})}));
 await assert.rejects(saveInvoiceAttempt(attempt,uid,{...first,total:4900000},{storage:store,resolve:async()=>({data:{state:'saved',invoice:{id:7,receiptNo:4}}}),send:()=>assert.fail('must not create duplicate')}),e=>e.invoiceRecovery?.invoice?.receiptNo===4);
 assert.equal(attempt.current.requestId,nonce);assert.equal(store.values.size,1);clearInvoiceAttempt(attempt,uid,store);assert.equal(store.values.size,0);
});
test('lookup failure cannot erase an uncertain original, even with a structured API error',async()=>{
 const store=storage(),attempt={current:null};await assert.rejects(saveInvoiceAttempt(attempt,uid,first,{storage:store,uuid:()=>nonce,send:async()=>({error:network})}));
 await assert.rejects(saveInvoiceAttempt(attempt,uid,{...first,total:1},{storage:store,resolve:async()=>({error:{code:'42501',message:'lookup denied'}}),send:()=>assert.fail()}));assert.equal(attempt.current.requestId,nonce);assert.equal(store.values.size,1);
});
test('only definitive database rollback clears a failed save; transport errors remain recoverable',async()=>{
 for(const [code,retained]of [['P0002',false],['PT409',false],['PGRST000',true],['',true]]){
  const store=storage(),attempt={current:null};await assert.rejects(saveInvoiceAttempt(attempt,uid,first,{storage:store,uuid:()=>nonce,send:async()=>({error:{code,message:'failure'}})}));assert.equal(!!attempt.current,retained);assert.equal(store.values.size,retained?1:0);
 }
});
test('user switching cannot replay or expose another account pending payload',async()=>{
 const store=storage(),attempt={current:null};await assert.rejects(saveInvoiceAttempt(attempt,uid,first,{storage:store,uuid:()=>nonce,send:async()=>({error:network})}));
 assert.equal(restoreInvoiceAttempt(attempt,'owner-B',store),null);assert.equal(restoreInvoiceAttempt(attempt,uid,store).requestId,nonce);
 await assert.rejects(saveInvoiceAttempt(attempt,uid,first,{storage:store,currentUser:async()=>'owner-B',send:()=>assert.fail()}));assert.equal(store.values.size,1);
});
test('recovery is available without form/stock validation and serializes concurrent clicks',async()=>{
 const store=storage(),attempt={current:null};await assert.rejects(saveInvoiceAttempt(attempt,uid,first,{storage:store,uuid:()=>nonce,send:async()=>({error:network})}));let release;
 const running=resolveInvoiceAttempt(attempt,uid,{storage:store,resolve:()=>new Promise(r=>{release=r;})});await new Promise(r=>setTimeout(r,0));await assert.rejects(saveInvoiceAttempt(attempt,uid,first,{storage:store,send:()=>assert.fail()}),/جاري تأكيد/);release({data:{state:'not_saved'}});assert.equal((await running).state,'not_saved');assert.equal(attempt.current,null);
});
