import test from 'node:test';
import assert from 'node:assert/strict';
import {wholesalePricingReady,wholesaleEconomicsChanged,wholesaleLinePricing,wholesalePriceDefault,wholesaleSuggestedPrice,refreshWholesaleDefaults,wholesaleFloorTokens,wholesalePricingIssues,wholesalePolicyEnforced} from '../app/wholesale-invoice-pricing.mjs';
import {salesDocument} from '../app/sales-document.mjs';

const state=(overrides={})=>({enabled:true,canManage:false,canOverride:false,currency:'IQD',revision:4,products:[{id:10,name:'لوح',enabled:true,minPrice:150000.25,revision:2},{id:11,name:'انفيرتر',enabled:false,minPrice:170000},{id:12,name:'بطارية',enabled:false,minPrice:null}],...overrides});
const line=(overrides={})=>({id:10,name:'لوح',qty:2,price:'150000.25',cost:120000,...overrides});
const scoped=(overrides={})=>state({scopeMode:'selected',scopeConfigured:true,appliesToCurrentUser:true,appliesToSubject:true,effectiveEnforced:true,legacyCanOverride:false,...overrides});

test('explicit scope binds selected accounts despite former free pricing while an unselected account stays free',()=>{
 for(const scopeMode of['all','selected'])for(const legacyCanOverride of[false,true]){
  const selected=scoped({scopeMode,legacyCanOverride});
  assert.equal(wholesalePricingReady(selected),true);
  assert.equal(wholesalePolicyEnforced(selected),true);
  assert.equal(wholesaleLinePricing(selected,10).reason,'required');
  assert.equal(wholesalePricingIssues(selected,[line({price:1})]).length,1);
  assert.equal(wholesalePriceDefault(selected,10),'150000.25');
 }
 const unselected=scoped({appliesToCurrentUser:false,appliesToSubject:false,effectiveEnforced:false});
 assert.equal(wholesalePricingReady(unselected),true);
 assert.equal(wholesaleLinePricing(unselected,10).reason,'outside_scope');
 assert.deepEqual(wholesalePricingIssues(unselected,[line({price:1})]),[]);
 assert.equal(wholesalePriceDefault(unselected,10),'');
});

test('archived edits use the invoice subject policy rather than the editing actor selection',()=>{
 const adminEditingBoundOwner=scoped({appliesToCurrentUser:false,appliesToSubject:true,effectiveEnforced:true,legacyCanOverride:true});
 assert.equal(wholesalePricingIssues(adminEditingBoundOwner,[line({price:1})]).length,1);
 const boundActorEditingFreeOwner=scoped({appliesToCurrentUser:true,appliesToSubject:false,effectiveEnforced:false});
 assert.deepEqual(wholesalePricingIssues(boundActorEditingFreeOwner,[line({price:1})]),[]);
 assert.equal(wholesaleLinePricing(boundActorEditingFreeOwner,10).reason,'outside_scope');
 const historical=[line({price:0})];
 assert.deepEqual(wholesalePricingIssues(adminEditingBoundOwner,historical,historical),[]);
 assert.equal(wholesalePricingIssues(adminEditingBoundOwner,[line({price:0,qty:3})],historical).length,1);
});

test('global disable and unmarked materials stay free; unconfigured scope preserves old exemptions',()=>{
 const disabled=scoped({enabled:false,effectiveEnforced:false});
 assert.equal(wholesalePricingReady(disabled),true);
 assert.deepEqual(wholesalePricingIssues(disabled,[line({price:1})]),[]);
 assert.equal(wholesaleLinePricing(disabled,10).reason,'disabled');
 assert.deepEqual(wholesalePricingIssues(scoped(),[line({id:11,price:1})]),[]);
 const legacy=scoped({scopeMode:'all',scopeConfigured:false,canOverride:true,legacyCanOverride:true,effectiveEnforced:false});
 assert.equal(wholesalePricingReady(legacy),true);assert.equal(wholesaleLinePricing(legacy,10).reason,'override');
 assert.deepEqual(wholesalePricingIssues(legacy,[line({price:1})]),[]);
});

test('incomplete scope response cannot silently choose unrestricted pricing',()=>{
 for(const policy of[state({scopeMode:'selected'}),scoped({scopeMode:'wrong'}),scoped({scopeConfigured:undefined}),scoped({appliesToSubject:undefined}),scoped({appliesToCurrentUser:undefined}),scoped({effectiveEnforced:undefined}),scoped({effectiveEnforced:false}),scoped({scopeConfigured:false,canOverride:false,effectiveEnforced:false}),scoped({enabled:false,effectiveEnforced:true}),scoped({appliesToSubject:false,effectiveEnforced:true})]){
  assert.equal(wholesalePricingReady(policy),false);
  assert.ok(wholesalePricingIssues(policy,[line({price:1})])[0].message);
 }
 assert.equal(wholesalePricingReady(state()),true,'pre-scope server response remains compatible');
});

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

test('automatic floors use current IQD valuation, including USD components already converted by the server',()=>{
 const policy=state({products:[{id:1,enabled:false,minPrice:690000,floorSource:'cost',effectiveMinPrice:125050.000001,floorToken:'old'},
  {id:2,enabled:true,minPrice:130000,floorSource:'configured',effectiveMinPrice:130000,floorToken:'manual'}]});
 const automatic={id:1,name:'مادة',qty:1,price:'',useWholesaleFloor:true},negotiated={id:2,qty:1,price:'155500'};
 const before=refreshWholesaleDefaults([automatic,negotiated],policy);
 assert.equal(before[0].price,'125050.01');assert.strictEqual(before[1],negotiated);
 assert.equal(wholesalePricingIssues(policy,[{...automatic,price:'125050'}])[0].minimum,125050.01);
 assert.deepEqual(wholesalePricingIssues(policy,before),[]);
 const next={...policy,products:[{...policy.products[0],effectiveMinPrice:129050.25,floorToken:'new'},policy.products[1]]};
 const after=refreshWholesaleDefaults(before,next);
 assert.equal(after[0].price,'129050.25');
 assert.strictEqual(after[1],negotiated);
 const typed={...before[0],useWholesaleFloor:false,price:'125300'};
 assert.strictEqual(refreshWholesaleDefaults([typed],next)[0],typed);
 assert.deepEqual(wholesaleFloorTokens(next,[typed]),{'1':'new'});
 assert.equal(wholesaleFloorTokens(next,[typed],[typed]),undefined);
 assert.equal(wholesaleFloorTokens({...next,enabled:false},[typed]),undefined);
 for(const [raw,rounded] of [[0,0],[0.29,0.29],[0.290001,.3],[1.995001,2],['',null],[null,null]])assert.equal(wholesaleSuggestedPrice(raw),rounded);
});
test('hidden automatic minima never prefill book cost or an inactive saved override and remain server-validated',()=>{
 const restricted=state({products:[{id:10,enabled:false,minPrice:175555,floorSource:'cost',effectiveMinPrice:null,floorToken:'opaque'}]});
 const rule=wholesaleLinePricing(restricted,10);
 assert.equal(rule.required,true);
 assert.equal(rule.price,null);assert.equal(rule.suggested,null);
 assert.equal(wholesalePriceDefault(restricted,10),'');
 assert.deepEqual(wholesalePricingIssues(restricted,[line({price:1})]),[]);
 assert.equal(refreshWholesaleDefaults([line({useWholesaleFloor:true})],restricted)[0].price,'');
 assert.equal(wholesaleLinePricing({...restricted,canOverride:true},10).required,false);
 assert.equal(wholesaleLinePricing(restricted,10,{historical:true}).required,false);
});

test('approved unit references follow the quote for free and bound sellers without repricing the customer field',()=>{
 const products=[
  {id:1,enabled:true,minPrice:140000,floorSource:'configured',effectiveMinPrice:140000,cost:null},
  {id:2,enabled:false,minPrice:990000,floorSource:'cost',effectiveMinPrice:125050.000001,cost:null},
  {id:3,enabled:false,minPrice:null,floorSource:'cost',effectiveMinPrice:0,cost:null}
 ];
 for(const enforced of[false,true]){
  const policy=scoped({products,appliesToCurrentUser:enforced,appliesToSubject:enforced,effectiveEnforced:enforced});
  const values=products.map(row=>wholesaleLinePricing(policy,row.id));
  assert.deepEqual(values.map(v=>v.price),[140000,125050.000001,0]);
  assert.deepEqual(values.map(v=>v.suggested),[140000,125050.01,0]);
  assert.deepEqual(values.map(v=>v.required),[enforced,enforced,enforced]);
  assert.deepEqual(products.map(row=>wholesalePriceDefault(policy,row.id)),enforced?['140000','125050.01','0']:['','','']);
  const typed={id:2,qty:'1',price:'12345.67',useWholesaleFloor:false};
  assert.strictEqual(refreshWholesaleDefaults([typed],policy)[0],typed);
 }
});
