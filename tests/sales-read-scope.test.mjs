import test from 'node:test';
import assert from 'node:assert/strict';
import {salesAuthorizationKey,salesReadAllowed,salesReadOwner,verifySalesResponse} from '../app/sales-read-scope.mjs';

const seller={id:'seller',active:true,user_type:'admin_staff',is_admin:false,permissions:{salesHistory:true,sale:true,system:true,ownSales:true,warehouse:true,stockMovement:true,installations:true}};
const admin={...seller,is_admin:true};
const ownPage=()=>({ownerId:seller.id,count:2,users:[{id:seller.id}],rows:[{id:1,kind:'sale',created_by:seller.id},{id:2,kind:'system',created_by:seller.id}]});
const denied=operation=>assert.throws(operation,error=>error.code==='SALES_SCOPE_MISMATCH');

test('ordinary sellers always request their own owner even with operational permissions or a stale admin filter',()=>{
 assert.equal(salesReadOwner(seller),seller.id);
 assert.equal(salesReadOwner(seller,'another-seller'),seller.id);
 assert.equal(salesReadOwner({...seller,permissions:{...seller.permissions,all:true,ownSales:false}},'another-seller'),seller.id);
 assert.equal(salesReadOwner(admin),null);
 assert.equal(salesReadOwner(admin,'another-seller'),'another-seller');
});

test('authorization identity changes on demotion, activation, role and permission changes but not object property order',()=>{
 const key=salesAuthorizationKey(admin);
 for(const profile of [seller,{...admin,id:'another-admin'},{...admin,active:false},{...admin,user_type:'warehouse'},{...admin,permissions:{...admin.permissions,sale:false}}])assert.notEqual(salesAuthorizationKey(profile),key);
 const reordered={...admin,permissions:Object.fromEntries(Object.entries(admin.permissions).reverse())};
 assert.equal(salesAuthorizationKey(reordered),key);
 assert.equal(salesAuthorizationKey({...admin,display_name:'Changed display name'}),key);
});

test('the whole archive response is rejected if ownership metadata or any receipt belongs to another user',()=>{
 const page=ownPage();assert.equal(verifySalesResponse(page,seller),page);
 for(const invalid of [
  {...page,ownerId:null},
  {...page,ownerId:'another-seller'},
  {...page,rows:[...page.rows,{id:3,kind:'sale',created_by:'another-seller'}],count:3},
  {...page,rows:[{id:1,kind:'sale'}]},
  {...page,users:[{id:'another-seller'}]},
  {...page,count:NaN},
 ])denied(()=>verifySalesResponse(invalid,seller));
 assert.equal(page.count,2);assert.equal(page.rows.length,2);
});

test('admin all-user access and selected-owner filtering remain intact',()=>{
 const other={id:3,kind:'system',created_by:'another-seller'};
 const company={ownerId:null,count:3,users:[{id:seller.id},{id:'another-seller'}],rows:[...ownPage().rows,other]};
 assert.equal(verifySalesResponse(company,admin),company);
 const selected={...company,ownerId:'another-seller',count:1,rows:[other]};
 assert.equal(verifySalesResponse(selected,admin,'another-seller'),selected);
 denied(()=>verifySalesResponse(company,admin,'another-seller'));
 denied(()=>verifySalesResponse({...selected,rows:ownPage().rows},admin,'another-seller'));
});

test('period summaries are accepted only for the requested owner scope without trimming or recomputing totals',()=>{
 const summary=Object.freeze({invoiceCount:2,materialCount:1,quantitySold:13});
 const report=Object.freeze({ownerId:seller.id,scope:'own',users:[{id:seller.id}],summary,rows:[{productId:9,quantitySold:13,remainingQty:87}]});
 assert.equal(verifySalesResponse(report,seller,null,{period:true}),report);
 assert.equal(verifySalesResponse(report,seller,null,{period:true}).summary,summary);
 denied(()=>verifySalesResponse({...report,scope:'company'},seller,null,{period:true}));
 denied(()=>verifySalesResponse({...report,ownerId:'another-seller'},seller,null,{period:true}));
 const company={...report,ownerId:null,scope:'company'};
 assert.equal(verifySalesResponse(company,admin,null,{period:true}),company);
 denied(()=>verifySalesResponse(company,admin,seller.id,{period:true}));
 assert.equal(verifySalesResponse(report,admin,seller.id,{period:true}),report);
});

test('a snapshot loaded as admin is invalid after same-account demotion; restricted operational roles cannot read this archive',()=>{
 const page={ownerId:null,count:1,rows:[{id:3,created_by:'another-seller'}],users:[]};
 assert.equal(verifySalesResponse(page,admin),page);
 assert.notEqual(salesAuthorizationKey(admin),salesAuthorizationKey(seller));
 denied(()=>verifySalesResponse(page,seller));
 for(const profile of [{...seller,active:false},{...admin,user_type:'warehouse'},{...admin,user_type:'installer'},null]){
  assert.equal(salesReadAllowed(profile),false);denied(()=>verifySalesResponse(ownPage(),profile));
 }
});

test('a wholesale-only archive refuses a system receipt even when its owner matches',()=>{
 const wholesale={...seller,permissions:{sale:true}};
 denied(()=>verifySalesResponse(ownPage(),wholesale));
 const row=ownPage().rows[0],page={ownerId:seller.id,count:1,rows:[row],users:[]};
 assert.equal(verifySalesResponse(page,wholesale),page);
 assert.equal(salesReadAllowed({...seller,permissions:{tahseel:true,ownSales:true,salesDeleteOwn:true}}),false);
});
