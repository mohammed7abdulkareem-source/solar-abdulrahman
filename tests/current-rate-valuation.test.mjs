import test from 'node:test';
import assert from 'node:assert/strict';
import {currentSaleItems,hasHiddenSaleCost,invoiceAttemptSignature,newSaleItemWithApprovedPrice} from '../app/inventory-valuation.mjs';
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

test('personal sales show only projected unit prices and keep private fallback costs unknown',()=>{
 const draft=[{id:1,cost:385,costBasis:{bookUnitCost:385}},{id:2,cost:127,bookCost:127}];
 const catalog=[{id:1,cost:430,personalPriceBasis:true},{id:2,cost:null,personalPriceBasis:true}];
 const rows=currentSaleItems(draft,catalog,[],true);
 assert.deepEqual(rows.map(r=>r.cost),[430,null]);
 assert.deepEqual(rows[0].costBasis,{});
 assert.equal('bookCost' in rows[1],false);
 assert.equal(hasHiddenSaleCost(rows),true);
 assert.equal(currentSaleItems(draft,[{id:1,cost:385}],[],true)[0].cost,null);
 assert.equal(currentSaleItems(draft,catalog,[{id:1,cost:399,personalPriceBasis:true}],true)[0].cost,399);
});

test('invoice retries retain the original pricing tokens without treating a refresh as new business input',()=>{
 for(const [kind,key] of [['sale','wholesaleFloorTokens'],['system','systemMaterialPriceTokens']]){
  const first=invoicePayload(kind,{[key]:{'1':'v1'},total:5000},[{id:1,qty:1,price:5000}]);
  assert.deepEqual(first[key],{'1':'v1'});
  assert.equal(invoiceAttemptSignature(first),invoiceAttemptSignature({...first,[key]:{'1':'v2'}}));
  assert.equal(invoicePayload('purchase',{[key]:{'1':'v1'}},[])[key],undefined);
 }
});

test('only new personal sale profit uses the effective approved unit returned for the invoice',()=>{
 const [selected]=currentSaleItems([{id:12,qty:2,price:'150',cost:9999}],[{id:12,personalPriceBasis:true,cost:null}],[],true);
 for(const price of[0,132.493001]){
  const priced=newSaleItemWithApprovedPrice(selected,price);
  assert.equal(priced.cost,price);
  assert.equal(priced.price,'150');
  assert.equal(hasHiddenSaleCost([priced]),false);
 }
 assert.equal(newSaleItemWithApprovedPrice(selected,null).cost,null);
 assert.equal(selected.cost,null);
 const [ordinary]=currentSaleItems([{id:12}],[{id:12,cost:37}]);
 assert.strictEqual(newSaleItemWithApprovedPrice(ordinary,200),ordinary);
});
