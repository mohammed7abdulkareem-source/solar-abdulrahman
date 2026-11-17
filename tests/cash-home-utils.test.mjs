import test from 'node:test';
import assert from 'node:assert/strict';
import {workspaceURL} from '../app/workspace-history.mjs';
import {cashAvailableTotals,cashPendingSnapshot,filterCashOwners,cashOwnerCanPost,cashOwnerDescription} from '../app/cash-home-utils.mjs';
const staff={id:'sender',active:true,is_admin:false,user_type:'admin_staff',permissions:{cash:true}};
const admin={...staff,id:'admin',is_admin:true};
const row=(id='one',amount=40)=>({id,sender_id:'sender',recipient_id:'recipient',senderName:'سفيان',recipientName:'محمد',amount,currency:'IQD',created_at:'2026-11-17T10:00:00Z',status:'pending'});
const snapshot=rows=>({summary:{pendingCount:rows.length,pendingIQD:rows.reduce((sum,r)=>sum+Number(r.amount),0)},pendingTransfers:rows});

test('available cash uses its authoritative fields only and never adds pending or transit',()=>{
 assert.deepEqual(cashAvailableTotals({summary:{availableIQD:500,availableUSD:12.25,IQD:900,transit:400,pendingIQD:400}}),{IQD:500,USD:12.25});
 assert.deepEqual(cashAvailableTotals({summary:{availableIQD:-25,availableUSD:0}}),{IQD:-25,USD:0});
 for(const data of [null,{summary:{IQD:500,USD:10}},{summary:{availableIQD:null,availableUSD:0}},{summary:{availableIQD:0,availableUSD:'NaN'}}])assert.throws(()=>cashAvailableTotals(data));
});
test('pending transfers retain exact parties and amount without expenses or unrelated details',()=>{
 const input={...row(),expense:12,expense_note:'hidden expense note',notes:'hidden notes',bankAccount:'hidden'};
 const result=cashPendingSnapshot(snapshot([input]),staff);
 assert.equal(result.total,40);assert.equal(result.count,1);assert.deepEqual(result.rows,[row()]);
 assert.deepEqual(Object.keys(result.rows[0]).sort(),Object.keys(row()).sort());
});
test('staff sees only own incoming or outgoing pending rows while admin respects optional owner scope',()=>{
 const ownIncoming={...row('two'),sender_id:'other',recipient_id:'sender'};
 assert.equal(cashPendingSnapshot(snapshot([row(),ownIncoming]),staff).count,2);
 const foreign={...row('foreign'),sender_id:'foreign',recipient_id:'another'};
 assert.throws(()=>cashPendingSnapshot(snapshot([row(),foreign]),staff));
 assert.equal(cashPendingSnapshot(snapshot([row(),foreign]),admin).count,2);
 assert.throws(()=>cashPendingSnapshot(snapshot([row(),foreign]),admin,'sender'));
 assert.equal(cashPendingSnapshot(snapshot([row(),ownIncoming]),admin,'sender').count,2);
 assert.throws(()=>cashPendingSnapshot(snapshot([]),{...staff,active:false}));
 assert.throws(()=>cashPendingSnapshot(snapshot([]),{...admin,user_type:'warehouse'}));
});
test('missing, inconsistent and unsafe pending snapshots fail instead of showing a false zero',()=>{
 assert.deepEqual(cashPendingSnapshot(snapshot([]),staff),{rows:[],total:0,count:0});
 for(const data of [null,{summary:{transit:0}},{...snapshot([row()]),summary:{pendingIQD:0,pendingCount:1}},snapshot([row(),row()]),snapshot([{...row(),amount:0}]),snapshot([{...row(),amount:true}]),snapshot([{...row(),status:'accepted'}]),snapshot([{...row(),currency:'USD'}]),snapshot([{...row(),senderName:''}]),snapshot([{...row(),created_at:'bad date'}]),{...snapshot([row()]),summary:{pendingIQD:40,pendingCount:0}}])assert.throws(()=>cashPendingSnapshot(data,staff));
});
test('pending summary validates fractional numeric values without imposing two-decimal rounding',()=>{
 const data=snapshot([row('a',0.1),row('b','0.2'),row('c',0.0004)]);data.summary.pendingIQD=0.3004;
 const result=cashPendingSnapshot(data,staff);
 assert.equal(result.rows[2].amount,0.0004);assert.equal(result.total,0.3004);
 assert.throws(()=>cashPendingSnapshot({...data,summary:{...data.summary,pendingIQD:0.31}},staff));
});
test('cash directory search keeps funded inactive accounts while posting eligibility excludes them',()=>{
 const owners=[{id:'a',name:'أشرف',IQD:100,USD:0,active:true,userType:'admin_staff'},{id:'b',name:'إبراهيم',IQD:-12,USD:4,active:false,userType:'admin_staff'},{id:'c',name:'المخزن',IQD:5,USD:0,active:true,userType:'warehouse'},{id:'d',name:'المهندس',IQD:0,USD:7,active:true,userType:'installer'}];
 assert.deepEqual(filterCashOwners(owners,'اشرف'),[owners[0]]);
 assert.deepEqual(filterCashOwners(owners,'ابراهيم'),[owners[1]]);
 assert.equal(filterCashOwners(owners,'').length,4);
 assert.deepEqual(owners.filter(cashOwnerCanPost),[owners[0]]);
 assert.equal(cashOwnerCanPost({...owners[0],userType:undefined,user_type:'warehouse'}),false);
 assert.equal(cashOwnerDescription(owners[1]),'حساب موقوف · إداري');
 assert.equal(cashOwnerDescription(owners[2]),'مسؤول مخزن');
 assert.equal(owners[1].IQD,-12);
});

test('leaving an exact pending-transfer route removes its cash selection from the next section',()=>{
 const current='https://example.test/?section=cash&cashView=transfers&cashOwner=sender&cashTransfer=pending-one&utm_source=shortcut';
 for(const section of ['home','sale']){
  const target=new URL(workspaceURL(section,current),'https://example.test');
  assert.equal(target.searchParams.has('cashTransfer'),false);
  assert.equal(target.searchParams.has('cashOwner'),false);
  assert.equal(target.searchParams.has('cashView'),false);
  assert.equal(target.searchParams.get('section'),section==='home'?null:section);
  assert.equal(target.searchParams.get('utm_source'),'shortcut');
 }
});
