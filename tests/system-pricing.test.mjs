import test from 'node:test';
import assert from 'node:assert/strict';
import {systemMinimumQuote,formatMaterialUnitPrice,belowSystemMinimum,systemEditPricingPercent,systemMaterialPriceMap,systemMaterialTotal,systemEditStock,systemEconomicsChanged} from '../app/system-pricing-utils.mjs';

test('the minimum is markup on complete frozen cost, with expenses, and higher prices remain valid',()=>{
 const quote=systemMinimumQuote([{id:1,qty:2,cost:500}],25,100,100);
 assert.deepEqual(quote,{percent:25,materialCost:1000,totalCost:1200,minimum:1500});
 assert.equal(belowSystemMinimum(1499.999,quote.minimum),true);
 assert.equal(belowSystemMinimum(1500,quote.minimum),false);
 assert.equal(belowSystemMinimum(1800,quote.minimum),false);
 assert.equal(systemMinimumQuote([{qty:2,cost:500}],15,100,100).minimum,1380);
});
test('decimal quantities and frozen currency costs round exactly like the server, always rounding the threshold up',()=>{
 assert.equal(systemMinimumQuote([{qty:1,cost:'1000.005'}],15).minimum,1150.02);
 assert.equal(systemMinimumQuote([{qty:3,cost:'0.333333'},{qty:1,cost:'0.005001'}],25).minimum,1.27);
 assert.equal(systemMinimumQuote([{qty:'1e-3',cost:'1650.123456'}],25).minimum,2.07);
 assert.equal(systemMinimumQuote([{qty:1,cost:1000}],15,'0.001').minimum,1150.01);
 assert.equal(systemMinimumQuote([{qty:1,cost:1000}],16),null);
 assert.equal(systemMinimumQuote([{qty:'invalid',cost:1000}],25),null);
});
test('prior unrestricted agreements survive metadata edits, saved percentages survive expense review, repricing uses the current policy',()=>{
 const original={total:1250,items:[{id:1,qty:1,cost:1000}],systemMarkupPercent:15},status={systemFreePricing:false,systemMarkupPercent:25};
 assert.equal(systemEditPricingPercent(status,original,original.items,1250),15);
 assert.equal(systemEditPricingPercent(status,{...original,systemMarkupPercent:null},original.items,1250),null);
 assert.equal(systemEditPricingPercent(status,original,original.items,1400),25);
 assert.equal(systemEditPricingPercent(status,original,[{id:1,qty:2,cost:1000}],1250),25);
 assert.equal(systemEditPricingPercent({...status,systemFreePricing:true},original,original.items,1400),null);
});

test('system pricing uses quoted material prices for the sale threshold independently from accounting cost',()=>{
 const rows=[{id:1,qty:2,cost:385,materialPrice:430},{id:2,qty:1,cost:60,materialPrice:60.0001}];
 assert.equal(systemMaterialTotal(rows),920);
 assert.equal(systemMinimumQuote(rows,15,50,30,'materialPrice').minimum,1150);
 assert.equal(systemMinimumQuote(rows,15,50,30).minimum,1046.5);
 assert.equal(systemMaterialTotal([]),0);
 assert.equal(systemMaterialTotal([{...rows[0],materialPrice:null}]),null);
 assert.equal(systemMinimumQuote([{...rows[0],materialPrice:null}],15,0,0,'materialPrice'),null);
 const original={total:1200,items:rows};
 assert.equal(systemEconomicsChanged(original,[{...rows[1],cost:10},{...rows[0],materialPrice:445}],1200),false);
 assert.equal(systemEconomicsChanged(original,[{...rows[0],qty:3},rows[1]],1200),true);
});
test('only requested materials, permitted amounts and fresh live checks are usable for system previews',()=>{
 const visible={productId:1,priceSource:'configured',materialPrice:430,priceHidden:false,priceToken:'live1'};
 const hidden={productId:2,priceSource:'cost',materialPrice:null,priceHidden:true,priceToken:'live2'};
 const result=systemMaterialPriceMap({items:[hidden,visible]},[1,2]);
 assert.deepEqual(result.tokens,{'1':'live1','2':'live2'});
 assert.equal(result.prices.get('2'),null);
 assert.equal(result.prices.get('1'),430);
 assert.equal(systemMaterialPriceMap({items:[{...visible,priceSource:'historical',priceToken:undefined}]},[1]).tokens,undefined);
 for(const rows of[[hidden],[visible,{...hidden,materialPrice:385}],[visible,visible],[visible,{...hidden,productId:3}]]){
  assert.throws(()=>systemMaterialPriceMap({items:rows},[1,2]));
 }
});

test('an archived receipt keeps its reserved material editable when the current warehouse balance is empty',()=>{
 const stock=[{id:2,qty:1,name:'الجهاز'}],saved=[{id:1,qty:5,name:'اللوح'},{id:2,qty:2,name:'الجهاز'}];
 const available=systemEditStock(stock,saved);
 assert.equal(available.find(i=>i.id===1).qty,5);
 assert.equal(available.find(i=>i.id===2).qty,3);
 assert.equal(stock[0].qty,1);
});

test('approved automatic unit prices preserve true zero and FX precision on both invoice screens',()=>{
 for(const [price,expected] of [[0,'0'],[120050.000001,'120,050.000001'],['125050.45','125,050.45'],[null,'—']]){
  assert.equal(formatMaterialUnitPrice(price),expected);
  if(price!=null){
   const snapshot=systemMaterialPriceMap({items:[{productId:7,materialPrice:price,priceSource:'cost',priceHidden:false,priceToken:'new'}]},[7]);
   assert.equal(snapshot.prices.get('7'),Number(price));
   assert.deepEqual(snapshot.tokens,{'7':'new'});
  }
 }
});
