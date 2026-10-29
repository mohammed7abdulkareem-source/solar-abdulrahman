import test from 'node:test';
import assert from 'node:assert/strict';
import {purchaseAmounts,weightedCost,exchangeRateError,canEditExchangeRate,invoicePayload} from '../app/currency-utils.mjs';
import {supplierDocument,supplierLedger} from '../app/supplier-utils.mjs';

test('USD purchases keep original prices while accounting and landed cost are IQD',()=>{
 const result=purchaseAmounts([{id:1,qty:2,price:100},{id:2,qty:1,price:200}],'USD',1500,60000);
 assert.equal(result.sourceSubtotal,400);assert.equal(result.subtotal,600000);assert.equal(result.total,660000);
 assert.equal(result.items[0].sourcePrice,100);assert.equal(result.items[0].price,150000);
 assert.equal(result.items[0].landedCost,165000);assert.equal(result.items[1].landedCost,330000);
});
test('IQD purchases ignore exchange rates and allocate only IQD expenses',()=>{
 const result=purchaseAmounts([{id:1,qty:2,price:100000}],'IQD',1550,20000);
 assert.equal(result.total,220000);assert.equal(result.exchangeRate,1);assert.equal(result.items[0].landedCost,110000);
});
test('average cost weights quantities, including different currencies and rates',()=>{
 assert.equal(weightedCost(10,100000,10,120000),110000);
 assert.equal(weightedCost(3,120000,1,160000),130000);
 assert.equal(weightedCost(0,99999,2,150000),150000);
 assert.throws(()=>weightedCost(-1,100,2,200));
});
test('invalid rates fail closed; no USD rate is assumed',()=>{
 for(const rate of ['',0,-1,Infinity,NaN,1000001])assert.ok(exchangeRateError('USD',rate));
 assert.equal(exchangeRateError('USD',1500),'');assert.ok(exchangeRateError('EUR',1));
 assert.throws(()=>purchaseAmounts([{qty:1,price:100}],'USD',0));
});
test('only active staff with an explicit permission or admin can edit the rate',()=>{
 assert.equal(canEditExchangeRate({active:true,is_admin:true}),true);
 assert.equal(canEditExchangeRate({active:true,permissions:{exchangeRateEdit:true}}),true);
 for(const profile of [null,{active:false,is_admin:true},{active:true,permissions:{}},{active:true,user_type:'installer',is_admin:true},{active:true,user_type:'warehouse',permissions:{exchangeRateEdit:true}}])assert.equal(canEditExchangeRate(profile),false);
});
test('saving a sale cannot submit a foreign currency or client-provided cost',()=>{
 const result=invoicePayload('sale',{currency:'USD',exchangeRate:1550,party:'عميل'},[{id:1,qty:1,price:200000,cost:1,costBasis:{rate:1}}]);
 assert.equal(result.sourceCurrency,'IQD');assert.equal(result.exchangeRate,1);assert.equal('cost' in result.items[0],false);
});
test('editing a purchase preserves its original rate and supplies a revision',()=>{
 const result=invoicePayload('purchase',{sourceCurrency:'USD',exchangeRate:1500},[{id:1,qty:1,price:100}],{id:20,pricingRevision:3});
 assert.equal(result.invoiceId,20);assert.equal(result.expectedRevision,3);assert.equal(result.exchangeRate,1500);
});
test('saved USD purchase PDF shows its frozen source price and rate, with source-currency total and explicit IQD book value',()=>{
 const doc=supplierDocument({kind:'purchase',receiptNo:5,party:'مورد',date:'2026-10-12',sourceCurrency:'USD',exchangeRate:1500,total:150000,items:[{qty:1,price:150000,sourcePrice:100,name:'لوح'}]});
 assert.match(doc.body,/الصرف المثبت/);assert.match(doc.body,/1,500/);assert.match(doc.body,/سعر الوحدة \$/);assert.match(doc.body,/>100</);assert.equal(doc.total,'100 $');assert.match(doc.body,/القيمة المحاسبية للمخزون/);assert.match(doc.body,/150,000/);
});
test('supplier balances use locked IQD values, not current exchange rates',()=>{
 const tx=[{kind:'purchase',party:'مورد',sourceCurrency:'USD',exchangeRate:1500,total:150000,cash:false,date:'2026-10-12'},{kind:'supplier_payment',party:'مورد',total:50000,date:'2026-10-12'}];
 assert.equal(supplierLedger(tx,{name:'مورد'}).balance,100000);
});
test('direct preparation is included only on a new wholesale sale',()=>{
 assert.equal(invoicePayload('sale',{directPreparation:true},[]).directPreparation,true);
 for(const result of [invoicePayload('sale',{directPreparation:false},[]),invoicePayload('sale',{directPreparation:true},[],{id:1}),invoicePayload('purchase',{directPreparation:true},[]),invoicePayload('system',{directPreparation:true},[])])assert.equal(Object.hasOwn(result,'directPreparation'),false);
});
