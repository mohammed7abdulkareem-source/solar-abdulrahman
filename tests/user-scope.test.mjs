import test from 'node:test';
import assert from 'node:assert/strict';
import {ownUserPermissions} from '../app/user-scope.mjs';
import {canOpenPage} from '../app/access-utils.mjs';
test('global legacy capabilities become own capabilities; isolation flags cannot be disabled',()=>{
 const p=ownUserPermissions({all:true,warehouse:true,salesHistory:true,installationsAll:true,salesDeleteAll:true,ownSales:false,ownPayments:false,ownCustomers:false,ownProfit:false});
 for(const k of ['ownSales','ownPayments','ownCustomers','ownProfit','salesDeleteOwn','installations'])assert.equal(p[k],true);
 assert.equal(p.installationsAll,false);assert.equal(p.salesDeleteAll,false);assert.equal(p.all,undefined);assert.equal(p.warehouse,true);
 assert.deepEqual(ownUserPermissions(p),p);
});
test('unrelated page privileges are preserved without adding closing/deletion permissions',()=>{
 const p=ownUserPermissions({sale:true,customerPayment:true,installations:false,salesDeleteOwn:false});assert.equal(p.installations,false);assert.equal(p.salesDeleteOwn,false);assert.equal(p.sale,true);assert.equal(p.customerPayment,true);
 const profile={active:true,user_type:'admin_staff',permissions:p};assert.equal(canOpenPage(profile,'sale'),true);assert.equal(canOpenPage(profile,'users'),false);
});
