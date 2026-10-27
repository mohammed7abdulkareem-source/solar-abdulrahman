import test from 'node:test';
import assert from 'node:assert/strict';
import {invoicePayload} from '../app/currency-utils.mjs';
import {canEditInstallationExpenses} from '../app/invoice-edit-utils.mjs';
import {cashStatementKind} from '../app/cash-statement-report.mjs';
test('system edits send an explicit zero with both revisions; legacy/new invoices do not implicitly clear costs',()=>{
 const original={id:1,pricingRevision:7,installationRevision:4};
 const p=invoicePayload('system',{requestedInstallationExpenses:0,total:5000000},[{id:2,qty:3}],original);assert.equal(p.approvedInstallationExpenses,0);assert.equal(p.expectedRevision,7);assert.equal(p.expectedInstallationRevision,4);
 assert.equal(Object.hasOwn(invoicePayload('system',{total:5000000},[],original),'approvedInstallationExpenses'),false);assert.equal(Object.hasOwn(invoicePayload('system',{requestedInstallationExpenses:0},[]),'approvedInstallationExpenses'),false);
 const profile={id:'owner',active:true,user_type:'admin_staff',permissions:{installations:true}},row={createdBy:'owner'};assert.ok(canEditInstallationExpenses(profile,row));assert.ok(!canEditInstallationExpenses(profile,{createdBy:'other'}));assert.ok(!canEditInstallationExpenses({...profile,user_type:'installer',is_admin:true},row));
});
test('statement distinguishes fully refunded installation costs without hiding original cash flow',()=>{
 assert.equal(cashStatementKind({kind:'installation_payout',current_expenses:0,current_paid:0}),'صرف تنصيب مُلغى — أُعيد للقاصة');assert.equal(cashStatementKind({kind:'installation_payout',current_expenses:0,current_paid:479000}),'صرف تنصيب');assert.equal(cashStatementKind({kind:'installation_payout',current_expenses:100000,current_paid:100000}),'صرف تنصيب');
});
