import test from 'node:test';
import assert from 'node:assert/strict';
import {cashBalanceSnapshot,currentCashBalances} from '../app/cash-read-balances.mjs';

const seller={id:'seller',active:true,user_type:'admin_staff',is_admin:false,permissions:{ownSales:true,cash:true}};
const amount=(IQD,USD=0,usdBook=0)=>({IQD,USD,usdBook});
const response=(profile=seller)=>({asOf:'2026-11-17T12:00:00Z',ownerId:profile.is_admin?null:profile.id,summary:amount(333331,14.25,21660),owners:[{id:profile.id,...amount(333331,14.25,21660)}]});

test('own cash includes protected receipt effects without creating synthetic transactions',()=>{
 const data=response(),snapshot=cashBalanceSnapshot({...data,rows:[{receiptNo:991,notes:'FOREIGN'}]},seller);
 assert.deepEqual(currentCashBalances(snapshot,seller).own,amount(333331,14.25,21660));
 assert.equal('rows' in snapshot,false);assert.ok(!JSON.stringify(snapshot).includes('FOREIGN'));
 assert.deepEqual(snapshot.owners,[{id:'seller',...amount(333331,14.25,21660)}]);
});
test('admin company amount uses authoritative summary including inactive owners and transit',()=>{
 const admin={...seller,is_admin:true},data={...response(admin),summary:amount(1050,25.5,37500),owners:[{id:'seller',...amount(100)},{id:'inactive',...amount(700,25.5,37500)},{id:null,...amount(250)}]};
 const current=currentCashBalances(cashBalanceSnapshot(data,admin),admin);
 assert.deepEqual(current.total,amount(1050,25.5,37500));assert.deepEqual(current.own,amount(100));
});
test('zero cash remains confirmed zero only after a successful valid response',()=>{
 const data={...response(),summary:amount(0),owners:[{id:'seller',...amount(0)}]};
 assert.deepEqual(currentCashBalances(cashBalanceSnapshot(data,seller),seller).own,amount(0));
 assert.equal(currentCashBalances(null,seller),null);
});
test('cash snapshots are synchronously invalidated by account or authorization changes',()=>{
 const admin={...seller,is_admin:true},snapshot=cashBalanceSnapshot(response(admin),admin);
 for(const next of [seller,{...admin,id:'other'},{...admin,active:false},{...admin,user_type:'warehouse'},{...admin,permissions:{cash:false}}])assert.equal(currentCashBalances(snapshot,next),null);
 assert.ok(currentCashBalances(snapshot,{...admin,permissions:{cash:true,ownSales:true}}));
});
test('ordinary callers reject other-owner, admin and malformed monetary snapshots as a whole',()=>{
 for(const data of [{...response(),ownerId:null},{...response(),owners:[{id:'foreign',...amount(9)}]},{...response(),owners:[...response().owners,{id:null,...amount(9)}]},{...response(),owners:[]},{...response(),summary:{...amount(1),USD:null}},{...response(),summary:amount(Infinity)},{...response(),asOf:''}])assert.throws(()=>cashBalanceSnapshot(data,seller),{code:'CASH_BALANCE_SCOPE_MISMATCH'});
});
test('only approved numeric balance fields survive the read projection and currencies stay separate',()=>{
 const data=response();data.owners[0].notes='FOREIGN';data.summary.receiptNo=991;
 const snapshot=cashBalanceSnapshot(data,seller);assert.deepEqual(snapshot.summary,amount(333331,14.25,21660));assert.ok(!JSON.stringify(snapshot).includes('FOREIGN'));assert.ok(!JSON.stringify(snapshot).includes('991'));
});
