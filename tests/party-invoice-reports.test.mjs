import test from 'node:test';
import assert from 'node:assert/strict';
import {customerAccount,supplierAccount,compactPeriod,compactStatementBody} from '../app/compact-party-utils.mjs';
import {invoiceLines,groupedInvoicesBody} from '../app/party-invoice-reports.mjs';

test('statement preserves cash amount, filtered running balance and escaped notes',()=>{
 const account=customerAccount({id:1,name:'<عميل>',rows:[
  {id:1,date:'2026-10-01T09:00Z',kind:'sale',total:500,cash:false,receiptNo:11,notes:'<script>x</script>'},
  {id:2,date:'2026-10-02T09:00Z',kind:'sale',total:100,cash:true,receiptNo:12},
  {id:3,date:'2026-10-03T09:00Z',kind:'customer_payment',total:200,receiptNo:13}
 ]});
 const sales=compactPeriod(account.rows,'2026-10-02','','invoices');
 assert.equal(sales.opening,500);assert.equal(sales.balance,300);assert.equal(sales.rows[0].balance,500);
 const html=compactStatementBody(account,sales,'2026-10-02','');
 assert.match(html,/مبلغ الوصل/);assert.match(html,/>100<\/td>/);assert.match(html,/رصيد الحساب بنهاية الفترة: 300/);
 const all=compactStatementBody(account,compactPeriod(account.rows),'','');assert.ok(all.includes('&lt;script&gt;'));assert.ok(!all.includes('<script>'));
});

test('all customer invoices are grouped with own price snapshots, while unavailable ones remain visible',()=>{
 const account=customerAccount({id:1,name:'زبون',rows:Array.from({length:110},(_,i)=>({id:i+1,date:'2026-10-02T09:00Z',kind:'sale',total:100,cash:false,receiptNo:i+1}))});
 const period=compactPeriod(account.rows,'','','invoices');const docs={};
 for(let i=1;i<=109;i++)docs[i]={id:i,kind:'sale',items:[{product_name:'لوح <'+i+'>',qty:2,price:50}]};
 const html=groupedInvoicesBody(account,period,'','',docs);
 assert.equal((html.match(/<table data-pdf-paginate data-pdf-keep-footer-with-row>/g)||[]).length,110);
 assert.ok(html.includes('لوح &lt;1&gt;'));assert.ok(html.includes('تفاصيل المواد غير متاحة ضمن صلاحيات الحساب'));
 assert.equal(invoiceLines(account,period.rows[0],docs).items[0].total,100);
 const system=invoiceLines(account,{id:200},{200:{kind:'system',items:[{product_name:'جهاز',qty:1}]}});assert.equal(system.items[0].price,null);
});

test('supplier invoice prices stay in source currency and unknown dollar prices are not invented',()=>{
 const data={revision:0,currency:'USD',rows:[{id:1,revision:0,currency:'USD',created_at:'2026-10-01T09:00Z',delta:20,rate:1500,
  transaction:{id:10,kind:'purchase',total:30000,account_amount:20,source_currency:'USD',source_subtotal:20,expenses:0},
  items:[{product_name:'لوح',qty:2,price:15000,source_price:10}]},
  {id:2,revision:0,currency:'USD',created_at:'2026-10-02T09:00Z',delta:10,rate:1500,
  transaction:{id:11,kind:'purchase',total:15000,account_amount:10,source_currency:'IQD',source_subtotal:15000,expenses:0},
  items:[{product_name:'بطارية',qty:1,price:15000,source_price:null}]},
  {id:3,revision:0,currency:'USD',created_at:'2026-10-03T09:00Z',delta:3,rate:1500,
  transaction:{id:12,kind:'purchase',total:4500,account_amount:3,source_currency:'USD',source_subtotal:3,expenses:0},
  items:[{product_name:'سعر غير محفوظ',qty:1,price:4500,source_price:null}]}]};
 const a=supplierAccount(data,'مورد'),period=compactPeriod(a.rows,'','','invoices');
 assert.equal(invoiceLines(a,period.rows[0]).items[0].price,10);
 assert.equal(invoiceLines(a,period.rows[1]).items[0].price,15000);
 assert.equal(invoiceLines(a,period.rows[2]).items[0].price,null);
 const html=groupedInvoicesBody(a,period,'','');assert.match(html,/السعر \$/);assert.match(html,/السعر د\.ع/);
 assert.match(html,/سعر غير محفوظ/);assert.ok(!html.includes('4,500 $'));
 assert.match(html,/الرصيد بعدها: 33 \$/);
});
