import test from 'node:test';
import assert from 'node:assert/strict';
import {wholesalePriceDraft,wholesalePriceChanged,wholesalePriceValidation,wholesalePriceItems,readWholesalePriceAttempt,rememberWholesalePriceAttempt,clearWholesalePriceAttempt} from '../app/wholesale-pricing-utils.mjs';
import {canManageWholesalePricing,canOpenPage} from '../app/access-utils.mjs';
import {sectionGroups,sections} from '../app/section-directory.mjs';

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
  globalThis.sessionStorage={getItem:()=>null,setItem:()=>{throw new Error('Storage unavailable');}};
  assert.equal(rememberWholesalePriceAttempt('one',attempt),false);
 }finally{if(previous===undefined)delete globalThis.sessionStorage;else globalThis.sessionStorage=previous;}
});
