import test from 'node:test';
import assert from 'node:assert/strict';
import {buildSalesSeries} from '../app/sales-trend-utils.mjs';
test('sales chart groups in Baghdad days and excludes payments',()=>{
 const result=buildSalesSeries([{kind:'sale',date:'2026-10-17T22:00:00Z',subtotal:200000,cost:150000},{kind:'system_payment',date:'2026-10-18',total:300000}], '2026-10-17','2026-10-18');
 assert.equal(result.length,2);assert.equal(result[0].sales,0);assert.equal(result[1].sales,200000);assert.equal(result[1].cost,150000);
});
test('sales chart keeps frozen invoice costs and the profit report calculated cost',()=>{
 const result=buildSalesSeries([{kind:'sale',date:'2026-10-18',total:200,cost:100,items:[{qty:1,cost:999}]},{kind:'system',date:'2026-10-18',sales:500,cost:350,installationExpenses:999}], '2026-10-18','2026-10-18');
 assert.equal(result[0].sales,700);assert.equal(result[0].cost,450);
});
test('empty chart has zero series, with no invented activity',()=>{
 const result=buildSalesSeries([],'2026-10-01','2026-10-18');assert.equal(result.length,18);assert.equal(result.reduce((sum,row)=>sum+row.sales+row.cost,0),0);
});
