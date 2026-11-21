import assert from 'node:assert/strict';
import test from 'node:test';
import {pendingProfitFigures,profitInvoiceExpense,profitMaterialDocument,receiptProfitFigures} from '../app/profit-material-document.mjs';
const b={receiptNo:4,kind:'sale',party:'<img>',creatorName:'A & B',warehouseName:'صيادة',date:'2026-10-28',sales:1000,total:1000,materialsCost:400,grossProfit:600,netProfit:550,profitAdjustment:-50,invoiceExpenses:50,installationExpenses:0,items:[{name:'بطارية',brand:'M',category:'بطاريات',code:'0001',qty:2,unitPrice:500,unitCost:200,lineSales:1000,lineCost:400,lineProfit:600}]};
test('profit export includes materials, saved costs and line profits and reconciles the approved movement',()=>{const d=profitMaterialDocument(b,{settled:0,available:550});for(const s of ['بطارية','كود 0001','ربح الفقرة','كلفة الفقرة','600','550','مصاريف الفاتورة: 50','&lt;img&gt;','A &amp; B'])assert.ok(d.body.includes(s),s);assert.equal(d.total,'550 د.ع');});
test('system profit export uses the agreed system price and material costs without inventing item prices',()=>{const d=profitMaterialDocument({...b,kind:'system',items:b.items.map(i=>({...i,unitPrice:null,lineSales:null,lineProfit:null}))},{settled:0,available:550});assert.ok(d.body.includes('سعر المنظومة إجمالي'));assert.ok(d.body.includes('بطارية'));assert.ok(!d.body.includes('<th>ربح الفقرة'));assert.ok(!d.body.includes('<th>سعر البيع'));assert.equal(d.total,'550 د.ع');});
test('profit document distinguishes company expenses without deducting them a second time',()=>{
 const company={...b,invoiceExpensesOnCustomer:false,customerInvoiceExpenses:0,companyInvoiceExpenses:50};
 const before=JSON.stringify(company),document=profitMaterialDocument(company,{settled:100,available:450});
 assert.deepEqual(profitInvoiceExpense(company),{label:'مصاريف الفاتورة على الشركة',amount:50});
 assert.match(document.body,/مصاريف الفاتورة على الشركة: 50 د\.ع/);
 assert.doesNotMatch(document.body,/تعديلات ربح أخرى/);
 assert.match(document.body,/صافي الربح: 550 د\.ع/);
 assert.match(document.body,/غير المسوّى: 450 د\.ع/);assert.equal(document.total,'550 د.ع');
 assert.equal(JSON.stringify(company),before);
 const customer={...b,invoiceExpensesOnCustomer:true,customerInvoiceExpenses:50,companyInvoiceExpenses:0,profitAdjustment:0,netProfit:600};
 const charged=profitMaterialDocument(customer,{settled:0,available:600});
 assert.match(charged.body,/مصاريف الفاتورة على الزبون: 50 د\.ع/);assert.equal(charged.total,'600 د.ع');
 assert.equal(profitInvoiceExpense(b).label,'مصاريف الفاتورة');
 assert.equal(profitInvoiceExpense({...company,kind:'system'}).label,'مصاريف الفاتورة');
});

test('a system with matching sale and historical cost charges installation once, and preserves independent adjustments',()=>{
 const system={...b,kind:'system',sales:5138000,total:5138000,materialsCost:5138000,grossProfit:0,
  invoiceExpenses:0,installationExpenses:1200000,netProfit:-1200000};
 const figures=receiptProfitFigures(system);
 assert.deepEqual(figures.map(([key,,amount])=>[key,amount]),[['sale',5138000],['materials',5138000],['gross',0],['installation',1200000],['net',-1200000]]);
 assert.deepEqual(receiptProfitFigures({...system,netProfit:-1200020}).find(([key])=>key==='adjustment'),['adjustment','تعديلات ربح أخرى',-20]);
 const report=profitMaterialDocument({...system,netProfit:-1200020},{settled:0,available:-1200020});
 assert.match(report.body,/تعديلات ربح أخرى: -20 د\.ع/);assert.match(report.body,/صافي الربح: -1,200,020 د\.ع/);
});
test('individual open receipt keeps document profit distinct from its zero contribution after a dual transfer',()=>{
 const figures=pendingProfitFigures({total:700,materialCost:400,invoiceExpenses:50,approvedExpenses:20,receiptProvisionalProfit:230,provisionalProfit:0,profitAttributedElsewhere:true});
 assert.equal(figures.find(([key])=>key==='net')[2],230);
 assert.equal(figures.find(([key])=>key==='contribution')[2],0);
 assert.equal(figures.find(([key])=>key==='beforeInstallation')[2],250);
});
