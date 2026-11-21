import test from 'node:test';
import assert from 'node:assert/strict';
import {companyInvoiceCost,companyMovementTotals} from '../app/company-profit-figures.mjs';

test('wholesale costs follow the saved IQD invoice cost for FX-priced receipts and stored line costs for legacy receipts',()=>{
 const items=[{qty:3,cost:12.5},{qty:2,cost:0.75}];
 assert.equal(companyInvoiceCost({kind:'sale',fxPricing:true,cost:40,exchangeRate:1500,items}),40);
 assert.equal(companyInvoiceCost({kind:'sale',fxPricing:true,cost:0,items}),0);
 assert.equal(companyInvoiceCost({kind:'sale',fxPricing:false,cost:440,items}),39);
});

test('closed systems include posted material cost plus the receipt and approved installation expenses',()=>{
 assert.equal(companyInvoiceCost({kind:'system',cost:1200,expenses:25,installationExpenses:37,installationPaidExpenses:1000}),1262);
});

test('posted period movements retain signed corrections and exclude payouts and personal balance adjustments',()=>{
 const values=[['cash_expense',-15],['profit_expense',-8],['handover_expense',4],['fx_gain',-7],['fx_gain',1],['external_profit',30],
  ['sale',75],['system',-25],['external_adjustment',50],['personal_distribution',0]];
 assert.deepEqual(companyMovementTotals(values.map(([kind,value])=>({kind,value}))),{expenses:19,fx:-6,externalProfit:30});
});

test('admin-filtered sales use the personal material basis for wholesale and add posted system expenses exactly once',()=>{
 const sale={kind:'sale',fxPricing:false,cost:30,items:[{qty:1,cost:30}]};
 assert.equal(companyInvoiceCost(sale,36),36);
 assert.equal(companyInvoiceCost({...sale,kind:'system',expenses:2,installationExpenses:4},36),42);
 assert.equal(companyInvoiceCost(sale),30);
});
