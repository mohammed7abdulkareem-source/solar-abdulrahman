import test from 'node:test';
import assert from 'node:assert/strict';
import {cashBalance,canOpenPage} from '../app/access-utils.mjs';
import {filterParties} from '../app/party-search-utils.mjs';
test('customer search matches Arabic forms, partial names and phone digits',()=>{
 const rows=[{id:1,name:'أحمد عبد الرحمن',phone:'٠٧٥٠ ١٢٣ ٤٥٦٧'},{id:2,name:'علي',phone:'07701234567'}];
 assert.equal(filterParties(rows,'احمد الرحمن')[0].id,1);
 assert.equal(filterParties(rows,'0750123')[0].id,1);
 assert.equal(filterParties(rows,'غير موجود').length,0);
});
test('pending transfer empties sender, does not credit receiver or lose company assets',()=>{
 const rows=[{cash:true,createdBy:'sender',kind:'cash_income',total:1000},{cash:true,cashboxUserId:'sender',kind:'handover_expense',cashDelta:-100},{cash:true,cashboxUserId:'sender',kind:'transfer_out',cashDelta:-900},{cash:true,kind:'transfer_transit',cashDelta:900}];
 assert.equal(cashBalance(rows,'sender'),0);assert.equal(cashBalance(rows,'receiver'),0);assert.equal(cashBalance(rows,null,true),900);
 rows.push({cash:true,kind:'transfer_transit',cashDelta:-900},{cash:true,cashboxUserId:'receiver',kind:'transfer_in',cashDelta:900});
 assert.equal(cashBalance(rows,'receiver'),900);assert.equal(cashBalance(rows,null,true),900);
});
test('finance permissions only grant transfer page; engineers cannot access it',()=>{
 const staff={active:true,user_type:'admin_staff',permissions:{financeReceive:true}};
 assert.equal(canOpenPage(staff,'cashTransfers'),true);assert.equal(canOpenPage(staff,'users'),false);assert.equal(canOpenPage(staff,'cash'),false);
 assert.equal(canOpenPage({...staff,user_type:'installer',is_admin:true},'cashTransfers'),false);
});
