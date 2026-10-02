import test from 'node:test';
import assert from 'node:assert/strict';
import {cashBalance,cashRowsFor,canOpenPage,canSeeCash,isAdministrator} from '../app/access-utils.mjs';
const rows=[
 {id:1,cash:true,createdBy:'admin',cashboxUserId:'staff',kind:'cash_income',total:500},
 {id:2,cash:true,createdBy:'staff',cashboxUserId:'staff',kind:'cash_expense',total:70},
 {id:3,cash:true,createdBy:'other',kind:'cash_income',total:900},
 {id:4,cash:false,createdBy:'staff',kind:'sale',total:800},
 {id:5,cash:true,createdBy:null,kind:'cash_income',total:40}
];
test('staff cash includes admin deposits into their box, excludes other boxes and credit',()=>{
 assert.equal(cashBalance(rows,'staff'),430);
 assert.deepEqual(cashRowsFor(rows,'staff').map(x=>x.id),[1,2]);
 assert.equal(cashBalance(rows,null),0);
 assert.equal(cashBalance(rows,null,true),1370);
});
test('engineer never gets cash or management, even with stale admin flags',()=>{
 const p={active:true,user_type:'installer',is_admin:true,permissions:{cash:true,profit:true}};
 assert.equal(canSeeCash(p),false);
 assert.equal(isAdministrator(p),false);
 for(const page of ['cash','capital','profit','users','sale'])assert.equal(canOpenPage(p,page),false);
 assert.equal(canOpenPage(p,'installations'),true);
});
test('permissions fail closed and staff only opens granted pages',()=>{
 assert.equal(canSeeCash(null),false);
 assert.equal(canOpenPage({active:false,is_admin:true},'cash'),false);
 assert.equal(canOpenPage({active:true,permissions:{cash:true}},'cash'),true);
 assert.equal(canOpenPage({active:true,permissions:{cash:true}},'installations'),false);
});
