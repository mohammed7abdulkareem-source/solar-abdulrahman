import test from 'node:test';
import assert from 'node:assert/strict';
import {changedRows, invoiceError, installationCost} from '../app/review-utils.mjs';
test('only explicitly changed records are written',()=>{
 const before=[{id:1,name:'one'},{id:2,name:'two'}];
 assert.deepEqual(changedRows(before,[before[0],{id:2,name:'updated'},{id:3,name:'new'}]),{changed:[{id:2,name:'updated'},{id:3,name:'new'}],removed:[]});
 assert.deepEqual(changedRows(before,[before[1]]).removed,[1]);
});
test('invalid quantities, missing prices and overselling are rejected',()=>{
 const products=[{id:1,name:'Panel',qty:2}];
 for(const qty of [0,-1,NaN,3]) assert.ok(invoiceError([{id:1,qty,price:100}],products,'sale'));
 assert.ok(invoiceError([{id:1,qty:1,price:''}],products,'sale'));
 assert.equal(invoiceError([{id:1,qty:2,price:100}],products,'sale'),'');
});
test('reclosing a job replaces expenses rather than counting them twice',()=>{
 const job={cost:100,expenses:10,installationExpenses:20};
 assert.equal(installationCost(job,30),140);
 assert.equal(installationCost(job),130);
});
