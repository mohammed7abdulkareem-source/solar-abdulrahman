import test from 'node:test';
import assert from 'node:assert/strict';
import {CASH_TRANSFER_FRESH_MS,cashTransferBalance,cashTransferScopedRows,cashTransferActions,cashTransferFullAmount,cashTransferCanCover} from '../app/cash-transfer-presentation.mjs';
const profile={id:'a',active:true,user_type:'admin_staff',is_admin:false,permissions:{cashTransferSend:true,financeReceive:true}};
test('transfer balances cannot display another actor, failed, offline, expired or unknown balance as confirmed',()=>{
 const snapshot={scope:'a:send:receive',readAt:1000,data:{balance:'12345.25'}};
 assert.equal(cashTransferBalance(snapshot,snapshot.scope,'ready',1001),12345.25);
 for(const state of ['loading','error','offline','uncertain'])assert.equal(cashTransferBalance(snapshot,snapshot.scope,state,1001),null);
 assert.equal(cashTransferBalance(snapshot,'a:receive','ready',1001),null);
 assert.equal(cashTransferBalance(snapshot,snapshot.scope,'ready',1000+CASH_TRANSFER_FRESH_MS),null);
 assert.equal(cashTransferBalance(snapshot,snapshot.scope,'ready',999),null);
 for(const balance of [null,undefined,'',false,'bad',Infinity])assert.equal(cashTransferBalance({...snapshot,data:{balance}},snapshot.scope,'ready',1001),null);
 assert.equal(cashTransferBalance({...snapshot,data:{balance:0}},snapshot.scope,'ready',1001),0);
});
test('pending records and decisions remain scoped to actual sender and recipient even for admin',()=>{
 const own={id:'own',sender_id:'a',recipient_id:'b',status:'pending'},incoming={id:'in',sender_id:'b',recipient_id:'a',status:'pending'},foreign={id:'foreign',sender_id:'b',recipient_id:'c',status:'pending'};
 assert.deepEqual(cashTransferScopedRows([own,incoming,foreign],profile),[own,incoming]);
 assert.deepEqual(cashTransferScopedRows([foreign],{...profile,is_admin:true}),[foreign]);
 assert.deepEqual(cashTransferScopedRows([own],{...profile,user_type:'warehouse',is_admin:true}),[]);
 assert.deepEqual(cashTransferActions(own,profile,true),['cancelled']);
 assert.deepEqual(cashTransferActions(incoming,profile,true),['accepted','rejected']);
 assert.deepEqual(cashTransferActions(incoming,profile,false),[]);
 assert.deepEqual(cashTransferActions(foreign,{...profile,is_admin:true},true),[]);
 assert.deepEqual(cashTransferActions({...own,status:'accepted'},profile,true),[]);
});
test('full transfer amount keeps optional expense separate and preserves cents',()=>{
 assert.equal(cashTransferFullAmount(500000,25000),'475000');
 assert.equal(cashTransferFullAmount(100.25,10.1),'90.15');
 assert.equal(cashTransferFullAmount(123.456),'123.456');
 assert.equal(cashTransferFullAmount(0.3,0.1),'0.2');
 assert.equal(cashTransferFullAmount(0.000001,0),'0.000001');
 assert.equal(cashTransferCanCover(0.3,0.2,0.1),true);
 assert.equal(cashTransferCanCover(123.456,123.46),false);
 assert.equal(cashTransferFullAmount(100,100),null);
 for(const balance of [null,undefined,NaN,0,-10,1e12+1])assert.equal(cashTransferFullAmount(balance),null);
 assert.equal(cashTransferFullAmount(100,-1),null);
});
