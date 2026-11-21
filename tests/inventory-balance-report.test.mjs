import test from 'node:test';
import assert from 'node:assert/strict';
import {inventoryBalanceDocument,inventoryBalanceView} from '../app/inventory-balance-report.mjs';

const warehouses=[{id:3,name:'الرئيسي',active:true},{id:5,name:'مخزن فرعي',active:true}];
const products=[
 {id:8,name:'لوح 600W',code:'X',qty:0.30002,reservedQty:1,bookQty:1.30002,cost:85000,brand:'Full'},
 {id:9,name:'لوح 600W',code:'Y',qty:0,reservedQty:0.00001,bookQty:0.00001,cost:180000,brand:'Full'},
 {id:10,name:'لوح 600W',code:'Z',qty:0,reservedQty:0,bookQty:0,cost:90000}
];
const warehouseBalances=[
 {productId:8,warehouseId:3,qty:0.2,bookQty:1.2,reservedQty:1},
 {productId:8,warehouseId:5,qty:0.10002,bookQty:0.10002,reservedQty:0},
 {productId:9,warehouseId:5,qty:0,bookQty:0.00001,reservedQty:0.00001}
];
const snapshot={warehouseBalances,warehouses,products,warehouseId:'',query:'',hideZero:true};
const settings={warehouseName:'جميع المخازن المسموحة',byWarehouse:true,priced:false,hideZero:true,query:''};
test('split keeps material IDs distinct and totals reservations, tiny fractions and current valued book stock once',()=>{
 const aggregate=inventoryBalanceView({...snapshot,byWarehouse:false}),split=inventoryBalanceView({...snapshot,byWarehouse:true});
 assert.deepEqual(aggregate.totals,split.totals);
 assert.equal(split.totals.products,2);assert.equal(split.totals.available,0.30002);assert.equal(split.totals.reserved,1.00001);
 assert.equal(split.totals.value,1.30002*85000+0.00001*180000);
 assert.deepEqual(split.groups.map(w=>w.rows.map(p=>p.id)),[[8],[8,9]]);
});
test('all balances includes missing pairs at zero; selected warehouse and material search scope stay exact',()=>{
 const split=inventoryBalanceView({...snapshot,byWarehouse:true,hideZero:false});
 assert.equal(split.totals.products,3);
 assert.deepEqual(split.groups.map(w=>w.rows.length),[3,3]);
 const filtered=inventoryBalanceView({...snapshot,byWarehouse:true,products:[{...products[1],qty:0}],warehouseId:'5',query:'Y'});
 assert.deepEqual(filtered.groups.map(w=>w.id),[5]);assert.equal(filtered.groups[0].rows[0].reservedQty,0.00001);
});
test('the grouped export repeats warehouse names in table headers, retains fractional stock and omits all costs in quantity mode',()=>{
 const view=inventoryBalanceView({...snapshot,byWarehouse:true});
 const quantity=inventoryBalanceDocument(view,settings);
 assert.ok(quantity.body.includes('0.00001'));assert.ok(quantity.body.includes('0.10002'));
 assert.ok(quantity.body.includes('الرئيسي</th>'));assert.ok(quantity.body.includes('مخزن فرعي</th>'));
 assert.ok(!quantity.body.includes('85,000'));assert.ok(!quantity.body.includes('قيمة المخزون'));assert.equal(quantity.total,'');
 const priced=inventoryBalanceDocument(view,{...settings,priced:true});
 assert.ok(priced.body.includes('85,000'));assert.ok(priced.body.includes('180,000'));assert.ok(priced.total);
});

test('export escapes the warehouse label in both its HTML title and body',()=>{
 const view=inventoryBalanceView({...snapshot,byWarehouse:false});
 const doc=inventoryBalanceDocument(view,{...settings,byWarehouse:false,warehouseName:'مخزن <فرع>'});
 assert.ok(doc.title.includes('&lt;فرع&gt;'));assert.ok(!doc.body.includes('<فرع>'));
});

test('stock uses effective unit prices for every material and counts its reserved quantity once in both views',()=>{
 const list=[
  {id:1,name:'يدوية',qty:5,reservedQty:1,bookQty:6,cost:40,bookCost:999999,floorSource:'configured'},
  {id:2,name:'تلقائية',qty:2.5,reservedQty:0.5,bookQty:3,cost:100.125455,floorSource:'cost'},
  {id:3,name:'صفر',qty:1,reservedQty:0,cost:0,floorSource:'cost'}
 ];
 const balances=[
  {productId:1,warehouseId:3,qty:2,reservedQty:1,bookQty:3},
  {productId:1,warehouseId:5,qty:3,bookQty:3},
  {productId:2,warehouseId:3,qty:1.5,reservedQty:0.5},
  {productId:2,warehouseId:5,qty:1,bookQty:1},
  {productId:3,warehouseId:5,qty:1}
 ];
 const source={...snapshot,products:list,warehouseBalances:balances};
 const aggregate=inventoryBalanceView({...source,byWarehouse:false});
 const view=inventoryBalanceView({...source,byWarehouse:true});
 assert.deepEqual(view.totals,aggregate.totals);
 assert.equal(view.totals.available,8.5);assert.equal(view.totals.reserved,1.5);
 assert.equal(view.totals.value,6*40+3*100.125455);
 assert.deepEqual(view.groups.map(w=>w.value),[3*40+2*100.125455,3*40+100.125455]);
 const priced=inventoryBalanceDocument(view,{...settings,priced:true,personalPrices:true});
 assert.equal(priced.total,'540.38 د.ع');
 assert.match(priced.body,/سعر المادة د.ع/);assert.match(priced.body,/100\.125455/);
 assert.match(priced.body,/يدوي/);assert.match(priced.body,/حسب الكلفة/);
 assert.match(priced.body,/320\.25/);assert.match(priced.body,/220\.13/);
 assert.match(priced.body,/<td><bdi>0<\/bdi><br><small>حسب الكلفة/);
 assert.doesNotMatch(priced.body,/999,999|غير محدد|أسعار الجملة/);
 const quantities=inventoryBalanceDocument(view,{...settings,priced:false,personalPrices:true});
 assert.equal(quantities.total,'');
 assert.doesNotMatch(quantities.body,/قيمة المخزون|سعر المادة|حسب الكلفة|100\.125455|999,999|320\.25|220\.13/);
});
