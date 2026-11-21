import test from 'node:test';
import assert from 'node:assert/strict';
import {canOpenPage,isAdministrator,canSeeCash} from '../app/access-utils.mjs';
import {quantityDocument,warehouseDocument,movementDocument,filteredStock} from '../app/warehouse-utils.mjs';
test('warehouse cannot access financial pages even with stale admin and permission flags',()=>{const p={active:true,user_type:'warehouse',is_admin:true,permissions:{all:true,profit:true,cash:true,sale:true,installationsAll:true}};for(const page of ['warehouse','stock','stockMovement'])assert.equal(canOpenPage(p,page),true);for(const page of ['cash','sale','profit','users','supplierStatement','installations','salesHistory','capital','updates'])assert.equal(canOpenPage(p,page),false);assert.equal(isAdministrator(p),false);assert.equal(canSeeCash(p),false)});
test('warehouse documents whitelist quantities and escape labels',()=>{const p={id:1,code:'X',name:'<img onerror=x>',brand:'A',category:'لوح',qty:1200,price:777777,cost:888888,total:999999,profit:666666};const outputs=[quantityDocument([p]),warehouseDocument({receiptNo:1,party:'زبون',items:[p],status:'pending',total:999999}),movementDocument([{...p,date:'2026-10-04',receiptNo:1,party:'عميل',kind:'sale',inQty:0,outQty:3,balance:1200}])];for(const text of outputs){assert.ok(!/777777|888888|999999|666666|<img/.test(text));assert.ok(text.includes('&lt;img'));assert.ok(!/د\.ع|السعر|الكلفة/.test(text))}assert.ok(outputs[0].includes('1,200'));assert.equal(filteredStock([p],'لوح').length,1)});

test('picking slips keep exact quantities and identify the recorded preparer only after preparation',()=>{
 const row={
  receiptNo:90,kind:'system',date:'2026-11-16T08:00:00Z',party:'اسم الزبون',warehouseName:'المخزن الرئيسي',
  preparedBy:'موظف التجهيز',items:[{name:'قطعة أ',qty:'0.000001'},{name:'قطعة ب',qty:'1.000002'}]
 };
 const pending=warehouseDocument({...row,status:'pending'});
 assert.match(pending,/بانتظار التجهيز/);
 assert.match(pending,/الكمية المطلوبة/);
 assert.match(pending,/1\.000003/);
 assert.doesNotMatch(pending,/موظف التجهيز|جهّز الوصل|مسؤول الفاتورة/);
 const ready=warehouseDocument({...row,status:'ready'});
 assert.match(ready,/الكمية المجهّزة/);
 assert.match(ready,/جهّز الوصل/);
 assert.match(ready,/موظف التجهيز/);
 assert.match(warehouseDocument({...row,status:'pending',pricingPending:true}),/بانتظار تسعير المواد/);
});

test('warehouse transfers disclose the route and status without exposing amounts or crediting a cancelled request as prepared',()=>{
 const row={receiptNo:7,status:'cancelled',date:'2026-11-16',fromName:'المصدر',toName:'الوجهة',actor:'صاحب الطلب',
  preparedBy:'المجهز',cancellationNote:'<اختبار>',items:[{name:'لوح',qty:3,unitCost:881224,price:451011}]};
 const cancelled=warehouseDocument(row,true);
 for(const value of ['المصدر','الوجهة','صاحب الطلب','ملغى قبل التجهيز','&lt;اختبار&gt;']) assert.ok(cancelled.includes(value),value);
 assert.doesNotMatch(cancelled,/المجهز|881224|451011|<اختبار>/);
 const posted=warehouseDocument({...row,status:'posted'},true);
 assert.match(posted,/جهّز الوصل/);
 assert.match(posted,/المجهز/);
 assert.doesNotMatch(posted,/سبب الإلغاء/);
});
