import test from 'node:test';
import assert from 'node:assert/strict';
import {cashRowBalance,cashTransferFacts} from '../app/cash-ledger-display.mjs';
import {cashVisibleMovement} from '../app/cash-finance-utils.mjs';

test('wallet balances stay separate from company totals and missing historical amounts',()=>{
 assert.equal(cashRowBalance({ownerBalance:'0',balance:7200},''),0);
 assert.equal(cashRowBalance({ownerBalance:-12.34,balance:7200},''),-12.34);
 assert.equal(cashRowBalance({balance:7200},''),null);
 assert.equal(cashRowBalance({balance:0},'selected'),0);
 assert.equal(cashRowBalance({},'selected'),null);
 const row=cashVisibleMovement({receiptRestricted:true,ownerBalance:123,balance:500,party:'طرف',transfer:{sender:'اسم'}});
 assert.equal(cashRowBalance(row,'owner'),123);
 assert.equal(row.transfer,undefined);
 assert.equal(row.party,'');
});

test('incoming funds identify sender and approver independently; direct handovers identify the recorder',()=>{
 const transfer={sender:'صاحب القاصة',recipient:'المستلم',decidedBy:'المدقق',status:'accepted'};
 assert.deepEqual(cashTransferFacts('transfer_in',transfer),[
  {label:'من',value:'صاحب القاصة'},{label:'اعتمد الاستلام',value:'المدقق'}
 ]);
 assert.deepEqual(cashTransferFacts('admin_transfer_out',transfer),[
  {label:'إلى',value:'المستلم'},{label:'نفّذ التحويل',value:'المدقق'}
 ]);
 assert.deepEqual(cashTransferFacts('transfer_in',null),[{label:'من',value:'غير مسجّل'}]);
 assert.deepEqual(cashTransferFacts('sale',null),[]);
});

test('refunds identify the returning wallet, intended recipient and decision',()=>{
 const fields=cashTransferFacts('transfer_refund',{sender:'الشخص الأول',recipient:'الشخص الثاني',status:'rejected',decidedBy:'المدقق'});
 assert.deepEqual(fields.map(x=>x.label),['عادت إلى قاصة','المستلم المحدد','رفض الاستلام']);
});
