import test from 'node:test';
import assert from 'node:assert/strict';
import {allowedCashModes,canUseCash,canReconcileCash,cashViewAllowed,cashPermissionOptions,canRetryCashAttempt} from '../app/cash-permissions.mjs';
import {canOpenPage} from '../app/access-utils.mjs';
import {filteredCustomers} from '../app/customer-utils.mjs';
import {cashKind,cashReceiptBody} from '../app/cash-utils.mjs';
const user={active:true,user_type:'admin_staff',is_admin:false,permissions:{cash:true}};
test('cash viewing grants no posting action; each cash permission is independent',()=>{
 assert.deepEqual(allowedCashModes(user),[]);
 const expense={...user,permissions:{cashExpense:true}};
 assert.deepEqual(allowedCashModes(expense),['expense']);assert.ok(canOpenPage(expense,'cash'));
 assert.deepEqual(allowedCashModes({...user,permissions:{cashExchange:true}}),['buy_usd','sell_usd']);
 assert.deepEqual(allowedCashModes({...user,permissions:{cashExternalProfit:true}}),['external_profit']);
 assert.deepEqual(allowedCashModes({...user,permissions:{cashAdminTools:true}}),[]);
 assert.equal(canUseCash({...user,user_type:'warehouse',is_admin:true},'cashAdminTools'),false);
});
test('debt filter excludes settled and prepaid customers but full directory remains available',()=>{
 const rows=[{name:'عليه دين',balance:100},{name:'مسدد',balance:0},{name:'رصيد دائن',balance:-50}];
 assert.deepEqual(filteredCustomers(rows,'','all','due').map(c=>c.name),['عليه دين']);
 assert.equal(filteredCustomers(rows).length,3);
});
test('external profit receipt names the profit and shows its fixed IQD value safely',()=>{
 assert.equal(cashKind('external_profit'),'أرباح خارجية');
 const html=cashReceiptBody({mode:'external_profit',currency:'USD',amount:100,rate:1660,profitAmountIQD:166000,date:'2026-10-20T12:00:00Z',note:'<service>',ownerName:'مستخدم'});
 assert.match(html,/166,000/);assert.match(html,/أرباح خارجية/);assert.match(html,/&lt;service&gt;/);
});

test('cash balance reconciliation cannot be delegated by legacy staff permissions',()=>{
 const delegated={...user,permissions:{cash:true,cashAdminTools:true,adminOnly:true,cashReconcile:true,cashReset:true,cashAdjust:true,is_admin:true}};
 for(const display_name of ['عبدالرحمن عبدالله','سفيان','أشرف']){
  const staff={...delegated,display_name};
  assert.equal(canReconcileCash(staff),false);
  assert.equal(cashViewAllowed(staff,'reconcile'),false);
  assert.equal(cashViewAllowed(staff,'admin'),false);
  assert.deepEqual(allowedCashModes(staff),[]);
  assert.equal(canUseCash(staff,'cashAdminTools'),false);
  assert.equal(canUseCash(staff,'adminOnly'),false);
 }
 assert.ok(!cashPermissionOptions.some(([key,label])=>key==='cashAdminTools'||/reconcile|reset/i.test(key)||/تصفير|مطابقة|تعديل الرصيد/.test(label)));
});
test('only an active office administrator can open set and zero controls',()=>{
 const admin={...user,id:'admin',is_admin:true,permissions:{}};
 assert.equal(canReconcileCash(admin),true);
 assert.equal(canUseCash(admin,'cashAdminTools'),true);
 assert.equal(canUseCash(admin,'adminOnly'),true);
 assert.ok(allowedCashModes(admin).includes('capital_deposit')&&allowedCashModes(admin).includes('capital_withdraw'));
 assert.equal(cashViewAllowed(admin,'reconcile'),true);
 for(const profile of [null,{...admin,active:false},{...admin,active:null},{...admin,is_admin:false},{...admin,is_admin:'true'},{...admin,user_type:'warehouse'},{...admin,user_type:'installer'}]){
  assert.equal(canReconcileCash(profile),false);
  assert.equal(cashViewAllowed(profile,'reconcile'),false);
  assert.equal(canUseCash(profile,'cashAdminTools'),false);
  assert.equal(canUseCash(profile,'adminOnly'),false);
 }
});
test('reconciliation restriction preserves independent normal cash workflows',()=>{
 const staff={...user,permissions:{cashDeposit:true,cashExpense:true,cashTransferSend:true,financeReceive:true,cashExchange:true,cashExternalProfit:true,cashAdminTools:true}};
 assert.deepEqual(allowedCashModes(staff),['deposit','expense','buy_usd','sell_usd','external_profit']);
 for(const view of ['home','box','ledger','entry','reports','expenses','transfers','profits','movement'])assert.equal(cashViewAllowed(staff,view),true);
 assert.equal(canUseCash(staff,'cashTransferSend'),true);
 assert.equal(canUseCash(staff,'financeReceive'),true);
 assert.equal(canReconcileCash(staff),false);
});

test('a restored administrative cash attempt requires current admin authority before retry',()=>{
 const attempt={id:'saved-request-id',payload:{ownerId:'staff',mode:'capital_withdraw',amount:100,currency:'IQD'}};
 const staff={...user,id:'staff',permissions:{cashAdminTools:true,cashDeposit:true,cashExpense:true}};
 assert.equal(canRetryCashAttempt(staff,attempt),false);
 assert.equal(canRetryCashAttempt({...staff,is_admin:true},attempt),true);
 assert.equal(canRetryCashAttempt({...staff,is_admin:true,active:false},attempt),false);
 assert.equal(canRetryCashAttempt(staff,{...attempt,payload:{...attempt.payload,mode:'deposit'}}),true);
 assert.equal(canRetryCashAttempt(staff,{...attempt,payload:{...attempt.payload,mode:'expense'}}),true);
 assert.equal(canRetryCashAttempt(staff,{...attempt,payload:{...attempt.payload,mode:'cash_reconcile'}}),false);
 assert.equal(canRetryCashAttempt(staff,null),false);
 assert.equal(attempt.id,'saved-request-id');
 assert.equal(attempt.payload.mode,'capital_withdraw');
});

test('external profit retry stays on the current cashbox after an admin becomes staff',()=>{
 const staff={...user,id:'staff',permissions:{cashExternalProfit:true}};
 const saved=ownerId=>({payload:{ownerId,mode:'external_profit'}});
 assert.ok(canRetryCashAttempt(staff,saved('staff')));
 assert.equal(canRetryCashAttempt(staff,saved('other')),false);
 assert.equal(canRetryCashAttempt({...staff,is_admin:true},saved('other')),true);
 assert.equal(canRetryCashAttempt({...staff,permissions:{cashExpense:true}},saved('staff')),false);
});
