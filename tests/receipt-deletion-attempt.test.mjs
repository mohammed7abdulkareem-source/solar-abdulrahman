import test from 'node:test';
import assert from 'node:assert/strict';
import {readDeletionAttempt,runDeletionAttempt} from '../app/receipt-deletion-attempt.mjs';
const row={id:'00000000-0000-0000-0000-000000000004',invoiceId:4,action:'delete_direct',token:'original',receiptNo:3,kind:'sale'};
const storage=()=>{const values=new Map();return {getItem:k=>values.get(k)||null,setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)};};
test('lost delete acknowledgement replays exact ID/token without re-reading the removed invoice',async()=>{
 const store=storage(),sent=[],options={store,currentUser:async()=>'owner',prepare:async()=>row,send:async r=>{sent.push(r);return {error:{message:'offline'}};}};
 await assert.rejects(runDeletionAttempt('owner',options));assert.equal(readDeletionAttempt('owner',store).id,row.id);
 const result=await runDeletionAttempt('owner',{...options,prepare:()=>assert.fail('deleted invoice context cannot be fetched'),send:async r=>{sent.push(r);return {data:{direct:true,status:'deleted'}};}});
 assert.equal(result.direct,true);assert.deepEqual(sent[0],sent[1]);assert.equal(readDeletionAttempt('owner',store),null);
});
test('definitive rollback permits a new context, and another account cannot replay the pending request',async()=>{
 const store=storage();await assert.rejects(runDeletionAttempt('owner',{store,currentUser:async()=>'owner',prepare:async()=>row,send:async()=>({error:{code:'PT409',message:'changed'}})}));assert.equal(readDeletionAttempt('owner',store),null);
 await assert.rejects(runDeletionAttempt('owner',{store,currentUser:async()=>'other',prepare:async()=>row,send:()=>assert.fail()}),/تغيّر الحساب/);assert.equal(readDeletionAttempt('other',store),null);assert.equal(readDeletionAttempt('owner',store).token,'original');
});
test('concurrent delete clicks serialize and storage failure prevents an unrecoverable request',async()=>{
 const store=storage();let release;const first=runDeletionAttempt('owner',{store,currentUser:async()=>'owner',prepare:async()=>row,send:()=>new Promise(r=>{release=r;})});await new Promise(r=>setTimeout(r,0));
 await assert.rejects(runDeletionAttempt('owner',{store}),/جاري تأكيد/);release({data:{status:'deleted'}});await first;
 await assert.rejects(runDeletionAttempt('owner',{store:{setItem(){throw new Error('storage full');},getItem:()=>null},prepare:async()=>row,send:()=>assert.fail()}),/storage full/);
});
test('switching accounts during a deletion response leaves the original result recoverable',async()=>{
 const store=storage();let actor='owner';
 await assert.rejects(runDeletionAttempt('owner',{store,currentUser:async()=>actor,prepare:async()=>row,send:async()=>{actor='other';return {data:{status:'deleted',direct:true}};}}),/تغيّر الحساب/);
 assert.equal(readDeletionAttempt('owner',store).id,row.id);assert.equal(readDeletionAttempt('other',store),null);
});
