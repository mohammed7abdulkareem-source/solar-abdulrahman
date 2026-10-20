import test from 'node:test';
import assert from 'node:assert/strict';
import {searchCategories,searchSections,balanceCaption} from '../app/quick-search-utils.mjs';

test('quick search categories follow live role capabilities even with stale administrator flags',()=>{
 const p={active:true,user_type:'admin_staff',is_admin:false,permissions:{cash:true}};
 assert.deepEqual(searchCategories(p),['all']);
 assert.deepEqual(searchCategories({...p,permissions:{customerCreate:true,sale:true,suppliers:true}}),['all','customers','products','suppliers']);
 assert.deepEqual(searchCategories({...p,is_admin:true}),['all','customers','products','suppliers']);
 assert.deepEqual(searchCategories({...p,is_admin:true,user_type:'warehouse'}),['all','products']);
 assert.deepEqual(searchCategories({...p,is_admin:true,user_type:'installer'}),['all']);
 assert.deepEqual(searchCategories({...p,active:false,is_admin:true,user_type:'warehouse'}),['all']);
});
test('section shortcuts search Arabic words in any order and exclude unauthorized destinations',()=>{
 const groups=[['sales',[['sale','فاتورة بَيْع جملة'],['purchase','فاتورة شراء'],['users','المستخدمون']]]];
 const p={active:true,user_type:'admin_staff',permissions:{sale:true}};
 assert.deepEqual(searchSections(groups,p,'جملة بيع'),[['sale','فاتورة بَيْع جملة']]);
 assert.deepEqual(searchSections(groups,p,'فاتورة'),[['sale','فاتورة بَيْع جملة']]);
 assert.deepEqual(searchSections(groups,p,''),[]);
});
test('account captions distinguish a customer debt, credit and settled balance from supplier debt',()=>{
 assert.equal(balanceCaption(100),'مطلوب من الزبون');
 assert.equal(balanceCaption(-100),'رصيد للزبون');
 assert.equal(balanceCaption(0),'الحساب مسدد');
 assert.equal(balanceCaption(100,true),'مستحق للمورد');
 assert.equal(balanceCaption(-100,true),'رصيدنا عند المورد');
});
