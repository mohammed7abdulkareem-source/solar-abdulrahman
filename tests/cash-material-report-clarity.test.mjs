import test from 'node:test';
import assert from 'node:assert/strict';
import {cashStatementCurrencyTotals,cashStatementDocument} from '../app/cash-statement-report.mjs';
import {materialMovementDocument,materialReportPeriod,filterMaterialRows} from '../app/material-movement-utils.mjs';
import {movementDocument} from '../app/warehouse-utils.mjs';

const cash={from:'2026-11-01',to:'2026-11-07',asOf:'2026-11-08T09:00:00Z',ownerName:'القاصات المسموحة',count:1,filterLabel:'مصروف تشغيلي',unfilteredCount:9,ledgers:[
 {ownerId:'a',ownerName:'أحمد',currency:'IQD',opening:1000000,incoming:200000,outgoing:300000,closing:900000,rows:[]},
 {ownerId:'b',ownerName:'سفيان',currency:'IQD',opening:-100000,incoming:0,outgoing:50000,closing:-150000,rows:[]},
 {ownerId:'a',ownerName:'أحمد',currency:'USD',opening:125.25,incoming:10,outgoing:0,closing:135.25,rows:[]}
]};
test('report summary keeps currency totals and saved balances independent of filtered rows',()=>{
 const before=structuredClone(cash);
 assert.deepEqual(cashStatementCurrencyTotals(cash),[
  {currency:'IQD',opening:900000,incoming:200000,outgoing:350000,closing:750000},
  {currency:'USD',opening:125.25,incoming:10,outgoing:0,closing:135.25}
 ]);
 assert.deepEqual(cashStatementCurrencyTotals(cash,'USD'),[{currency:'USD',opening:125.25,incoming:10,outgoing:0,closing:135.25}]);
 const html=cashStatementDocument(cash,(_title,body)=>body);
 for(const label of ['الرصيد الافتتاحي','إجمالي الداخل','إجمالي الخارج','الرصيد الختامي','الدينار العراقي · IQD','الدولار الأمريكي · USD','01/11/2026','07/11/2026','الأرصدة والمجاميع تشمل كل حركات الفترة'])assert.ok(html.includes(label),label);
 assert.equal((html.match(/class="cashStatementSummary" data-currency=/g)||[]).length,2);
 assert.ok(html.includes('750,000')&&html.includes('135.25'));
 assert.deepEqual(cash,before);
});
const movements=[{id:'purchase:1',name:'لوح <أ>',date:'2026-11-02T09:00:00Z',receiptNo:1,kind:'purchase',warehouseName:'الرئيسي',party:'المجهز',inQty:5,outQty:0,balance:15,pricing:{kind:'purchase',unitPrice:1234567.89,lineTotal:6172839.45}},
 {id:'sale:2',name:'لوح <أ>',date:'2026-11-03T09:00:00Z',receiptNo:2,kind:'sale',warehouseName:'الرئيسي',party:'الزبون',inQty:0,outQty:3,balance:12,note:'تفاصيل عربية محفوظة <script>bad</script> '.repeat(25)+'نهاية الملاحظة',pricing:{kind:'sale',unitPrice:200000,lineTotal:600000}}];
const material={product:{code:'001',name:'لوح <أ>',brand:'FULLMAX'},withPrices:false,from:'2026-11-01',to:'2026-11-07',scope:'own',warehouses:[{name:'الرئيسي',beforeFirst:10,inQty:5,outQty:3,afterLast:12,currentQty:20},{name:'الثاني',beforeFirst:null,inQty:0,outQty:0,afterLast:null,currentQty:2}]};
test('material report separates current stock from period balances and retains long notes with masked prices',()=>{
 const shown=filterMaterialRows(movements,'out','الزبون'),before=structuredClone(material);
 const html=materialMovementDocument(material,shown,{direction:'out',query:'الزبون'});
 for(const text of ['دخول الفترة','خروج الفترة','قبل أول حركة بالفترة','بعد آخر حركة بالفترة','المتاح حاليًا','خروج فقط'])assert.ok(html.includes(text),text);
 assert.ok(html.includes('وصولاتك المسموحة فقط')&&html.includes('المتاح حاليًا رصيد مستقل'));
 assert.ok(html.includes('data-note-for="sale:2"')&&html.includes('نهاية الملاحظة'));
 assert.ok(!html.includes('<script>')&&html.includes('&lt;script&gt;'));
 assert.ok(!html.includes('1,234,567.89')&&!html.includes('600,000'));
 assert.match(html,/<tfoot>[\s\S]*<bdi>0<\/bdi>[\s\S]*<bdi>3<\/bdi>/);
 assert.deepEqual(material,before);assert.equal(shown[0].balance,12);
 assert.equal(materialReportPeriod('2026-11-01','2026-11-07'),'01/11/2026 — 07/11/2026');
 assert.equal(materialReportPeriod('',''),'جميع الفترات');
});
test('general movement export carries the full result and visible quantities without combining stock balances',()=>{
 const html=movementDocument(movements);
 assert.ok(html.includes('data-pdf-paginate')&&html.includes('data-pdf-keep-footer-with-row'));
 assert.ok(html.includes('مجموع كميات الحركات الظاهرة')&&html.includes('لكل مادة ومخزن رصيد مستقل'));
 assert.ok(html.includes('الرصيد بعد الحركة')&&html.includes('&lt;أ&gt;'));
 assert.ok(!html.includes('1,234,567.89')&&!html.includes('<script>'));
 assert.match(html,/<tfoot>[\s\S]*<bdi>5<\/bdi>[\s\S]*<bdi>3<\/bdi>/);
});
