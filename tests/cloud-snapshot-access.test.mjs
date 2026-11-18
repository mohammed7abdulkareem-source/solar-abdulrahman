import test from 'node:test';
import assert from 'node:assert/strict';
import {cloudSnapshotAccess} from '../app/cloud-snapshot-access.mjs';
import {salesAuthorizationKey} from '../app/sales-read-scope.mjs';
import {loadCloud,supabase} from '../app/supabase.js';

const office=(permissions={},patch={})=>({id:'person',active:true,is_admin:false,user_type:'admin_staff',permissions,...patch});
const restricted=office({tahseel:true,tahseelFull:true,ownSales:true,ownCash:true,salesDeleteOwn:true});
const product={id:3,name:'لوح 600W',code:'A12',category:'ألواح',brands:{name:'FULLMAX'},cost:10000,qty:110,bookQty:120,cost_basis:{usd:45}};

test('quote-only loads only the quote catalog on startup and refresh, with the granted pricing projection',async t=>{
 let profile=restricted;const calls=[];
 t.mock.method(supabase.auth,'getSession',async()=>({data:{session:{user:{id:profile.id}}}}));
 t.mock.method(supabase,'from',table=>{
  calls.push(table);assert.equal(table,'profiles');
  return {select(){return this},eq(column,id){assert.equal(column,'id');assert.equal(id,profile.id);return this},single:async()=>({data:profile})};
 });
 t.mock.method(supabase,'rpc',async(name,options)=>{
  calls.push(name);assert.equal(name,'solar_inventory');assert.deepEqual(options,{action:'catalog'});return {data:[product]};
 });
 for(const full of [true,false]){
  profile={...restricted,permissions:{...restricted.permissions,tahseelFull:full}};
  calls.length=0;
  const result=await loadCloud({fresh:true});
  assert.equal(result.authorizationKey,salesAuthorizationKey(profile));
  assert.deepEqual(calls,['profiles','solar_inventory']);
  assert.deepEqual(result.products,[{id:3,name:'لوح 600W',code:'A12',category:'ألواح',brand:'FULLMAX',...(full?{cost:10000}:{})}]);
  for(const table of ['brands','tx','customers','suppliers'])assert.deepEqual(result[table],[]);
  assert.equal(result.cashBalances,null);
 }
 profile=office({warranty:true,deletionRequests:true});
 calls.length=0;assert.deepEqual((await loadCloud({fresh:true})).products,[]);
 assert.deepEqual(calls,['profiles']);
});

test('a fresh authorization check during a slower read returns the downgraded scope to all waiters',async t=>{
 let profile=restricted;
 const started=Promise.withResolvers(),complete=Promise.withResolvers();
 t.mock.method(supabase.auth,'getSession',async()=>({data:{session:{user:{id:profile.id}}}}));
 t.mock.method(supabase,'from',table=>{
  assert.equal(table,'profiles');return {select(){return this},eq(){return this},single:async()=>({data:profile})};
 });
 t.mock.method(supabase,'rpc',async name=>{assert.equal(name,'solar_inventory');started.resolve();return complete.promise;});
 const first=loadCloud();await started.promise;
 profile=office({warranty:true});
 const next=loadCloud({fresh:true});
 // The load first awaits the local auth session before issuing the newer read.
 await new Promise(resolve=>setImmediate(resolve));complete.resolve({data:[product]});
 for(const result of await Promise.all([first,next])){
  assert.equal(result.authorizationKey,salesAuthorizationKey(profile));assert.deepEqual(result.products,[]);
  assert.deepEqual(result.tx,[]);assert.equal(result.cashBalances,null);
 }
});

test('a sale snapshot asks for its own receipt kinds, material and customer data and avoids cash or purchase entries',async t=>{
 const profile=office({sale:true}),seen=new Map();
 t.mock.method(supabase.auth,'getSession',async()=>({data:{session:{user:{id:profile.id}}}}));
 t.mock.method(supabase,'from',table=>{
  const entry={};seen.set(table,entry);return {
   select(columns){entry.columns=columns;return this},eq(){return this},single:async()=>({data:profile}),
   in(column,values){entry.filter={column,values};return this},order(){return this},range:async()=>({data:[]})
  };
 });
 t.mock.method(supabase,'rpc',async name=>{seen.set(name,{});return {data:[]};});
 await loadCloud({fresh:true});
 assert.deepEqual([...seen.keys()].sort(),['profiles','solar_inventory','customers','transactions','transaction_items','solar_receipt_contacts'].sort());
 assert.deepEqual(seen.get('transactions').filter,{column:'kind',values:['sale']});
 assert.deepEqual(seen.get('transaction_items').filter,{column:'receipt.kind',values:['sale']});
 assert.match(seen.get('transaction_items').columns,/receipt:transactions!inner\(kind\)/);
});

test('snapshot fetches only shared data consumed by the granted office workspaces',()=>{
 for(const profile of [null,office({}, {active:false,is_admin:true}),office({}, {user_type:'installer',is_admin:true}),office({}, {user_type:'warehouse',is_admin:true})]){
  const s=cloudSnapshotAccess(profile);
  for(const key of ['catalog','transactions','items','cashEntries','cashBalances','fxHistory','suppliers','customers','staff','brands'])assert.ok(!s[key],key);
 }
 for(const flags of [{ownSales:true,salesDeleteOwn:true},{deletionRequests:true},{warranty:true},{exchangeRate:true},{salesHistory:true}]){
  const s=cloudSnapshotAccess(office(flags));assert.equal(s.transactions,false);assert.equal(s.cashBalances,false);assert.equal(s.catalog,null);
 }
 const purchase=cloudSnapshotAccess(office({purchase:true}));assert.deepEqual(purchase.transactionKinds,['purchase']);assert.equal(purchase.suppliers,true);assert.equal(purchase.customers,false);
 const receiver=cloudSnapshotAccess(office({financeReceive:true}));assert.equal(receiver.cashBalances,true);assert.equal(receiver.transactions,false);assert.equal(receiver.fxHistory,false);
 const admin=cloudSnapshotAccess(office({}, {is_admin:true}));assert.equal(admin.transactionKinds,null);assert.equal(admin.cashEntries,true);assert.equal(admin.fxHistory,true);assert.equal(admin.staff,true);
});
