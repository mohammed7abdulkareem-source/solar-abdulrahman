import test from 'node:test';
import assert from 'node:assert/strict';
import {salesDocument} from '../app/sales-document.mjs';
import {warehouseDocument} from '../app/warehouse-utils.mjs';
import {invoiceDate,warrantyLastDay} from '../app/document-format.mjs';
const row={kind:'sale',receipt_no:4,created_at:'2026-10-19T01:00:00Z',party_name:'زبون <اختبار>',total:13720000,items:[{product_id:1,product_name:'10KW/MAGIC',qty:8,price:1715000}],warranty_token:'11111111-1111-1111-1111-111111111111',warehouse_qr_token:'22222222-2222-2222-2222-222222222222',invoice_account:{available:true,previousBalance:2000000,invoiceTotal:13720000,paidNow:0,balanceAfter:15720000,lastPayment:{receiptNo:17,date:'2026-10-18T22:00:00Z',amount:300000}},warranty:{enabled:true,items:[{id:1,duration:2,unit:'years'}],maintenance:{duration:6,unit:'months'},notes:'شروط <واضحة>'}};
test('customer receipt has fixed prior account, last payment with date/receipt, final balance and readable warranties',()=>{
 const doc=salesDocument(row);for(const s of ['الحساب السابق','2,000,000','آخر تسديد سابق','300,000','19/10/2026','17','15,720,000','آخر يوم مشمول','18/10/2028','18/04/2027','&lt;واضحة&gt;'])assert.ok(doc.body.includes(s),s);
 assert.ok(doc.body.indexOf('<svg')<doc.body.indexOf('invoiceItems'));assert.ok(!doc.body.includes('<اختبار>'));
 assert.ok(salesDocument({...row,kind:'system'}).body.includes('الحساب النهائي'));
});
test('warehouse print uses independent safe QR and keeps all financial data private',()=>{
 const doc=salesDocument(row,false);assert.equal(doc.total,'');assert.match(doc.body,/آخر يوم مشمول/);assert.match(doc.body,/<svg/);for(const s of ['invoiceAccount','آخر تسديد','2,000,000','13,720,000','1,715,000','300,000','الحساب النهائي'])assert.ok(!doc.body.includes(s),s);
 const warehouse=warehouseDocument({kind:'sale',date:row.created_at,receiptNo:4,party:'زبون',items:[{productId:1,name:'10KW/MAGIC',qty:8}],warranty:row.warranty,warehouseQrToken:row.warehouse_qr_token});assert.match(warehouse,/<svg/);assert.match(warehouse,/18\/10\/2028/);
});
test('warranty printed dates match Postgres month/year clamping and inclusive last covered day',()=>{
 assert.equal(warrantyLastDay('2024-01-31',{duration:1,unit:'months'}),'28/02/2024');assert.equal(warrantyLastDay('2024-02-29',{duration:1,unit:'years'}),'27/02/2025');assert.equal(warrantyLastDay('2026-10-19',{duration:1,unit:'days'}),'19/10/2026');assert.equal(warrantyLastDay('2026-10-19',{duration:0,unit:'days'}),null);assert.equal(invoiceDate('2026-10-18T22:00:00Z'),'19/10/2026');
});
