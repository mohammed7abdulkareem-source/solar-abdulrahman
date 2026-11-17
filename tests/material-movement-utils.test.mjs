import test from 'node:test';
import assert from 'node:assert/strict';
import {filterMovementProducts,materialSelectionLabel,materialReportMatchesSelection,materialMovementPresentation,materialVisibleTotals,materialQuantity,materialSignedQuantity,materialLastVisibleBalances,filterMaterialRows,materialMovementDocument,materialPrice} from '../app/material-movement-utils.mjs';
const rows=[{id:'a',date:'2026-10-01T09:00:00Z',kind:'purchase',party:'المورد',receiptNo:1,warehouseName:'الرئيسي',inQty:5,outQty:0,balance:15,createdByName:'المشتري',preparedByName:null,pricing:{kind:'purchase',unitPrice:1234567.89,lineTotal:6172839.45}},{id:'b',date:'2026-10-02T10:00:00Z',kind:'sale',party:'الزبون',receiptNo:2,warehouseName:'الرئيسي',inQty:0,outQty:3,balance:12,createdByName:'البائع',preparedByName:'المجهز',pricing:{kind:'sale',unitPrice:3000,lineTotal:9000}}];
test('filtering direction/party preserves the saved running stock balance and matches preparer',()=>{
 assert.deepEqual(filterMaterialRows(rows,'out','المجهز').map(r=>[r.id,r.balance]),[['b',12]]);
 assert.deepEqual(filterMaterialRows(rows,'all','المورد').map(r=>r.balance),[15]);
 assert.equal(materialPrice({pricing:{kind:'system_total'}}).unit,'—');
 assert.match(materialPrice({pricing:{kind:'system_total'}}).label,/غير موزّع/);
});
test('priced and unpriced PDFs retain exact parties/warehouse/preparer and mask every financial price',()=>{
 const data={product:{code:'001',name:'لوح <أ>',brand:'البراند',category:'ألواح'},withPrices:false,warehouses:[{name:'الرئيسي',beforeFirst:10,inQty:5,outQty:3,afterLast:12,currentQty:12}],scope:'all'};
 const plain=materialMovementDocument(data,rows),priced=materialMovementDocument({...data,withPrices:true},rows);
 assert.ok(!plain.includes('1,234,567.89')&&!plain.includes('6,172,839.45')&&!plain.includes('سعر الوحدة د.ع'));
 assert.ok(priced.includes('1,234,567.89')&&priced.includes('9,000')&&priced.includes('سعر الوحدة د.ع'));
 for(const text of ['المورد','الزبون','الرئيسي','المجهز','الرصيد بعد الحركة'])assert.ok(plain.includes(text));
 assert.ok(plain.includes('&lt;أ&gt;')&&!plain.includes('<أ>'));
});
test('material search matches sale search fields without combining duplicate names or excluding zero stock',()=>{
 const products=[{id:1,name:'ألواح 600W',code:'001',brand:'FULLMAX',category:'لوح',qty:0},{id:2,name:'ألواح 600W',code:'002',brand:'OTHER',category:'لوح',qty:5},{id:3,name:'بطارية',code:'003',brand:'FULLMAX',category:'25KW',qty:1}];
 const before=structuredClone(products);
 assert.deepEqual(filterMovementProducts(products,'الواح ٦٠٠W fullmax').map(p=>p.id),[1]);
 assert.deepEqual(filterMovementProducts(products,'ألواح').map(p=>p.id),[1,2]);
 assert.deepEqual(filterMovementProducts(products,'۰۰۲').map(p=>p.id),[2]);
 assert.deepEqual(filterMovementProducts(products,'25kw').map(p=>p.id),[3]);
 assert.equal(materialSelectionLabel(products[0]),'ألواح 600W · FULLMAX · لوح · 001');
 assert.deepEqual(products,before);
});
test('a material response is usable only for the chosen identity, date, warehouse and price mode',()=>{
 const selected={productId:'8',warehouseId:'2',from:'2026-11-01',to:'2026-11-15',withPrices:false};
 const response={product:{id:8},from:selected.from,to:selected.to,withPrices:false,warehouses:[{id:2}],rows:[{productId:8,warehouseId:2,balance:7}]};
 assert.equal(materialReportMatchesSelection(response,selected),true);
 for(const invalid of [null,{...response,product:{id:9}},{...response,rows:[{productId:9,warehouseId:2}]},{...response,rows:[{warehouseId:2}]},{...response,rows:[{productId:8,warehouseId:3}]},{...response,warehouses:[{id:3}]},{...response,from:'2026-10-01'},{...response,to:null},{...response,withPrices:true},{...response,withPrices:'false'}])assert.equal(materialReportMatchesSelection(invalid,selected),false);
 assert.equal(materialReportMatchesSelection({...response,withPrices:true,canShowPrices:false},{...selected,withPrices:true}),false);
 assert.equal(materialReportMatchesSelection(response,{...selected,productId:''}),false);
 assert.equal(materialReportMatchesSelection({...response,rows:[]},selected),true);
 assert.equal(materialReportMatchesSelection({...response,warehouses:[{id:2},{id:3}],rows:[{productId:8,warehouseId:3}]},{...selected,warehouseId:''}),true);
});
test('movement search is separate from material selection and keeps original row objects and balances',()=>{
 const materialRows=rows.map(row=>({...row,name:'لوح شمس',code:'XYZ123',brand:'SECRETBRAND',category:'ألواح'}));
 assert.equal(filterMaterialRows(materialRows,'all','شمس').length,0);
 assert.equal(filterMaterialRows(materialRows,'all','XYZ123').length,0);
 assert.equal(filterMaterialRows(materialRows,'all','SECRETBRAND').length,0);
 assert.strictEqual(filterMaterialRows(materialRows,'out','#٢ المجهز')[0],materialRows[1]);
 assert.equal(materialRows[1].balance,12);
});
test('reservation and cancellation describe available-stock effects without inventing physical delivery',()=>{
 const events=[{kind:'transfer_reserved',outQty:4,inQty:0,balance:6,preparationStatus:'pending'},
  {kind:'transfer_out',outQty:3,inQty:0,balance:3,preparationStatus:'cancelled',preparedAt:null},
  {kind:'transfer_cancelled',outQty:0,inQty:3,balance:6,preparationStatus:'cancelled'},
  {kind:'transfer_out',outQty:2,inQty:0,balance:4,preparationStatus:'prepared',preparedAt:'2026-11-10T09:00Z'}];
 const before=structuredClone(events);
 assert.equal(materialMovementPresentation(events[0]).isReservation,true);
 assert.equal(materialMovementPresentation(events[1]).label,'حجز نقل ملغى');
 assert.equal(materialMovementPresentation(events[1]).isReservation,true);
 assert.match(materialMovementPresentation(events[1]).stockNote,/دون تجهيز/);
 assert.equal(materialMovementPresentation(events[3]).isReservation,false);
 assert.equal(materialMovementPresentation(events[3]).label,'نقل صادر');
 assert.equal(materialMovementPresentation({kind:'purchase'}).partyLabel,'المورّد');
 assert.equal(materialMovementPresentation({kind:'sale',preparationStatus:'pending'}).preparationLabel,'بانتظار التجهيز');
 assert.match(materialMovementPresentation({kind:'sale'}).stockNote,/عند تسجيل الفاتورة/);
 assert.deepEqual(materialVisibleTotals(events),{in:3,out:9,count:4,reservedOut:7,reservationReleased:3});
 assert.deepEqual(events,before);
});
test('purchase and stock adjustment never inherit an outgoing preparation workflow',()=>{
 const data={product:{name:'لوح',code:'1'},withPrices:false,warehouses:[]};
 for(const kind of ['purchase','stock_adjustment']){
  const row={...rows[0],kind,preparationStatus:'pending',createdByName:'مسجل الحركة',executedByName:'منفذ الحركة',preparedByName:'اسم موروث',preparedAt:'2026-11-10T08:00Z'};
  const view=materialMovementPresentation(row);
  assert.equal(view.preparationApplicable,false);assert.equal(view.preparationLabel,null);assert.equal(view.preparerLabel,null);
  const html=materialMovementDocument(data,[row]);
  assert.doesNotMatch(html,/بانتظار التجهيز|لم يُسجّل تجهيز|وقت التجهيز:|اسم موروث/);
  assert.match(html,/مسجل الحركة/);assert.match(html,/منفذ الحركة/);
  if(kind==='purchase')assert.match(html,/المورّد: المورد/);
 }
 for(const kind of ['sale','system','transfer_reserved','transfer_in','transfer_out']){
  const view=materialMovementPresentation({kind,preparationStatus:'pending'});
  assert.equal(view.preparationApplicable,true);assert.equal(view.preparationLabel,'بانتظار التجهيز');
 }
});
test('PDF keeps server warehouse anchors and every movement balance after filtering, with honest reservation labels',()=>{
 const events=[{...rows[1],id:'reserve',kind:'transfer_out',preparationStatus:'cancelled',preparedAt:null,balance:12,outQty:3},
  {...rows[0],id:'cancel',kind:'transfer_cancelled',balance:15,inQty:3}];
 const data={product:{name:'بطارية',brand:'FULLMAX',category:'25KW',code:'0003'},withPrices:false,warehouses:[{name:'الرئيسي',beforeFirst:18,inQty:3,outQty:6,afterLast:15,currentQty:27},{name:'بلا حركة',beforeFirst:null,afterLast:null,inQty:0,outQty:0,currentQty:8}],scope:'own'};
 const before=structuredClone(data),out=filterMaterialRows(events,'out');
 const html=materialMovementDocument(data,out,{direction:'out'});
 assert.match(html,/حجز نقل ملغى/);assert.match(html,/قبل أول حركة بالفترة/);assert.match(html,/بعد آخر حركة بالفترة/);
 assert.match(html,/وليست رصيد بداية ونهاية التاريخ/);assert.match(html,/ليست رصيد الحجوزات الحالي/);
 assert.match(html,/<td class="mlReportBalance"><bdi>12<\/bdi><\/td>/);
 assert.match(html,/<td class="mlReportBalance"><bdi>15<\/bdi><\/td>/);
 assert.match(html,/<td>بلا حركة<\/td><td><bdi>—<\/bdi><\/td>/);
 assert.doesNotMatch(html,/data-movement-id="cancel"/);
 assert.deepEqual(data,before);
 const malformedPriceFlag=materialMovementDocument({...data,withPrices:'false'},rows);
 assert.doesNotMatch(malformedPriceFlag,/1,234,567.89|6,172,839.45|سعر الوحدة د\.ع/);
 assert.equal(materialPrice({pricing:{kind:'unknown',unitPrice:1234567}}).unit,'—');
});
test('signed quantities retain tiny fractions and both sides while decimal display totals avoid rounding artifacts',()=>{
 for(const [value,text] of [[0,'0'],[-0,'0'],[0.0004,'0.0004'],[-0.125,'−0.125'],[1.25e-7,'0.000000125'],['1.23004000','1.23004'],['1234.1234567890123456789','1,234.1234567890123456789'],[null,'—'],[undefined,'—']])assert.equal(materialQuantity(value),text);
 assert.equal(materialSignedQuantity({inQty:.0004,outQty:0}).text,'+0.0004');
 assert.equal(materialSignedQuantity({inQty:0,outQty:.125}).text,'−0.125');
 assert.equal(materialSignedQuantity({inQty:5,outQty:3}).text,'+5 / −3');
 assert.equal(materialSignedQuantity({inQty:-0,outQty:0}).text,'0');
 assert.equal(materialSignedQuantity({}).text,'0');
 assert.equal(materialSignedQuantity({inQty:'invalid'}).text,'—');
 assert.equal(materialVisibleTotals([{inQty:.1},{inQty:.2}]).in,.3);
 assert.deepEqual(materialVisibleTotals([{kind:'transfer_reserved',inQty:0,outQty:1e-4},{kind:'transfer_reserved',outQty:.0003},{kind:'transfer_cancelled',inQty:.0004}]),{in:.0004,out:.0004,count:3,reservedOut:.0004,reservationReleased:.0004});
});
test('dense ledger preserves every event in server order with its own signed quantity and authoritative balance',()=>{
 const kinds=['purchase','transfer_reserved','transfer_cancelled','transfer_out','transfer_in','transfer_return_in','transfer_return_out','sale','stock_adjustment'];
 const events=kinds.map((kind,index)=>({id:'event:'+index,date:'2026-11-10T08:00:00Z',kind,warehouseId:index%2?2:1,warehouseName:index%2?'الفرعي':'الرئيسي',party:'طرف '+index,receiptNo:100+index,inQty:index%2?0:index===0?.0004:.125,outQty:index%2?.125:0,balance:index===4?-.0004:100-index,createdByName:'المستخدم الكامل',preparedByName:'مسؤول مثبت',preparationStatus:'prepared',preparedAt:'2026-11-10T09:00:00Z',note:index===0?'بيان <كامل> '.repeat(60)+'نهاية البيان':'',pricing:{kind:kind==='purchase'?'purchase':'sale',unitPrice:9876543.21,lineTotal:7654321.23}}));
 const data={product:{id:1,name:'مادة دقيقة',code:'01',brand:'FULLMAX'},withPrices:false,warehouses:[{id:1,name:'الرئيسي',beforeFirst:110,inQty:5,outQty:2,afterLast:108,currentQty:130},{id:2,name:'الفرعي',beforeFirst:20,inQty:5,outQty:0,afterLast:25,currentQty:25}]};
 const before=structuredClone(events),html=materialMovementDocument(data,events),main=html.match(/<table class="mlReportMain"[\s\S]*?<\/table>/)[0],matches=[...main.matchAll(/<tr data-movement-id="([^"]+)">([\s\S]*?)<\/tr>/g)];
 assert.deepEqual(matches.map(match=>match[1]),events.map(row=>row.id));
 for(let index=0;index<events.length;index++){
  assert.ok(matches[index][2].includes('<bdi>'+materialSignedQuantity(events[index]).text+'</bdi>'));
  assert.ok(matches[index][2].includes('<td class="mlReportBalance"><bdi>'+materialQuantity(events[index].balance)+'</bdi></td>'));
 }
 assert.doesNotMatch(main,/المستخدم الكامل|مسؤول مثبت|بيان|ملحق/);
 assert.match(html,/data-detail-for="event:0"/);assert.match(html,/data-note-for="event:0"/);assert.match(html,/نهاية البيان/);
 assert.doesNotMatch(html,/9876543|9,876,543|7654321|7,654,321|<كامل>/);assert.match(html,/&lt;كامل&gt;/);
 assert.ok(html.indexOf('class="mlReportMain"')<html.indexOf('class="mlReportWarehouseSummary"'));
 assert.ok(html.indexOf('class="mlReportMain"')<html.indexOf('class="mlReportDetails"'));
 const priced=materialMovementDocument({...data,withPrices:true},events);
 assert.match(priced,/<th>سعر الوحدة د\.ع<\/th>/);assert.match(priced,/9,876,543.21/);assert.match(priced,/7,654,321.23/);
 assert.deepEqual(events,before);
});
test('last visible balances remain per warehouse and never become net movement, full-period or current quantities',()=>{
 const events=[{id:'a',warehouseId:1,warehouseName:'الأول',inQty:10,outQty:0,balance:110},{id:'b',warehouseId:2,warehouseName:'الثاني',inQty:5,outQty:0,balance:25},{id:'c',warehouseId:1,warehouseName:'الأول',inQty:0,outQty:2,balance:108}];
 assert.deepEqual(materialLastVisibleBalances(events),[{warehouseId:1,warehouseName:'الأول',balance:108},{warehouseId:2,warehouseName:'الثاني',balance:25}]);
 const filtered=filterMaterialRows(events,'out');
 assert.deepEqual(materialLastVisibleBalances(filtered),[{warehouseId:1,warehouseName:'الأول',balance:108}]);
 assert.deepEqual(materialLastVisibleBalances([]),[]);
 const data={product:{name:'لوح'},withPrices:false,warehouses:[{id:1,name:'الأول',beforeFirst:100,inQty:10,outQty:7,afterLast:103,currentQty:200}]};
 const html=materialMovementDocument(data,filtered,{direction:'out'}),last=html.match(/<div class="mlLastBalances">[\s\S]*?<\/div>/)[0];
 assert.match(last,/الرصيد بعد آخر حركة ظاهرة/);assert.match(last,/<bdi>108<\/bdi>/);assert.doesNotMatch(last,/>2<|103|200|الثاني/);
 assert.match(html,/<td class="mlReportBalance"><bdi>103<\/bdi>/);
 assert.match(materialMovementDocument(data,[]),/لا توجد حركة ظاهرة؛ لا يُستنتج رصيد/);
});
