import test from 'node:test';
import assert from 'node:assert/strict';
import {filterMaterialRows,materialMovementDocument,materialPrice} from '../app/material-movement-utils.mjs';
const rows=[{id:'a',date:'2026-10-01T09:00:00Z',kind:'purchase',party:'المورد',receiptNo:1,warehouseName:'الرئيسي',inQty:5,outQty:0,balance:15,createdByName:'المشتري',preparedByName:null,pricing:{kind:'purchase',unitPrice:1234567.89,lineTotal:6172839.45}},{id:'b',date:'2026-10-02T10:00:00Z',kind:'sale',party:'الزبون',receiptNo:2,warehouseName:'الرئيسي',inQty:0,outQty:3,balance:12,createdByName:'البائع',preparedByName:'المجهز',pricing:{kind:'sale',unitPrice:3000,lineTotal:9000}}];
test('filtering direction/party preserves the saved running stock balance and matches preparer',()=>{
 assert.deepEqual(filterMaterialRows(rows,'out','المجهز').map(r=>[r.id,r.balance]),[['b',12]]);
 assert.deepEqual(filterMaterialRows(rows,'all','المورد').map(r=>r.balance),[15]);
 assert.equal(materialPrice({pricing:{kind:'system_total'}}).unit,'—');
 assert.match(materialPrice({pricing:{kind:'system_total'}}).label,/غير موزّع/);
});
test('priced and unpriced PDFs retain exact parties/warehouse/preparer and mask every financial price',()=>{
 const data={product:{code:'001',name:'لوح <أ>',brand:'البراند',category:'ألواح'},withPrices:false,warehouses:[{name:'الرئيسي',beforeFirst:10,inQty:5,outQty:3,afterLast:12,currentQty:12}],scope:'all'};
 const plain=materialMovementDocument(data,rows),priced=materialMovementDocument({...data,withPrices:true},rows);
 assert.ok(!plain.includes('1,234,567.89')&&!plain.includes('6,172,839.45')&&!plain.includes('السعر / مبلغ الفقرة'));
 assert.ok(priced.includes('1,234,567.89')&&priced.includes('9,000')&&priced.includes('السعر / مبلغ الفقرة'));
 for(const text of ['المورد','الزبون','الرئيسي','المجهز','لم يُسجّل تجهيز','الرصيد بعد الحركة'])assert.ok(plain.includes(text));
 assert.ok(plain.includes('&lt;أ&gt;')&&!plain.includes('<أ>'));
});
