import test from 'node:test';
import assert from 'node:assert/strict';
import {availableWholesalePriceProducts,refreshWholesalePricing,wholesaleEffectivePrice,wholesalePriceSaveNotice,wholesalePriceDraft,wholesalePriceChanged,wholesalePriceValidation,wholesalePriceItems,wholesaleScopeDraft,wholesaleScopeChanged,wholesaleScopeValidation,wholesaleScopePayload,wholesaleConfigurationDraft,wholesaleConfigurationChanged,wholesaleConfigurationValidation,wholesaleConfigurationPayload,wholesaleConfigurationUser,readWholesalePriceAttempt,rememberWholesalePriceAttempt,clearWholesalePriceAttempt} from '../app/wholesale-pricing-utils.mjs';
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
 assert.match(wholesalePriceSaveNotice('configure',{enabled:true,mode:'selected'},{changedCount:1,notifiedCount:5}),/مفعّل للمستخدمين المحددين.*إرسال إشعار/);
 assert.match(wholesalePriceSaveNotice('configure',{enabled:false,mode:'all'},{changedCount:1,notifiedCount:0}),/متوقف للجميع مع الاحتفاظ بالاختيارات/);
 assert.doesNotMatch(wholesalePriceSaveNotice('configure',{enabled:false,mode:'all'},{changedCount:1,notifiedCount:0}),/إرسال إشعار/);
});

test('configuration retry acknowledgement reports confirmed current state after another manager changed the policy',()=>{
 const original={enabled:true,mode:'all',userIds:[],expectedRevision:4};
 const currentOff=wholesalePriceSaveNotice('configure',original,{enabled:false,scopeMode:'selected',changedCount:1,notifiedCount:2});
 assert.match(currentOff,/الحالة الحالية: متوقف للجميع/);assert.doesNotMatch(currentOff,/مفعّل|تشغيله/);
 const currentSubset=wholesalePriceSaveNotice('configure',original,{enabled:true,scopeMode:'selected',changedCount:1,notifiedCount:0});
 assert.match(currentSubset,/الحالة الحالية: مفعّل للمستخدمين المحددين/);assert.doesNotMatch(currentSubset,/مفعّل لجميع المستخدمين|إرسال إشعار/);
 const noChange=wholesalePriceSaveNotice('configure',original,{enabled:false,scopeMode:'all',changedCount:0,notifiedCount:2});
 assert.match(noChange,/متوقف للجميع/);assert.doesNotMatch(noChange,/إرسال إشعار/);
});

test('legacy toggle and scope retries report current policy without implying the old request was reapplied',()=>{
 const oldToggle=wholesalePriceSaveNotice('toggle',{enabled:true,expectedRevision:4},{enabled:false,scopeMode:'selected',changedCount:1,notifiedCount:1});
 assert.match(oldToggle,/الحالة الحالية: متوقف للجميع/);assert.doesNotMatch(oldToggle,/تم تشغيل|مفعّل/);
 const oldScope=wholesalePriceSaveNotice('scope',{mode:'selected',userIds:['one'],expectedRevision:5},{enabled:true,scopeMode:'all',changedCount:1,notifiedCount:0});
 assert.match(oldScope,/الحالة الحالية: مفعّل لجميع المستخدمين/);assert.doesNotMatch(oldScope,/للمستخدمين المحددين|إرسال إشعار/);
 const noScopeMetadata=wholesalePriceSaveNotice('toggle',{enabled:true},{enabled:true,changedCount:0,notifiedCount:0});
 assert.match(noScopeMetadata,/الحالة الحالية: مفعّل\./);assert.doesNotMatch(noScopeMetadata,/لجميع المستخدمين|للمستخدمين المحددين|إرسال إشعار/);
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

test('one configuration saves activation and selection atomically and disabling preserves users',()=>{
 const state={enabled:true,scopeConfigured:true,scopeMode:'selected',selectedUserIds:['two'],eligibleUsers:[{id:'one'},{id:'two'}]};
 const saved=wholesaleConfigurationDraft(state),off={...saved,enabled:false};
 assert.deepEqual(saved,{enabled:true,mode:'selected',userIds:['two']});
 assert.equal(wholesaleConfigurationChanged(state,null),false);assert.equal(wholesaleConfigurationChanged(state,saved),false);assert.equal(wholesaleConfigurationChanged(state,off),true);
 assert.deepEqual(wholesaleConfigurationPayload(off,18),{enabled:false,mode:'selected',userIds:['two'],expectedRevision:18});
 assert.equal(wholesaleConfigurationValidation({enabled:false,mode:'selected',userIds:[]},state.eligibleUsers),'');
 assert.ok(wholesaleConfigurationValidation({enabled:true,mode:'selected',userIds:[]},state.eligibleUsers));
 assert.ok(wholesaleConfigurationValidation({...off,userIds:['gone']},state.eligibleUsers));
 assert.ok(wholesaleConfigurationValidation({...off,enabled:'false'},state.eligibleUsers));
 assert.equal(wholesaleConfigurationChanged({...state,scopeConfigured:false},saved),true);
});

test('unified checklist removes one user from all and restores future-inclusive all when every user is checked',()=>{
 const users=[{id:'one'},{id:'three'},{id:'two'}],all={enabled:false,mode:'all',userIds:[]};
 const subset=wholesaleConfigurationUser(all,'two',false,users);
 assert.deepEqual(subset,{enabled:false,mode:'selected',userIds:['one','three']});
 const restored=wholesaleConfigurationUser(subset,'two',true,users);
 assert.deepEqual(restored,all);assert.deepEqual(wholesaleConfigurationPayload(restored,12),{enabled:false,mode:'all',userIds:[],expectedRevision:12});
 assert.equal(wholesaleConfigurationUser(all,'unknown',false,users),all);
 assert.deepEqual(all,{enabled:false,mode:'all',userIds:[]});
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
 assert.ok(sections.flatMap(([,rows])=>rows).some(([id,label])=>id==='wholesalePricing'&&label==='أسعار المواد'));
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
  const configureAttempt={...scopeAttempt,action:'configure',payload:{enabled:false,mode:'selected',userIds:scopeAttempt.payload.userIds,expectedRevision:11}};rememberWholesalePriceAttempt('one',configureAttempt);assert.deepEqual(readWholesalePriceAttempt('one'),configureAttempt);
  const emptyOff={...configureAttempt,payload:{...configureAttempt.payload,userIds:[]}};rememberWholesalePriceAttempt('one',emptyOff);assert.deepEqual(readWholesalePriceAttempt('one'),emptyOff);
  for(const payload of [{...emptyOff.payload,enabled:true},{...emptyOff.payload,enabled:undefined},{...configureAttempt.payload,expectedRevision:-1}]){rememberWholesalePriceAttempt('one',{...configureAttempt,payload});assert.equal(readWholesalePriceAttempt('one'),null);}
  rememberWholesalePriceAttempt('one',{...configureAttempt,payload:{enabled:true,mode:'all',userIds:[],expectedRevision:12}});assert.equal(readWholesalePriceAttempt('one').action,'configure');
  globalThis.sessionStorage={getItem:()=>null,setItem:()=>{throw new Error('Storage unavailable');}};
  assert.equal(rememberWholesalePriceAttempt('one',attempt),false);
 }finally{if(previous===undefined)delete globalThis.sessionStorage;else globalThis.sessionStorage=previous;}
});

test('automatic floor uses the current quote even when a disabled manual price is saved',()=>{
 const automatic={id:1,minPrice:83000,enabled:false,cost:61200.25,effectiveMinPrice:61200.25,floorSource:'cost'};
 assert.deepEqual(wholesaleEffectivePrice(automatic),{source:'cost',amount:61200.25});
 assert.deepEqual(wholesaleEffectivePrice({...automatic,minPrice:null}),{source:'cost',amount:61200.25});
 assert.deepEqual(wholesaleEffectivePrice({...automatic,effectiveMinPrice:61200.25173}),{source:'cost',amount:61200.26});
 assert.deepEqual(wholesaleEffectivePrice(automatic,{enabled:true,minPrice:'83000'}),{source:'configured',amount:83000});
 const manual={...automatic,minPrice:70000,enabled:true,floorSource:'configured',effectiveMinPrice:70000};
 assert.deepEqual(wholesaleEffectivePrice(manual,{minPrice:'70000',enabled:false}),{source:'cost',amount:61200.25});
 assert.deepEqual(wholesalePriceItems([automatic],{1:{minPrice:'83000',enabled:true}})[0].minPrice,83000);
 assert.deepEqual(wholesalePriceItems([manual],{1:{minPrice:'70000',enabled:false}})[0].minPrice,70000);
});

test('personal pricing management cannot reveal a numeric automatic floor on load or when previewing an unchecked override',()=>{
 const row={minPrice:92000,enabled:false,cost:67911,effectiveMinPrice:67911,floorSource:'cost'};
 assert.deepEqual(wholesaleEffectivePrice(row,undefined,true),{source:'cost',amount:null});
 assert.deepEqual(wholesaleEffectivePrice({...row,personalPriceBasis:true}),{source:'cost',amount:null});
 assert.deepEqual(wholesaleEffectivePrice({...row,enabled:true},{enabled:false,minPrice:'92000'},true),{source:'cost',amount:null});
 assert.deepEqual(wholesaleEffectivePrice({...row,enabled:true},undefined,true),{source:'configured',amount:92000});
});

test('live valuation refresh keeps the draft editing baseline including the original price and scope revisions',()=>{
 const old={revision:8,scopeMode:'selected',products:[{id:1,minPrice:123000,enabled:false,revision:5,cost:64000,floorSource:'cost',effectiveMinPrice:64000}]};
 const fresh={revision:10,scopeMode:'all',products:[{id:1,minPrice:150000,enabled:true,revision:9,cost:66350,floorSource:'configured',effectiveMinPrice:150000}]};
 const retained=refreshWholesalePricing(old,fresh,true);
 assert.equal(retained.scopeMode,'selected');assert.equal(retained.revision,8);
 const row=retained.products[0];assert.equal(row.revision,5);
 assert.deepEqual(wholesaleEffectivePrice(row),{source:'cost',amount:66350});
 const expected=wholesalePriceItems([row],{1:{enabled:true,minPrice:'149000'}});
 assert.deepEqual(expected,[{productId:1,minPrice:149000,enabled:true,expectedRevision:5}]);
 assert.equal(old.products[0].cost,64000);
 assert.equal(refreshWholesalePricing(old,fresh,false),fresh);
});
