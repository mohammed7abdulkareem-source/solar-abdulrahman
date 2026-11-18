import test from 'node:test';
import assert from 'node:assert/strict';
import {readProfitTargetAttempt,runProfitTargetAttempt} from '../app/profit-target-attempt.mjs';

const actor='00000000-0000-4000-8000-000000000001';
const owner='00000000-0000-4000-8000-000000000002';
const id='00000000-0000-4000-8000-000000000003';
const target={ownerId:owner,targetBalance:0,expectedToken:'reviewed-balance',note:'تصفية خارجية'};
function scenario(){
 const values=new Map();
 const options={
  store:{getItem:k=>values.get(k)??null,setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)},
  locks:null,makeId:()=>id,currentUser:async()=>actor
 };
 const call=(input,send,extra={})=>runProfitTargetAttempt(actor,input,{...options,send,...extra});
 const read=()=>readProfitTargetAttempt(actor,options.store);
 return {options,call,read};
}
const saved={id,ownerId:owner,before:-4275569.69,after:0,delta:4275569.69};

test('lost response and reload confirm the original signed target once, without permitting a different target or actor',async()=>{
 const {call,read,options}=scenario(),received=[];
 const lost=async attempt=>{received.push(attempt);throw new TypeError('network disconnected');};
 await assert.rejects(call(target,lost),/disconnected/);
 assert.deepEqual(read(),{id,actorId:actor,payload:target});
 assert.equal(readProfitTargetAttempt(owner,options.store),null);
 await assert.rejects(call({...target,targetBalance:-0.25},()=>assert.fail('sent new adjustment')),/السابقة/);
 const result=await call(null,async attempt=>{received.push(attempt);return {data:saved};});
 assert.deepEqual(result,saved);
 assert.deepEqual(received[0],received[1]);
 assert.equal(read(),null);
});

test('stale preview or denied actor discards rejected changes; a partial success response keeps the recovery reference',async()=>{
 for(const code of ['40001','42501','22023']){
  const {call,read}=scenario();
  await assert.rejects(call(target,async()=>({error:{code,message:'rollback'}})),e=>e.code===code);
  assert.equal(read(),null);
 }
 const {call,read}=scenario();
 for(const data of [null,{...saved,id:owner},{...saved,after:15},{...saved,delta:null}]){
  await assert.rejects(call(read()?null:target,async()=>({data})),/مطابق/);
  assert.equal(read().id,id);
 }
});

test('duplicate submission, switching accounts mid-save and unavailable storage never send an untracked replacement',async()=>{
 const {call,read}=scenario();
 let finish,started;
 const waiting=new Promise(r=>{started=r;});
 const sending=call(target,async()=>{started();return await new Promise(r=>{finish=r;});});
 await waiting;
 await assert.rejects(call(target,()=>assert.fail('duplicate send')),/قيد التأكيد/);
 finish({data:saved});await sending;
 let checks=0;
 await assert.rejects(call(target,async()=>({data:saved}),{currentUser:async()=>++checks===1?actor:owner}),/تغيّر الحساب/);
 assert.equal(read().id,id);
 await call(null,async()=>({data:saved}));
 await assert.rejects(call(target,()=>assert.fail('untracked write'),{store:null}),/مرجع التسوية/);
});

test('a negative fractional target is sent unchanged and a mismatched saved owner is rejected',async()=>{
 const {call,read}=scenario(),payload={...target,targetBalance:-984.25};
 const receipt={...saved,after:-984.25,delta:4274585.44};
 await assert.rejects(call(payload,async()=>({data:{...receipt,ownerId:actor}})),/مطابق/);
 assert.deepEqual(read().payload,payload);
 assert.deepEqual(await call(null,async attempt=>{
  assert.equal(attempt.payload.targetBalance,-984.25);return {data:receipt};
 }),receipt);
});
