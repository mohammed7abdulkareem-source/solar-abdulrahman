import test from 'node:test';
import assert from 'node:assert/strict';
import {statementPeriod,accountLabel,customerStatementBody} from '../app/reconciliation-utils.mjs';
import {movementDocument} from '../app/warehouse-utils.mjs';
const rows=[
 {id:1,date:'2026-10-01T10:00Z',kind:'customer_payment',mode:'opening_balance',total:-1000},
 {id:2,date:'2026-10-02T10:00Z',kind:'sale',cash:true,total:500},
 {id:3,date:'2026-10-03T10:00Z',kind:'customer_payment',total:200},
 {id:4,date:'2026-10-04T10:00Z',kind:'customer_payment',mode:'account_reconciliation',total:100},
];
test('opening and reconciliation affect debt but settled cash sales do not',()=>{const r=statementPeriod(rows);assert.equal(r.balance,700);assert.equal(r.rows[1].balance,1000);assert.equal(accountLabel(rows[0]),'رصيد افتتاحي');assert.equal(accountLabel(rows[3]),'مطابقة حساب')});
test('period carries earlier balance and view filter preserves full balance',()=>{const r=statementPeriod(rows,'2026-10-03','2026-10-04','invoices');assert.equal(r.opening,1000);assert.equal(r.balance,700);assert.equal(r.rows.length,0)});
test('Baghdad date boundary and credit opening',()=>{const r=statementPeriod([{id:1,date:'2026-10-02T21:30Z',kind:'system_payment',mode:'opening_balance',total:75}],'2026-10-03','2026-10-03');assert.equal(r.rows.length,1);assert.equal(r.balance,-75)});
test('statement safely prints opening/matching/notes and grid',()=>{const r=statementPeriod(rows);const html=customerStatementBody('<client>',r,'','');assert.match(html,/رصيد افتتاحي/);assert.match(html,/مطابقة حساب/);assert.match(html,/&lt;client&gt;/);assert.match(html,/<thead>/)});
test('stock adjustment report states reason and no fictitious cash customer',()=>{const html=movementDocument([{kind:'stock_adjustment',receiptNo:1,date:'2026-10-06',name:'بطارية',inQty:0,outQty:3,balance:7,note:'جرد <test>'}]);assert.match(html,/تسوية رصيد/);assert.match(html,/جرد &lt;test&gt;/);assert.doesNotMatch(html,/زبون نقدي/)});
