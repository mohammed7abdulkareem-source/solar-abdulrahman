import test from 'node:test';
import assert from 'node:assert/strict';
import {supplierAccount,compactPeriod} from '../app/compact-party-utils.mjs';
import {invoiceLines,groupedInvoicesBody} from '../app/party-invoice-reports.mjs';
import {supplierDocument} from '../app/supplier-utils.mjs';
import {cashKind} from '../app/cash-utils.mjs';
import {cashTypeOptions,cashGroups} from '../app/cash-finance-utils.mjs';

const before={id:419,kind:'purchase',party_name:'مورد',party_id:8,receipt_no:41,created_at:'2026-11-01T10:00:00Z',cash:false,total:1000,subtotal:1000,source_subtotal:1000,account_amount:1000,account_currency:'IQD',source_currency:'IQD',market_rate:1,exchange_rate:1,cash_currency:'IQD',cash_amount:0,expenses:0,pricing_revision:0,warehouse_id:1,warehouse_name:'الرئيسي'};
const current={...before,total:720,subtotal:720,source_subtotal:720,account_amount:720,pricing_revision:1};
const beforeItems=[{product_id:7,product_name:'مادة أصلية',qty:10,price:100,source_price:100,cost:100}];
const currentItems=[{...beforeItems[0],qty:8,price:90,source_price:90,cost:90}];
const entry={id:1,revision:0,currency:'IQD',delta:1000,created_at:before.created_at,rate:1,ledgerAmount:1000,transaction:current,items:currentItems,originalTransaction:before,originalItems:beforeItems};
const correction={id:2,revision:0,currency:'IQD',delta:-280,ledgerAmount:280,created_at:'2026-11-18T12:00:00Z',correction_for:419,transaction:null,archivedPurchase:{id:419,receiptNo:41,party:'مورد',entryRole:'correction'}};

test('supplier ledger retains original amount/materials and exposes current corrected receipt separately',()=>{
 const account=supplierAccount({supplierId:8,revision:0,currency:'IQD',rows:[entry,correction]},'مورد');
 const row=account.rows[0],period=compactPeriod(account.rows);
 assert.equal(row.amount,1000);assert.equal(row.effect,1000);assert.match(row.label,/أصل الوصل قبل التصحيح/);
 assert.equal(row.original.items[0].qty,10);assert.equal(row.original.total,1000);assert.equal(row.original.pricingRevision,0);
 assert.equal(row.currentOriginal.items[0].qty,8);assert.equal(row.currentOriginal.total,720);assert.equal(row.currentOriginal.pricingRevision,1);
 assert.equal(account.rows[1].label,'تصحيح شراء');assert.equal(account.rows[1].amount,280);assert.equal(period.balance,720);
 assert.equal(invoiceLines(account,row).items[0].price,100);
 const report=groupedInvoicesBody(account,{...period,rows:period.rows.filter(r=>r.category==='invoices')},'','');
 assert.match(report,/<td class="number">10<\/td>/);assert.match(report,/<td class="number">100<\/td>/);assert.doesNotMatch(report,/<td class="number">90<\/td>/);
 assert.equal(supplierDocument(row.original).total,'1,000 د.ع');assert.equal(supplierDocument(row.currentOriginal).total,'720 د.ع');
});
test('cash purchase original ledger keeps bill amount despite zero supplier effect',()=>{
 const account=supplierAccount({revision:0,currency:'IQD',rows:[{...entry,delta:0,originalTransaction:{...before,cash:true,cash_amount:1000},transaction:{...current,cash:true,cash_amount:720}}]},'مورد');
 assert.equal(account.rows[0].amount,1000);assert.equal(account.rows[0].effect,0);assert.equal(compactPeriod(account.rows).balance,0);
});
test('foreign receipt projection cannot expose original/current snapshots or ledger amounts',()=>{
 const account=supplierAccount({revision:0,currency:'IQD',rows:[{...entry,receiptRestricted:true,delta:20,ledgerAmount:1000}]},'مورد');
 const row=account.rows[0];assert.equal(row.amount,20);assert.equal(row.original,null);assert.equal(row.currentOriginal,undefined);assert.equal(row.receiptNo,null);assert.equal(JSON.stringify(row).includes('مادة أصلية'),false);
});
test('purchase correction has a distinct truthful cash filter label and does not rename cancellations',()=>{
 assert.equal(cashKind('purchase_correction'),'تصحيح شراء');assert.equal(cashKind('purchase_refund'),'استرجاع شراء ملغى');
 assert.ok(cashTypeOptions.some(([key,label])=>key==='purchase_correction'&&label==='تصحيح شراء'));assert.ok(cashGroups.expenses.includes('purchase_correction'));
});
