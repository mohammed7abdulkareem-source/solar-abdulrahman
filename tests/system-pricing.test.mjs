import test from 'node:test';
import assert from 'node:assert/strict';
import {systemMinimumQuote,belowSystemMinimum,systemEditPricingPercent} from '../app/system-pricing-utils.mjs';

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
