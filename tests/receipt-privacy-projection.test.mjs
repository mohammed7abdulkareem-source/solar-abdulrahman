import test from 'node:test';
import assert from 'node:assert/strict';
import {customerAccount,supplierAccount,compactPeriod,compactStatementBody} from '../app/compact-party-utils.mjs';
import {groupedInvoicesBody,invoiceLines} from '../app/party-invoice-reports.mjs';
import {cashStatementDetails,cashStatementNotes,cashStatementKind,cashStatementTable} from '../app/cash-statement-report.mjs';
import {cashPage} from '../app/cash-finance-utils.mjs';

test('restricted customer effects preserve running balances without creating foreign invoice cards or exports',()=>{
 const privateRow={id:'restricted:opaque',date:'2026-11-02T08:00:00Z',effect:700,receiptRestricted:true,kind:'sale',total:999999,receiptNo:'FOREIGN-991',notes:'FOREIGN-NOTE',creatorName:'FOREIGN-ACTOR',items:[{name:'FOREIGN-MATERIAL'}]};
 const account=customerAccount({id:1,name:'زبوني',rows:[{id:1,date:'2026-11-01T08:00:00Z',kind:'sale',total:300,receiptNo:12},privateRow,{id:2,date:'2026-11-03T08:00:00Z',kind:'customer_payment',total:100}]});
 const period=compactPeriod(account.rows),invoicePeriod=compactPeriod(account.rows,'','','invoices');
 assert.equal(period.balance,900);assert.deepEqual(period.rows.map(row=>row.balance),[300,1000,900]);
 assert.equal(period.invoices,300);assert.equal(invoicePeriod.balance,900);assert.equal(invoicePeriod.rows.length,1);
 assert.equal(account.rows[1].category,'adjustment');assert.equal(account.rows[1].original,null);
 assert.equal(account.rows[1].amount,700);assert.equal(account.rows[1].receiptRestricted,true);
 const html=compactStatementBody(account,period,'','')+groupedInvoicesBody(account,period,'','',{});
 for(const secret of ['FOREIGN-991','FOREIGN-NOTE','FOREIGN-ACTOR','FOREIGN-MATERIAL','999,999'])assert.ok(!html.includes(secret),secret);
 assert.ok(html.includes('أثر حسابي'));
 assert.equal(compactPeriod(account.rows,'','','all','FOREIGN').rows.length,0);
 assert.deepEqual(invoiceLines(account,privateRow,{[privateRow.id]:{items:privateRow.items}}),{available:false,items:[],currency:'IQD'});
});

test('restricted supplier effects retain account currency, revision and cancellations but discard raw receipt metadata',()=>{
 const account=supplierAccount({supplierId:1,currency:'USD',revision:2,rows:[
  {id:1,revision:2,created_at:'2026-11-01T00:00:00Z',delta:100,entry_type:'opening',currency:'USD'},
  {id:'restricted:charge',revision:2,created_at:'2026-11-02T00:00:00Z',delta:20.25,receiptRestricted:true,transaction:{id:99,kind:'purchase',notes:'FOREIGN-NOTE',receipt_no:991,total:90000},items:[{product_name:'FOREIGN-MATERIAL'}]},
  {id:'restricted:refund',revision:2,created_at:'2026-11-03T00:00:00Z',delta:-20.25,receiptRestricted:true,archivedPurchase:{receiptNo:991,notes:'FOREIGN-NOTE'}},
  {id:'restricted:old',revision:1,created_at:'2026-10-01T00:00:00Z',delta:500000,receiptRestricted:true}
 ]},'موردي');
 const period=compactPeriod(account.rows);
 assert.equal(account.currency,'USD');assert.equal(period.balance,100);assert.equal(period.rows.length,3);
 assert.deepEqual(period.rows.map(row=>row.balance),[100,120.25,100]);assert.equal(period.invoices,0);
 for(const row of account.rows.filter(row=>row.receiptRestricted)){assert.equal(row.original,null);assert.equal(row.receiptNo,null);assert.equal(row.notes,'');}
 const html=compactStatementBody(account,period,'','');assert.ok(!html.includes('FOREIGN'));assert.ok(!html.includes('991'));assert.ok(html.includes('USD'));
});

test('cash statement exports print only the approved effect even if a restricted row contains obsolete metadata',()=>{
 const row={id:'restricted:cash',receiptRestricted:true,created_at:'2026-11-01T00:00:00Z',currency:'IQD',delta:25,balance:125,kind:'sale',receipt_no:771199,party:'FOREIGN-PARTY',note:'FOREIGN-NOTE',actor_name:'FOREIGN-ACTOR',warehouse_name:'FOREIGN-WAREHOUSE',source_currency:'USD',source_amount:9911,rate:1511};
 assert.deepEqual(cashStatementDetails(row),[]);assert.equal(cashStatementNotes(row),'أثر حسابي');assert.equal(cashStatementKind(row),'أثر حسابي');
 const html=cashStatementTable({ownerName:'قاصتي',currency:'IQD',opening:100,incoming:25,outgoing:0,closing:125,rows:[row]});
 assert.ok(!html.includes('FOREIGN'));assert.ok(!html.includes('771199'));assert.ok(!html.includes('9,911'));assert.ok(html.includes('125'));
});

test('an opening amount entered by administration remains opening balance while its receipt stays private',()=>{
 const account=customerAccount({id:1,name:'زبوني',rows:[{id:'restricted:opening',date:'2026-10-01T00:00:00Z',receiptRestricted:true,kind:'customer_payment',mode:'opening_balance',effect:200,total:-200,receiptNo:991,notes:'FOREIGN-NOTE'}]});
 const period=compactPeriod(account.rows);
 assert.equal(period.balance,200);assert.equal(period.originalOpening,200);assert.equal(period.invoices,0);assert.equal(period.payments,0);
 assert.equal(account.rows[0].receiptNo,null);assert.equal(account.rows[0].original,null);assert.equal(account.rows[0].label,'رصيد افتتاحي');
});

test('cash list drops obsolete restricted metadata before mobile or desktop rendering while retaining amounts',()=>{
 const own={id:'tx:1',kind:'sale',delta:20,party:'زبوني'},restricted={id:'restricted:x',kind:'sale',receiptRestricted:true,currency:'IQD',delta:30,balance:50,created_at:'2026-11-01',party:'FOREIGN-PARTY',note:'FOREIGN-NOTE',ownerName:'FOREIGN-ACTOR',receipt_no:991,document:{items:['FOREIGN-MATERIAL']}};
 const data={rows:[own,restricted],count:2,summary:{periodIQDIn:50}};
 for(const type of ['all','sale']){
  const visible=cashPage(data,type);assert.equal(visible.count,2);assert.equal(visible.summary.periodIQDIn,50);assert.equal(visible.rows[1].delta,30);assert.equal(visible.rows[1].balance,50);
  assert.ok(!JSON.stringify(visible).includes('FOREIGN'));assert.equal(visible.rows[1].receipt_no,null);assert.equal(visible.rows[0],own);
 }
 assert.equal(data.rows[1].party,'FOREIGN-PARTY');
});
