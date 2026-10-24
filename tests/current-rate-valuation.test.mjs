import test from 'node:test';
import assert from 'node:assert/strict';
import {currentSaleItems,invoiceAttemptSignature} from '../app/inventory-valuation.mjs';
import {invoicePayload} from '../app/currency-utils.mjs';

test('new sale quotes follow catalog FX without losing entered quantities/prices',()=>{
 const rows=[{id:1,qty:'2',price:'250000',cost:170100}];
 const next=currentSaleItems(rows,[{id:1,cost:180100,costBasis:{valuationRevision:2}}]);
 assert.equal(next[0].cost,180100);assert.equal(next[0].qty,'2');assert.equal(next[0].price,'250000');assert.equal(rows[0].cost,170100);
});
test('archive lines retain saved costs; newly added materials use current quote',()=>{
 const next=currentSaleItems([{id:1,qty:3,price:20,cost:1},{id:2,qty:1,price:30}], [{id:1,cost:11},{id:2,cost:25}], [{id:1,cost:8,costBasis:{valuationRevision:1}}]);
 assert.equal(next[0].cost,8);assert.equal(next[0].costBasis.valuationRevision,1);assert.equal(next[1].cost,25);
});
test('pending exact retry survives FX change but detects changed business input',()=>{
 const first=invoicePayload('sale',{party:'A',mode:'credit',valuationRevision:2},[{id:1,qty:2,price:250000}]);
 assert.equal(invoiceAttemptSignature(first),invoiceAttemptSignature({...first,valuationRevision:3}));
 assert.notEqual(invoiceAttemptSignature(first),invoiceAttemptSignature({...first,party:'B'}));
 assert.notEqual(invoiceAttemptSignature(first),invoiceAttemptSignature({...first,items:[{id:1,qty:3,price:250000}]}));
 assert.equal(first.valuationRevision,2);
 assert.equal(invoicePayload('purchase',{valuationRevision:2},[]).valuationRevision,undefined);
});
