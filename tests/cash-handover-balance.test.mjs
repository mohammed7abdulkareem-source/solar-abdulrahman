import test from 'node:test';
import assert from 'node:assert/strict';
import {CASH_HANDOVER_BALANCE_MAX_AGE,cashHandoverBalanceKey,cashHandoverBalance,cashHandoverOwnerBalance,cashHandoverFullAmount} from '../app/cash-handover-balance.mjs';

const time=1780000000000;
const owners=[{id:'a',IQD:1275000.25,USD:'85.75'},{id:'b',IQD:-300000,USD:0}];
const key=cashHandoverBalanceKey('admin','a','IQD');
const snapshot={key,readAt:time,owners};

test('handover balances keep owner and currency separate, including negative and zero balances',()=>{
 assert.equal(cashHandoverBalance(snapshot,key,'a','IQD',time),1275000.25);
 assert.equal(cashHandoverOwnerBalance(owners,'a','USD'),85.75);
 assert.equal(cashHandoverOwnerBalance(owners,'b','IQD'),-300000);
 assert.equal(cashHandoverOwnerBalance(owners,'b','USD'),0);
 for(const changedKey of [cashHandoverBalanceKey('admin','b','IQD'),cashHandoverBalanceKey('admin','a','USD'),cashHandoverBalanceKey('other','a','IQD')])assert.equal(cashHandoverBalance(snapshot,changedKey,'a','IQD',time),null);
 assert.equal(cashHandoverOwnerBalance(owners,'missing','IQD'),null);
 assert.equal(cashHandoverOwnerBalance(owners,'a','all'),null);
});

test('unknown, failed, future, and expired balance reads cannot become a confirmed zero or fill amount',()=>{
 assert.equal(cashHandoverBalance(null,key,'a','IQD',time),null);
 assert.equal(cashHandoverBalance(snapshot,key,'a','IQD',time+CASH_HANDOVER_BALANCE_MAX_AGE-1),1275000.25);
 assert.equal(cashHandoverBalance(snapshot,key,'a','IQD',time+CASH_HANDOVER_BALANCE_MAX_AGE),null);
 assert.equal(cashHandoverBalance(snapshot,key,'a','IQD',time-1),null);
 for(const invalid of [undefined,null,'',' ',false,NaN,Infinity,'not money']){
  const invalidOwners=[{id:'a',IQD:invalid,USD:85.75}];
  assert.equal(cashHandoverOwnerBalance(invalidOwners,'a','IQD'),null);
  assert.equal(cashHandoverFullAmount(cashHandoverOwnerBalance(invalidOwners,'a','IQD')),null);
 }
});

test('full cashbox amount preserves cents and transfer bounds without rounding away a real balance',()=>{
 assert.equal(cashHandoverFullAmount(1275000.25),'1275000.25');
 assert.equal(cashHandoverFullAmount(85.75),'85.75');
 assert.equal(cashHandoverFullAmount(0.01),'0.01');
 assert.equal(cashHandoverFullAmount(1e12),'1000000000000');
 for(const unavailable of [null,undefined,0,-0.01,-300000,NaN,Infinity,1e12+1,1.001,'85.75'])assert.equal(cashHandoverFullAmount(unavailable),null);
 assert.deepEqual(snapshot,{key,readAt:time,owners:[{id:'a',IQD:1275000.25,USD:'85.75'},{id:'b',IQD:-300000,USD:0}]});
});
