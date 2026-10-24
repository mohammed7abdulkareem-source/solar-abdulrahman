import test from 'node:test';
import assert from 'node:assert/strict';
import {refreshMaterialBrands} from '../app/current-brand.mjs';
import {currentSaleItems} from '../app/inventory-valuation.mjs';
import {quoteDocument,newQuote,calculateQuote} from '../app/tahseel-utils.mjs';
test('current material labels follow reassignment and cleared brands without changing saved values',()=>{
 const original=[{product_id:1,brand_name:'OLD',qty:3,price:99,cost:10,cost_basis:{usd:2}},{productId:2,brand:'OLD',qty:1},{id:3,brand:'OLD',cost:50},{product_id:null,id:1,brand_name:'LEGACY'},{id:4,brand:'DELETED'}];
 const copy=structuredClone(original),next=refreshMaterialBrands(original,[{id:1,brand:'M'},{id:2,brands:{name:'NEW'}},{id:3,brand:''}]);
 assert.equal(next[0].brand_name,'M');assert.equal(next[1].brand,'NEW');assert.equal(next[2].brand,'');assert.equal(next[3].brand_name,'LEGACY');assert.equal(next[4].brand,'DELETED');assert.deepEqual(original,copy);
 for(let i=0;i<next.length;i++){const {brand,brand_name,...a}=next[i],{brand:b,brand_name:c,...old}=original[i];assert.deepEqual(a,old);}
 const sale=currentSaleItems([{id:1,brand:'OLD',qty:3,price:99,cost:10}],[{id:1,brand:'M',cost:200}],[{id:1,brand:'OLD',cost:10}]);assert.equal(sale[0].brand,'M');assert.equal(sale[0].cost,10);assert.equal(sale[0].price,99);
});
test('saved quote PDFs use current brands while keeping original costs and totals',()=>{
 const form={...newQuote(),day:'10',night:'0',panel:{id:1,name:'لوح',brand:'OLD',cost:'100'},inverter:{id:2,name:'انفيرتر',brand:'OLD',cost:'1000'}};
 const before=structuredClone(form),q=calculateQuote(form),html=quoteDocument(form,true,null,[{id:1,brand:'M & NEW',cost:99999},{id:2,brand:'M',cost:99999}]);
 assert.ok(html.includes('M &amp; NEW'));assert.ok(!html.includes('OLD'));assert.deepEqual(form,before);assert.equal(calculateQuote(form).price,q.price);assert.ok(html.includes('1,000'));
});
