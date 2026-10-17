import test from 'node:test';
import assert from 'node:assert/strict';
import {formatMoney,purchaseDisplayTotal} from '../app/money-format.mjs';
test('USD fractions have two places, integer dollars have none',()=>{
 for(const [value,expected] of [[125,'125'],[125.5,'125.50'],[125.25,'125.25'],[0,'0'],[1000.5,'1,000.50'],[-125.5,'-125.50'],['125.00','125'],[125.999,'126']])assert.equal(formatMoney(value,'USD'),expected);
 assert.equal(formatMoney(1500000,'IQD'),'1,500,000');
});
test('purchase totals retain invoice currency including IQD expenses converted at the saved rate',()=>{
 assert.deepEqual(purchaseDisplayTotal({sourceCurrency:'USD',sourceSubtotal:251,expenses:3000,total:379500,marketRate:1500}),{currency:'USD',value:253});
 assert.deepEqual(purchaseDisplayTotal({sourceCurrency:'USD',total:188250,exchangeRate:1500}),{currency:'USD',value:125.5});
 assert.deepEqual(purchaseDisplayTotal({sourceCurrency:'IQD',total:188250}),{currency:'IQD',value:188250});
});
