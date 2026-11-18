import test from 'node:test';
import assert from 'node:assert/strict';
import {cashBalance,cashRowsFor,canOpenPage,canSeeCash,isAdministrator,canDeleteSale} from '../app/access-utils.mjs';
const rows=[
 {id:1,cash:true,createdBy:'admin',cashboxUserId:'staff',kind:'cash_income',total:500},
 {id:2,cash:true,createdBy:'staff',cashboxUserId:'staff',kind:'cash_expense',total:70},
 {id:3,cash:true,createdBy:'other',kind:'cash_income',total:900},
 {id:4,cash:false,createdBy:'staff',kind:'sale',total:800},
 {id:5,cash:true,createdBy:null,kind:'cash_income',total:40}
];
test('sales grants allow browsing and direct deletion of the seller’s own receipts',()=>{
 const p={id:'owner',active:true,user_type:'admin_staff',permissions:{sale:true,salesDeleteOwn:false}};
 assert.equal(canOpenPage(p,'salesHistory'),true);
 assert.equal(canDeleteSale(p,'owner'),true);
 assert.equal(canDeleteSale(p,'other'),false);
 assert.equal(canDeleteSale({...p,is_admin:true},'other'),true);
 for(const profile of [{...p,active:false},{...p,user_type:'warehouse',is_admin:true},{...p,user_type:'installer',is_admin:true}]){
  assert.equal(canOpenPage(profile,'salesHistory'),false);assert.equal(canDeleteSale(profile,'owner'),false);
 }
});
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
test('create-only customer permission opens the own-customer workspace without unrelated permissions',()=>{
 const creator={active:true,permissions:{customerCreate:true}};
 assert.equal(canOpenPage(creator,'customers'),true);
 assert.equal(canOpenPage(creator,'customerCreate'),true);
 assert.equal(canOpenPage({active:true,permissions:{customers:true}},'customerCreate'),true);
 for(const p of [{active:true,permissions:{}},{...creator,active:false},{...creator,user_type:'warehouse'},{...creator,user_type:'installer'}])assert.equal(canOpenPage(p,'customerCreate'),false);
 for(const page of ['users','operationControl','cash','customerStatement','customerReconcile'])assert.equal(canOpenPage(creator,page),false);
 assert.equal(canOpenPage({active:true,permissions:{}},'customers'),false);
 assert.equal(canOpenPage({...creator,user_type:'warehouse'},'customers'),false);
 assert.equal(canOpenPage({...creator,user_type:'installer'},'customers'),false);
});

test('profit settlement permission opens only the own-profit workspace',()=>{
 const p={active:true,permissions:{profitSettlement:true}};
 assert.equal(canOpenPage(p,'profit'),true);
 for(const page of ['cash','users','capital'])assert.equal(canOpenPage(p,page),false);
 assert.equal(canOpenPage({...p,user_type:'installer'},'profit'),false);
 assert.equal(canOpenPage({...p,user_type:'warehouse'},'profit'),false);
 assert.equal(canOpenPage({active:true,permissions:{}},'profit'),false);
});

test('staff activity is visible only to active office administrators even if a stale custom permission is present',()=>{
 const profile={active:true,user_type:'admin_staff',permissions:{userActivity:true}};
 assert.equal(canOpenPage({...profile,is_admin:true},'userActivity'),true);
 for(const restricted of [profile,{...profile,user_type:'warehouse',is_admin:true},{...profile,user_type:'installer',is_admin:true},{...profile,active:false,is_admin:true}]){
  assert.equal(canOpenPage(restricted,'userActivity'),false);
 }
});

test('quote and warranty alone never open financial pages, prior sales, or receipt deletion',()=>{
 const profile={id:'owner',active:true,is_admin:false,user_type:'admin_staff',permissions:{
  tahseel:true,tahseelFull:true,ownSales:true,ownProfit:true,ownPayments:true,ownCustomers:true,salesDeleteOwn:true
 }};
 assert.equal(canOpenPage(profile,'tahseel'),true);
 assert.equal(canOpenPage(profile,'warranty'),true);
 for(const page of ['cash','profit','sale','system','exchangeRate','salesHistory','paymentHistory','deletionRequests'])assert.equal(canOpenPage(profile,page),false,page);
 assert.equal(canDeleteSale(profile,'owner'),false);
 assert.equal(canOpenPage({...profile,permissions:{...profile.permissions,warranty:false}},'warranty'),false);
 const sale={...profile,permissions:{sale:true}};
 assert.equal(canOpenPage(sale,'salesHistory'),true);
 assert.equal(canOpenPage(sale,'deletionRequests'),false);
 assert.equal(canOpenPage({...sale,permissions:{sale:true,salesHistory:false}},'salesHistory'),false);
 assert.equal(canOpenPage({...profile,permissions:{deletionRequests:true}},'deletionRequests'),true);
});
