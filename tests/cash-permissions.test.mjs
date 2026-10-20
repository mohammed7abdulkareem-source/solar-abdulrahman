import test from 'node:test';
import assert from 'node:assert/strict';
import {allowedCashModes,canUseCash} from '../app/cash-permissions.mjs';
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
 assert.deepEqual(allowedCashModes({...user,permissions:{cashAdminTools:true}}),['capital_deposit','capital_withdraw']);
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
