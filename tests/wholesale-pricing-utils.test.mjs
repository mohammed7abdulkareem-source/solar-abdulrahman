import test from 'node:test';
import assert from 'node:assert/strict';
import {availableWholesalePriceProducts,wholesalePriceSaveNotice,wholesalePriceDraft,wholesalePriceChanged,wholesalePriceValidation,wholesalePriceItems,wholesaleScopeDraft,wholesaleScopeChanged,wholesaleScopeValidation,wholesaleScopePayload,readWholesalePriceAttempt,rememberWholesalePriceAttempt,clearWholesalePriceAttempt} from '../app/wholesale-pricing-utils.mjs';
import {canManageWholesalePricing,canOpenPage} from '../app/access-utils.mjs';
import {sectionGroups,sections} from '../app/section-directory.mjs';

test('pricing management includes only finite positive scoped stock without changing stored policies',()=>{
 const zero=Object.freeze({id:3,qty:0,companyQty:99,minPrice:55000,enabled:true,revision:4});
 const rows=Object.freeze([Object.freeze({id:1,qty:2,minPrice:100,revision:2}),Object.freeze({id:2,qty:'0.001',minPrice:null,revision:0}),zero,...['0',-1,null,undefined,'',NaN,Infinity,'NaN',true].map((qty,index)=>Object.freeze({id:index+4,qty,companyQty:50,minPrice:500}))]);
 const available=availableWholesalePriceProducts(rows);
 assert.deepEqual(available.map(row=>row.id),[1,2]);assert.equal(available[0],rows[0]);
 assert.equal(zero.minPrice,55000);assert.equal(zero.enabled,true);assert.equal(zero.revision,4);
 assert.deepEqual(wholesalePriceDraft(availableWholesalePriceProducts([{...zero,qty:1}])[0]),{minPrice:'55000',enabled:true});
 const drafts={1:{minPrice:'150',enabled:true},3:{minPrice:'',enabled:false}};
 assert.deepEqual(wholesalePriceItems(available,drafts),[{productId:1,minPrice:150,enabled:true,expectedRevision:2}]);
 assert.deepEqual(availableWholesalePriceProducts(null),[]);
});

test('pricing save acknowledgements mention notifications only for confirmed effective changes',()=>{
 assert.match(wholesalePriceSaveNotice('save',{}, {changedCount:2,notifiedCount:4}),/إرسال إشعار/);
 for(const response of [{changedCount:0,notifiedCount:4},{changedCount:2,notifiedCount:0},{},{changedCount:2}])assert.doesNotMatch(wholesalePriceSaveNotice('save',{},response),/إرسال إشعار/);
 assert.match(wholesalePriceSaveNotice('save',{}, {changedCount:0,notifiedCount:0}),/لا توجد تغييرات/);
 assert.doesNotMatch(wholesalePriceSaveNotice('toggle',{enabled:true},{changedCount:0,notifiedCount:5}),/إرسال إشعار/);
 assert.match(wholesalePriceSaveNotice('toggle',{enabled:false},{changedCount:1,notifiedCount:5}),/الاحتفاظ بالأسعار المحفوظة وإرسال إشعار/);
 assert.match(wholesalePriceSaveNotice('scope',{mode:'selected'},{changedCount:1,notifiedCount:5}),/تم حفظ المستخدمين.*إرسال إشعار/);
 assert.doesNotMatch(wholesalePriceSaveNotice('scope',{mode:'all'},{changedCount:1,notifiedCount:0}),/إرسال إشعار/);
});

test('scope drafts require explicit first configuration and keep all-mode separate from global activation',()=>{
 const state={scopeConfigured:false,scopeMode:'all',selectedUserIds:[],eligibleUsers:[{id:'one',isAdmin:true,legacyCanOverride:true},{id:'two'}],enabled:true};
 const all=wholesaleScopeDraft(state);
 assert.deepEqual(all,{mode:'all',userIds:[]});assert.equal(wholesaleScopeChanged(state,null),false);
 assert.equal(wholesaleScopeChanged(state,all),true);
 assert.equal(wholesaleScopeChanged({...state,scopeConfigured:true},all),false);
 assert.deepEqual(wholesaleScopePayload({mode:'all',userIds:['one']},7),{mode:'all',userIds:[],expectedRevision:7});
 assert.equal(wholesaleScopeValidation({mode:'selected',userIds:['one']},state.eligibleUsers),'');
 assert.deepEqual(state.eligibleUsers[0],{id:'one',isAdmin:true,legacyCanOverride:true});
});

test('selected scope validates available sellers, normalizes order, and excludes stale unavailable IDs only in its draft',()=>{
 const state={scopeConfigured:true,scopeMode:'selected',selectedUserIds:['two','gone','one'],eligibleUsers:[{id:'one'},{id:'two'}]};
 const draft=wholesaleScopeDraft(state);
 assert.deepEqual(draft,{mode:'selected',userIds:['one','two']});assert.deepEqual(state.selectedUserIds,['two','gone','one']);
 assert.equal(wholesaleScopeChanged(state,{mode:'selected',userIds:['two','one']}),false);
 assert.equal(wholesaleScopeChanged(state,{mode:'selected',userIds:['two']}),true);
 assert.ok(wholesaleScopeValidation({mode:'selected',userIds:[]},state.eligibleUsers));
 assert.ok(wholesaleScopeValidation({mode:'selected',userIds:['gone']},state.eligibleUsers));
 assert.deepEqual(wholesaleScopePayload({mode:'selected',userIds:['two','one','two']},9),{mode:'selected',userIds:['one','two'],expectedRevision:9});
});

test('unset wholesale floor stays blank and cannot be enabled until a positive price is entered',()=>{
 const blank=wholesalePriceDraft({minPrice:null,enabled:false});
 assert.deepEqual(blank,{minPrice:'',enabled:false});assert.equal(wholesalePriceValidation(blank),'');
 assert.ok(wholesalePriceValidation({...blank,enabled:true}));
 for(const minPrice of ['0','-1','NaN','Infinity','1000000000001','1.234','.'])assert.ok(wholesalePriceValidation({minPrice,enabled:false}),minPrice);
 for(const minPrice of ['.5','250000','1500.25'])assert.equal(wholesalePriceValidation({minPrice,enabled:true}),'');
});

test('saving floor edits preserves unchanged rows and individual revisions including blank removal',()=>{
 const products=[{id:1,minPrice:1000,enabled:true,revision:7},{id:2,minPrice:2000,enabled:true,revision:9},{id:3,minPrice:null,enabled:false,revision:0}];
 const drafts={1:{minPrice:'1000.00',enabled:true},2:{minPrice:'',enabled:false},3:{minPrice:'500.25',enabled:true}};
 assert.equal(wholesalePriceChanged(products[0],drafts[1]),false);
 assert.deepEqual(wholesalePriceItems(products,drafts),[{productId:2,minPrice:null,enabled:false,expectedRevision:9},{productId:3,minPrice:500.25,enabled:true,expectedRevision:0}]);
 assert.equal(wholesalePriceChanged(products[1],{minPrice:'2000',enabled:false}),true);
});

test('price management permission is independent from free selling and limited to active office roles',()=>{
 const staff={id:'staff',active:true,user_type:'admin_staff',permissions:{}};
 assert.equal(canManageWholesalePricing(staff),false);
 assert.equal(canManageWholesalePricing({...staff,permissions:{wholesaleFreePricing:true}}),false);
 assert.equal(canManageWholesalePricing({...staff,permissions:{wholesalePricingManage:true}}),true);
 assert.equal(canManageWholesalePricing({...staff,is_admin:true}),true);
 for(const user_type of ['warehouse','installer'])assert.equal(canManageWholesalePricing({...staff,user_type,is_admin:true,permissions:{wholesalePricingManage:true}}),false);
 assert.equal(canManageWholesalePricing({...staff,active:false,is_admin:true}),false);
 assert.equal(canOpenPage({...staff,permissions:{wholesalePricingManage:true}},'users'),false);
 assert.ok(sectionGroups.find(group=>group.id==='settings').ids.includes('wholesalePricing'));
 assert.ok(sections.flatMap(([,rows])=>rows).some(([id,label])=>id==='wholesalePricing'&&label==='أسعار بيع الجملة'));
});

test('an uncertain settings request survives same-tab reload and is scoped to user and exact request',()=>{
 const saved=new Map(),previous=globalThis.sessionStorage;
 globalThis.sessionStorage={getItem:key=>saved.get(key)||null,setItem:(key,value)=>saved.set(key,value),removeItem:key=>saved.delete(key)};
 try{
  const attempt={id:'00000000-0000-4000-8000-000000000001',action:'toggle',payload:{enabled:true,expectedRevision:5}};
  assert.equal(rememberWholesalePriceAttempt('one',attempt),true);
  assert.deepEqual(readWholesalePriceAttempt('one'),attempt);assert.equal(readWholesalePriceAttempt('two'),null);
  clearWholesalePriceAttempt('one','00000000-0000-4000-8000-000000000002');assert.deepEqual(readWholesalePriceAttempt('one'),attempt);
  clearWholesalePriceAttempt('one',attempt.id);assert.equal(readWholesalePriceAttempt('one'),null);
  rememberWholesalePriceAttempt('one',{...attempt,payload:{enabled:true,expectedRevision:-1}});assert.equal(readWholesalePriceAttempt('one'),null);
  rememberWholesalePriceAttempt('one',{...attempt,action:'save',payload:{items:[]}});assert.equal(readWholesalePriceAttempt('one'),null);
  const scopeAttempt={...attempt,action:'scope',payload:{mode:'selected',userIds:['00000000-0000-4000-8000-000000000002'],expectedRevision:9}};
  assert.equal(rememberWholesalePriceAttempt('one',scopeAttempt),true);assert.deepEqual(readWholesalePriceAttempt('one'),scopeAttempt);
  clearWholesalePriceAttempt('one',scopeAttempt.id);assert.equal(readWholesalePriceAttempt('one'),null);
  for(const payload of [{mode:'selected',userIds:[],expectedRevision:9},{mode:'selected',userIds:['bad-id'],expectedRevision:9},{mode:'all',userIds:scopeAttempt.payload.userIds,expectedRevision:9},{mode:'selected',userIds:[...scopeAttempt.payload.userIds,...scopeAttempt.payload.userIds],expectedRevision:9},{mode:'selected',userIds:scopeAttempt.payload.userIds,expectedRevision:-1}]){rememberWholesalePriceAttempt('one',{...scopeAttempt,payload});assert.equal(readWholesalePriceAttempt('one'),null);}
  const allAttempt={...scopeAttempt,payload:{mode:'all',userIds:[],expectedRevision:10}};rememberWholesalePriceAttempt('one',allAttempt);assert.deepEqual(readWholesalePriceAttempt('one'),allAttempt);
  globalThis.sessionStorage={getItem:()=>null,setItem:()=>{throw new Error('Storage unavailable');}};
  assert.equal(rememberWholesalePriceAttempt('one',attempt),false);
 }finally{if(previous===undefined)delete globalThis.sessionStorage;else globalThis.sessionStorage=previous;}
});
