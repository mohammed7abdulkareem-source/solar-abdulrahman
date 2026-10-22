import test from 'node:test';
import assert from 'node:assert/strict';
import {savedSaleInvoice} from '../app/invoice-save-result.mjs';
import {salesDocument} from '../app/sales-document.mjs';

test('new-sale exports retain the committed receipt after the next editor is cleared',()=>{
 const draft={kind:'sale',draft:true,party:'زبون الاختبار',date:'2026-10-21T20:59:59Z',total:999,creatorName:'المسؤول',creatorPhone:'07700000000',customerPhone:'07800000000',warehouseName:'المخزن الرئيسي',cash:false,items:[{id:7,name:'بطارية أصلية',brand:'FULLMAX',qty:2,price:150000}]};
 const receipt={id:44,receiptNo:18,total:300000,invoiceAccount:{asOf:'2026-10-22T07:00:00Z',available:true,previousBalance:1700000,invoiceTotal:300000,paidNow:0,balanceAfter:2000000,lastPayment:{amount:300000,receiptNo:16,date:'2026-10-20T12:00:00Z'}},warrantyToken:'11111111-1111-1111-1111-111111111111',warehouseQrToken:'22222222-2222-2222-2222-222222222222',warranty:{enabled:true,items:[{id:7,duration:2,unit:'years'}],maintenance:{duration:6,unit:'months'}}};
 const saved=savedSaleInvoice(draft,receipt),before=salesDocument(saved);
 draft.party='زبون آخر';draft.items[0].price=1;draft.items=[];draft.total=0;
 const after=salesDocument(saved);assert.deepEqual(after,before);assert.equal(saved.created_at,receipt.invoiceAccount.asOf);assert.equal(saved.draft,false);
 for(const s of ['1,700,000','2,000,000','آخر تسديد سابق','300,000','بطارية أصلية','invoiceQr','07700000000','07800000000','18'])assert.ok(after.body.includes(s),s);
 assert.doesNotMatch(after.body,/ملخص الحساب وآخر تسديد يظهران بعد حفظ الفاتورة/);
 const warehouse=salesDocument(saved,false);assert.ok(warehouse.body.includes('بطارية أصلية'));assert.ok(warehouse.body.includes('invoiceQr'));assert.doesNotMatch(warehouse.body,/1,700,000|2,000,000|150,000|300,000|الحساب السابق/);
});
