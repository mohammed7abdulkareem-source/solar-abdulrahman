import test from'node:test';
import assert from'node:assert/strict';
import{cashTotals,cashPage,statementByType}from'../app/cash-finance-utils.mjs';
import{cashStatementDocument}from'../app/cash-statement-report.mjs';
test('cashbox summary preserves negative amounts and keeps currencies independent to the cent',()=>{
 assert.deepEqual(cashTotals([{IQD:'1000000.10',USD:'0.10'},{IQD:'-1500000.20',USD:'0.20'}]),{IQD:-500000.1,USD:0.3});
});
test('type filtering paginates a complete result and keeps saved cumulative balances unchanged',()=>{
 const rows=Array.from({length:125},(_,i)=>({id:'tx:'+i,kind:i%2?'expense':'cash_income',delta:i%2?-10:20,balance:200-i})),data={count:rows.length,rows,summary:{IQD:500}};
 const page=cashPage(data,'expense',50);assert.equal(page.count,62);assert.equal(page.rows.length,12);assert.equal(page.rows[0].id,'tx:101');assert.equal(page.rows[0].balance,99);assert.equal(data.rows.length,125);
 assert.throws(()=>cashPage({...data,count:5001},'expense'),/فترة أقصر/);
});
test('filtered statements retain the true opening/closing and full-period totals for every currency',()=>{
 const data={ownerName:'قاصة',from:'2026-10-01',to:'2026-10-29',asOf:'2026-10-29T12:00Z',count:3,ledgers:[{ownerId:'a',ownerName:'أحمد',currency:'IQD',opening:100,incoming:70,outgoing:40,closing:130,rows:[{kind:'expense',delta:-40,balance:60},{kind:'cash_income',delta:70,balance:130}]},{ownerId:'a',ownerName:'أحمد',currency:'USD',opening:20,incoming:0,outgoing:5,closing:15,rows:[{kind:'expense',delta:-5,balance:15}]}]};
 const filtered=statementByType(data,'expense');assert.equal(filtered.count,2);assert.equal(filtered.unfilteredCount,3);assert.equal(filtered.ledgers[0].closing,130);assert.equal(filtered.ledgers[0].rows[0].balance,60);assert.equal(filtered.ledgers[1].closing,15);assert.equal(data.ledgers[0].rows.length,2);
 const html=cashStatementDocument(filtered,(_title,body)=>body);assert.ok(html.includes('الأرصدة والمجاميع تشمل كل حركات الفترة'));assert.ok(html.includes('دينار')||html.includes('د.ع'));assert.ok(html.includes('$'));
});
