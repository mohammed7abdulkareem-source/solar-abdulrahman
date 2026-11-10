import test from 'node:test';
import assert from 'node:assert/strict';
import {wholesalePricingReady,wholesaleEconomicsChanged,wholesaleLinePricing,wholesalePriceDefault,wholesalePricingIssues} from '../app/wholesale-invoice-pricing.mjs';
import {salesDocument} from '../app/sales-document.mjs';

const state=(overrides={})=>({enabled:true,canManage:false,canOverride:false,currency:'IQD',revision:4,products:[{id:10,name:'لوح',enabled:true,minPrice:150000.25,revision:2},{id:11,name:'انفيرتر',enabled:false,minPrice:170000},{id:12,name:'بطارية',enabled:false,minPrice:null}],...overrides});
const line=(overrides={})=>({id:10,name:'لوح',qty:2,price:'150000.25',cost:120000,...overrides});

test('wholesale minimum needs the global switch, the material check and a restricted seller independently',()=>{
 for(const enabled of[false,true])for(const marked of[false,true])for(const canOverride of[false,true]){
  const policy=state({enabled,canOverride,products:[{id:10,enabled:marked,minPrice:150000.25}]}),required=enabled&&marked&&!canOverride;
  assert.equal(wholesaleLinePricing(policy,10).required,required);
  assert.equal(wholesalePricingIssues(policy,[line({price:1})]).length,required?1:0);
  assert.equal(wholesalePriceDefault(policy,10),required?'150000.25':'');
 }
 // Editing prices and permission to sell freely are independent privileges.
 assert.equal(wholesalePricingIssues(state({canManage:true}),[line({price:1})]).length,1);
 assert.equal(wholesaleLinePricing(state(),11).reason,'unmarked');
 assert.equal(wholesalePriceDefault(state(),12),'');
});

test('each prescribed unit price is a floor: equality and higher pass, exact fractional deficits fail',()=>{
 for(const price of['150000.25','150000.250','150000.26','200000'])assert.deepEqual(wholesalePricingIssues(state(),[line({price})]),[]);
 for(const price of['150000.24','150000.249999','1.5000024e5','0','-1'])assert.equal(wholesalePricingIssues(state(),[line({price})]).length,1,price);
 const policy=state({products:[{id:10,enabled:true,minPrice:0.29}]});
 assert.deepEqual(wholesalePricingIssues(policy,[line({qty:0.3,price:'0.29'})]),[]);
 assert.equal(wholesalePricingIssues(policy,[line({qty:0.3,price:'0.289999'})]).length,1);
 const issues=wholesalePricingIssues(state(),[line({price:'140000'}),line({id:11,name:'حر',price:'9000000'})]);
 assert.deepEqual(issues,[{id:10,name:'لوح',minimum:150000.25}]);
});

test('unknown policy blocks save, incomplete marked prices fail closed, blank actual price remains ordinary form validation',()=>{
 for(const policy of[null,{},state({revision:null}),state({revision:''}),state({revision:-1}),state({revision:1.5}),state({currency:'USD'}),state({canOverride:undefined}),state({enabled:'true'})]){
  assert.equal(wholesalePricingReady(policy),false);
  assert.ok(wholesalePricingIssues(policy,[line()])[0].message);
 }
 for(const minPrice of[null,'',-1,Infinity,'bad'])assert.ok(wholesalePricingIssues(state({products:[{id:10,enabled:true,minPrice}]}),[line()])[0].message);
 assert.equal(wholesalePricingReady(state()),true);
 assert.deepEqual(wholesalePricingIssues(state(),[line({price:''})]),[]);
 assert.deepEqual(wholesalePricingIssues(state(),[line({id:12,price:1})]),[]);
});

test('historical prices survive metadata and display changes while any changed material, quantity or price uses current floors',()=>{
 const original=[line({price:120000}),line({id:11,name:'انفيرتر',price:100000})];
 const displayOnly=original.map(row=>({...row,name:'اسم محدث',brand:'براند',cost:999999,notes:'ملاحظة'})).reverse();
 assert.equal(wholesaleEconomicsChanged(displayOnly,original),false);
 assert.deepEqual(wholesalePricingIssues(state(),displayOnly,original),[]);
 assert.equal(wholesaleLinePricing(state(),10,{historical:true}).reason,'historical');
 for(const edited of[
  original.map(row=>row.id===10?{...row,qty:3}:row),
  original.map(row=>row.id===10?{...row,price:120001}:row),
  [...original,line({id:12})],original.slice(0,1),
  original.map(row=>row.id===11?{...row,id:12}:row),
 ]){
  assert.equal(wholesaleEconomicsChanged(edited,original),true);
  assert.equal(wholesalePricingIssues(state(),edited,original)[0].id,10);
 }
 assert.equal(wholesaleEconomicsChanged(original,undefined),true);
 assert.equal(wholesaleEconomicsChanged([line({qty:'2.0',price:'120000.00'}),original[1]],original),false);
 assert.deepEqual(wholesalePricingIssues(state(),original.map(row=>({...row,price:200000})),original),[]);
});

test('customer preview/PDF/share uses actual selling prices without internal cost or prescribed minimum',()=>{
 const row={kind:'sale',receiptNo:91,party_name:'عميل جملة',created_at:'2026-11-10T09:00:00Z',total:234568.78,wholesalePricingRevision:19,items:[{product_id:10,product_name:'لوح',qty:2,price:117284.39,cost:87654.32,minPrice:98765.43,wholesaleMinPrice:98765.43,costBasis:{unitCost:87654.32}}]};
 for(const draft of[false,true]){
  const doc=salesDocument({...row,draft});
  assert.match(doc.body,/117,284\.39/);
  assert.match(doc.body,/234,568\.78/);
  assert.equal(doc.total,'234,568.78 د.ع');
  for(const hidden of['87,654.32','87654.32','98,765.43','98765.43','كلفة الوحدة','سعر البيع المقرر','wholesalePricingRevision'])assert.ok(!JSON.stringify(doc).includes(hidden),hidden);
  const warehouse=salesDocument({...row,draft},false);
  assert.equal(warehouse.total,'');
  for(const hidden of['117,284.39','234,568.78','87,654.32','98,765.43','سعر البيع المقرر'])assert.ok(!warehouse.body.includes(hidden),hidden);
 }
});
