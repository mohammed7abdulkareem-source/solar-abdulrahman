import test from 'node:test';
import assert from 'node:assert/strict';
import {structuredNotification,notificationPreview,notificationQuantity} from '../app/notification-details.mjs';

test('purchase inbox and toast whitelist material identity and quantity without financial fields or raw body',()=>{
 const notice={event:'purchase_received',title:'UNSAFE 667788',body:'supplier-secret cost 667788 total 998877',details:{type:'purchase_received',invoiceId:90,supplier:'supplier-secret',total:998877,items:[{name:'لوح 600W',category:'ألواح',brand:'FULLMAX',qty:31,cost:667788,price:998877,accountAmount:12345,invoiceId:90}]}};
 const copy=JSON.stringify(notice),data=structuredNotification(notice);
 assert.deepEqual(data.items,[{name:'لوح 600W',category:'ألواح',brand:'FULLMAX',qty:31}]);
 assert.deepEqual(notificationPreview(notice),{title:'دخول مواد جديدة',body:'1 فقرة في المواد المستلمة'});
 for(const hidden of['667788','998877','12345','supplier-secret','invoiceId','cost','price','accountAmount'])assert.ok(!JSON.stringify([data,notificationPreview(notice)]).includes(hidden),hidden);
 assert.equal(JSON.stringify(notice),copy);
});

test('price notices distinguish current manual floors from older inactive amounts and discard purchase costs',()=>{
 const notice={event:'wholesale_prices_updated',details:{type:'wholesale_prices_updated',currency:'IQD',cost:76321,items:[{name:'لوح',category:'ألواح',brand:'FULLMAX',minPrice:120000.25,enabled:true,cost:76321,qty:8},{name:'انفيرتر',category:'انفيرتر',brand:'F',minPrice:2000000,enabled:false,purchasePrice:987654},{name:'بطارية',minPrice:null,enabled:false}]}},data=structuredNotification(notice);
 assert.deepEqual(data.items,[{name:'لوح',category:'ألواح',brand:'FULLMAX',minPrice:120000.25,enabled:true},{name:'انفيرتر',category:'انفيرتر',brand:'F',minPrice:null,enabled:false,inactiveManualPrice:2000000},{name:'بطارية',category:'',brand:'',minPrice:null,enabled:false}]);
 assert.equal(data.currency,'IQD');
 for(const hidden of['76321','987654','purchasePrice','cost','qty'])assert.ok(!JSON.stringify(data).includes(hidden),hidden);
 assert.equal(notificationPreview(notice).body,'3 مادة في تحديث الأسعار');
});

test('unavailable/malformed new details never fall back to a potentially sensitive purchase body',()=>{
 for(const details of[null,{},[],{type:'wrong',items:[]},{type:'purchase_received',items:null}]){
  const notice={event:'purchase_received',body:'secret price 9000',details};
  assert.equal(structuredNotification(notice).items,null);
  assert.ok(!notificationPreview(notice).body.includes('9000'));
 }
 assert.equal(structuredNotification({event:'wholesale_prices_updated',details:{type:'wholesale_prices_updated',currency:'USD',items:[]}}).items,null);
 const legacy={event:'warehouse_ready',title:'تم التجهيز',body:'وصل رقم 10'};
 assert.equal(structuredNotification(legacy),null);assert.deepEqual(notificationPreview(legacy),{title:legacy.title,body:legacy.body});
});

test('all rows remain available and invalid quantities stay unknown instead of becoming invented zeros',()=>{
 const items=Array.from({length:350},(_,index)=>({name:'مادة '+index,category:'ألواح',brand:'براند',qty:index+0.125}));
 const data=structuredNotification({event:'purchase_received',details:{type:'purchase_received',items}});
 assert.equal(data.items.length,350);assert.equal(data.items[349].name,'مادة 349');assert.equal(data.items[349].qty,349.125);
 assert.equal(notificationQuantity(349.125),'349.125');assert.equal(notificationQuantity(1000),'1,000');
 const invalid=structuredNotification({event:'purchase_received',details:{type:'purchase_received',items:[null,[],{qty:false},{qty:-1},{qty:''},{qty:0},{name:'<img src=x onerror=alert(1)>',brand:'<script>x</script>',qty:'1.125'}]}});
 assert.equal(invalid.items.length,7);assert.deepEqual(invalid.items.slice(0,5).map(row=>row.qty),[null,null,null,null,null]);assert.equal(invalid.items[5].qty,0);
 assert.equal(invalid.items[6].name,'<img src=x onerror=alert(1)>');assert.equal(invalid.items[6].brand,'<script>x</script>');assert.equal(invalid.items[6].qty,1.125);
});


test('legacy codes are never displayed as a type; additive category preserves all allowed values',()=>{
 for(const event of ['purchase_received','wholesale_prices_updated']){
  const item={name:'15KW',model:'SECRET-CODE-0003',brand:'FULLMAX',...(event==='purchase_received'?{qty:2}:{minPrice:120000,enabled:true})};
  const details={type:event,...(event==='wholesale_prices_updated'?{currency:'IQD'}:{}),items:[item]};
  const source=JSON.stringify(details),legacy=structuredNotification({event,details});
  assert.equal(legacy.items[0].category,'');
  assert.ok(!JSON.stringify(legacy).includes('SECRET-CODE-0003'));
  const enriched=structuredNotification({event,details:{...details,items:[{...item,category:'بطارية'}]}});
  assert.equal(enriched.items[0].category,'بطارية');
  const {category,...identity}=enriched.items[0];
  assert.deepEqual({...identity,category:''},legacy.items[0]);
  assert.ok(!JSON.stringify(enriched).includes('SECRET-CODE-0003'));
  assert.equal(JSON.stringify(details),source);
 }
});

test('purchase warehouse snapshot appears in compact previews without exposing raw receipt metadata',()=>{
 const notice={event:'purchase_received',warehouse_name:'WRONG-WAREHOUSE',body:'SECRET invoice90 cost998877',details:{type:'purchase_received',warehouseName:'  مخزن أربيل الرئيسي  ',warehouseId:99,invoiceId:90,total:998877,items:[{name:'لوح600W',category:'ألواح',brand:'FULLMAX',qty:12.5,cost:998877}]}};
 const source=JSON.stringify(notice),data=structuredNotification(notice);
 assert.equal(data.warehouseName,'مخزن أربيل الرئيسي');assert.equal(data.itemSummary,'1 فقرة في المواد المستلمة');
 assert.deepEqual(notificationPreview(notice),{title:'دخول مواد جديدة',body:'المخزن: مخزن أربيل الرئيسي · 1 فقرة في المواد المستلمة'});
 assert.deepEqual(data.items,[{name:'لوح600W',category:'ألواح',brand:'FULLMAX',qty:12.5}]);
 for(const secret of ['SECRET','WRONG-WAREHOUSE','998877','invoiceId','warehouseId'])assert.ok(!JSON.stringify(data).includes(secret),secret);
 assert.equal(JSON.stringify(notice),source);
});

test('missing or malformed warehouse names keep legacy preview without inventing a warehouse',()=>{
 for(const warehouseName of [undefined,null,'','   ',false,99,[],{name:'مخزن غير موثوق'}]){
  const notice={event:'purchase_received',body:'المخزن: SECRET',warehouseName:'SECRET',details:{type:'purchase_received',warehouseName,items:[]}};
  assert.equal(structuredNotification(notice).warehouseName,'');
  assert.deepEqual(notificationPreview(notice),{title:'دخول مواد جديدة',body:'0 فقرة في المواد المستلمة'});
 }
 const invalid={event:'purchase_received',details:{type:'wrong',warehouseName:'SECRET',items:[]}};
 assert.equal(structuredNotification(invalid).warehouseName,'');assert.ok(!notificationPreview(invalid).body.includes('SECRET'));
 const pricing={event:'wholesale_prices_updated',details:{type:'wholesale_prices_updated',currency:'IQD',warehouseName:'SECRET',items:[]}};
 assert.equal(structuredNotification(pricing).warehouseName,'');assert.equal(notificationPreview(pricing).body,'0 مادة في تحديث الأسعار');
});

test('warehouse names remain literal text, including markup and long multilingual names',()=>{
 const warehouseName='مخزن <img src=x onerror=alert(1)> Erbil & أربيل '+ 'أ '.repeat(150);
 const data=structuredNotification({event:'purchase_received',details:{type:'purchase_received',warehouseName,items:[]}});
 assert.equal(data.warehouseName,warehouseName.trim());assert.equal(data.summary,'المخزن: '+warehouseName.trim()+' · 0 فقرة في المواد المستلمة');
 assert.equal(data.items.length,0);
});
