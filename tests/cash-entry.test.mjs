import test from 'node:test';
import assert from 'node:assert/strict';
import {cashEntryProblem,cashProjection} from '../app/cash-entry-utils.mjs';
const base={ownerId:'owner',mode:'expense',currency:'IQD',amount:'1000',rate:'1500',note:'نقل بضاعة',iqd:10000,usd:20.5};
test('cash validation explains missing amounts, notes and insufficient funds',()=>{
 assert.match(cashEntryProblem({...base,amount:''}),/مبلغاً أكبر/);
 assert.match(cashEntryProblem({...base,note:' '}),/بيان الحركة/);
 assert.match(cashEntryProblem({...base,amount:'10001'}),/لا يكفي/);
 assert.match(cashEntryProblem({...base,currency:'USD',amount:'1.01',rate:''}),/سعر صرف/);
 assert.equal(cashEntryProblem({...base,currency:'USD',amount:'20.50'}),'');
 assert.match(cashEntryProblem({...base,currency:'USD',amount:'20.501'}),/مرتبتين/);
});
test('exchange preview and validation keep each physical currency independent',()=>{
 assert.deepEqual(cashProjection({...base,mode:'buy_usd',amount:'2.25'}),{IQD:6625,USD:22.75});
 assert.deepEqual(cashProjection({...base,mode:'sell_usd',amount:'2.25'}),{IQD:13375,USD:18.25});
 assert.match(cashEntryProblem({...base,mode:'buy_usd',amount:'7'}),/رصيد الدينار/);
 assert.match(cashEntryProblem({...base,mode:'sell_usd',amount:'21'}),/رصيد الدولار/);
});
test('unrelated negative legacy balance does not block a deposit or spending another currency',()=>{
 assert.equal(cashEntryProblem({...base,usd:-10}),'');
 assert.equal(cashEntryProblem({...base,mode:'deposit',iqd:-5000}),'');
 assert.deepEqual(cashProjection({...base,mode:'deposit',iqd:-5000}),{IQD:-4000,USD:20.5});
});
