// Actual admin and staff stock views backed by an isolated PostgREST and database.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4128_admin_stock_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3370';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3373';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4128/integration/release';
const {db,sql,rpc,fingerprint,createHarness}=await import('./version4-browser-support.mjs');
assert.match(db,/^solar_v4128_[a-z0-9_]+_browser$/);
const stamp=Date.now(),prefix='QA28-'+stamp,staff=randomUUID(),cashier=randomUUID(),warehouse=randomUUID(),a=stamp+10,b=stamp+11;
const items=[
 {id:stamp,key:'fixed',cost:100000,sale:125000,a:18,b:9,held:2},
 {id:stamp+1,key:'unchecked',cost:70000.25,sale:70000.25,a:4,b:3,held:0},
 {id:stamp+2,key:'unspecified',cost:45000,sale:45000,a:0,b:2,held:0},
 {id:stamp+3,key:'reserved',cost:80000,sale:74000,a:2,b:0,held:2},
 {id:stamp+4,key:'zero',cost:89000,sale:89000,a:0,b:0,held:0}
];
const stock=(who,payload={},status=200)=>rpc(who,'solar_inventory',{action:'stock',payload},status);
const numeric=text=>Number(String(text).replace(/[^\d.-]/g,''));
const row=(data,id)=>data.products.find(x=>Number(x.id)===id);
const sum=(key,where)=>items.reduce((n,p)=>n+(where==='a'?p.a:where==='b'?p.b:p.a+p.b)*p[key],0);
const measures=(scope)=>scope==='a'?{available:20,reserved:4,cost:sum('cost','a'),sale:sum('sale','a')}:
 scope==='b'?{available:14,reserved:0,cost:sum('cost','b'),sale:sum('sale','b')}:{available:34,reserved:4,cost:sum('cost'),sale:sum('sale')};
async function seed(){
 for(const [id,role] of [[staff,'admin_staff'],[warehouse,'warehouse']]){
  sql("insert into public.profiles(id,username,display_name,user_type,active,is_admin,phone,permissions) values('"+id+"','stock28_"+id+"','اختبار المخزون "+role+"','"+role+"',true,false,'07700000000','{\"stock\":true}')");
 }
 sql("insert into public.profiles(id,username,display_name,user_type,active,is_admin,phone,permissions) values('"+cashier+"','stock28_"+cashier+"','أمين قاصة اختبار','admin_staff',true,false,'07700000000','{\"cash\":true}')");
 sql("insert into solar_private.warehouses(id,name,code,active) overriding system value values("+a+",'مخزن ألف "+stamp+"','QAA"+stamp+"',true),("+b+",'مخزن باء "+stamp+"','QAB"+stamp+"',true);insert into solar_private.warehouse_access(user_id,warehouse_ids) values('"+staff+"',array["+a+"]::bigint[]),('"+warehouse+"',array["+a+"]::bigint[])");
 for(const p of items){
  sql("begin;insert into public.products(id,code,name,qty,cost)values("+p.id+",'"+prefix+"-"+p.key+"','مادة "+p.key+" "+stamp+"',"+(p.a+p.b)+","+p.cost+");update solar_private.warehouse_stocks set qty=0 where product_id="+p.id+";insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)values("+a+","+p.id+","+p.a+"),("+b+","+p.id+","+p.b+");commit");
 }
 for(const p of items.filter(x=>x.held>0)){
  const s=await stock('admin',{warehouseId:a});
  await rpc('admin','solar_inventory',{action:'transfer',request_id:randomUUID(),payload:{fromId:a,toId:b,note:'حجز كمية اختبار',items:[{productId:p.id,qty:p.held,revision:row(s,p.id).stockRevision}]}});
 }
 const state=await rpc('admin','solar_wholesale_pricing',{action:'state'});
 const rules=[[items[0],125000,true],[items[1],195000,false],[items[3],74000,true]].map(([p,minPrice,enabled])=>({productId:p.id,minPrice,enabled,expectedRevision:row(state,p.id).revision}));
 await rpc('admin','solar_wholesale_pricing',{action:'save',request_id:randomUUID(),payload:{items:rules}});
 const basis=await rpc('admin','solar_profit_basis_users',{action:'state'});
 await rpc('admin','solar_profit_basis_users',{action:'save',request_id:randomUUID(),payload:{token:basis.token,changes:[{id:staff,enabled:true}]}});
}
async function acl(){
 const vanilla=await stock('admin'),enriched=await stock('admin',{adminSalePrices:true,byWarehouse:true});
 const visibleToStaff=await stock(staff,{inventoryMaterialPrices:true,byWarehouse:true});
 const scopedAdmin=await stock('admin',{warehouseId:a,adminSalePrices:true,byWarehouse:true});
 const scopedStaff=await stock(staff,{warehouseId:a,inventoryMaterialPrices:true,byWarehouse:true});
 for(const p of items){
  const extra=row(enriched,p.id),normal=row(vanilla,p.id);assert.equal(extra.cost,p.cost);assert.equal(extra.salePrice,p.sale);
  assert.equal(extra.salePriceSource,['fixed','reserved'].includes(p.key)?'configured':'cost');assert.ok(!('salePrice'in normal));
  assert.equal(extra.qty,normal.qty);assert.equal(extra.bookQty,normal.bookQty);assert.equal(extra.reservedQty,normal.reservedQty);
  const single=row(scopedAdmin,p.id),limited=row(scopedStaff,p.id);
  assert.deepEqual([single.qty,single.reservedQty,single.bookQty],[limited.qty,limited.reservedQty,limited.bookQty]);
  assert.equal(limited.cost,p.sale);assert.ok(!('salePrice'in limited)&&!('bookCost'in limited));
  assert.equal(row(visibleToStaff,p.id).qty,p.a-p.held);assert.equal(extra.qty,p.a+p.b-p.held);
 }
 await stock(cashier,{adminSalePrices:true},403);
 for(const who of [staff,warehouse]){
  await stock(who,{adminSalePrices:true},403);
  const allowed=await stock(who);assert.ok(allowed.products.every(p=>!('salePrice'in p)&&!('salePriceSource'in p)));
  await stock(who,{warehouseId:b},403);
 }
}
async function exercise(h){
 await seed();await acl();const before=fingerprint();
 const {page,ctx}=await h.open('admin','/?section=stock'),view=page.locator('.inventoryBalancePanel');
 await view.getByRole('searchbox',{name:'بحث أرصدة المخازن'}).fill(prefix);
 const cost=view.getByRole('checkbox',{name:'إظهار الكلفة',exact:true}),sale=view.getByRole('checkbox',{name:'إظهار سعر البيع',exact:true}),zero=view.getByRole('checkbox',{name:'إخفاء الأرصدة الصفرية',exact:true});
 const metric=k=>view.locator('[data-stock-metric="'+k+'"] bdi');
 const material=(node,id)=>node.locator('[data-stock-product="'+id+'"]');
 const formatted=n=>Number(n).toLocaleString('en-US',{maximumFractionDigits:4});
 const compare=async(node,val)=>{await node.waitFor();assert.equal(numeric(await node.innerText()),val);};
 const report=async(label,c,s,group=false)=>{
  const source=await h.report(page,ctx,page.locator('.inventoryBalanceExport .reportExport'),label);
  const rendered=await page.evaluate(html=>new DOMParser().parseFromString(html,'text/html').body.textContent,source);
  const headers=await page.evaluate(html=>Array.from(new DOMParser().parseFromString(html,'text/html').querySelectorAll('thead th')).map(th=>th.textContent),source);
  assert.equal(headers.some(text=>text.startsWith('كلفة الوحدة')),c,label+' explicit cost heading');
  assert.equal(headers.some(text=>text.startsWith('سعر البيع')),s,label+' explicit sale heading');
  assert.ok(!rendered.includes('195,000'),'unchecked saved manual price in export');
  for(const [flag,unit,total] of [[c,'100,000',formatted(sum('cost'))],[s,'125,000',formatted(sum('sale'))]]){
   assert.equal(rendered.includes(unit),flag,label+' unit metric');assert.equal(rendered.includes(total),flag,label+' valuation');
  }
  if(group)for(const wh of ['a','b'])for(const [flag,key] of [[c,'cost'],[s,'sale']])if(flag)assert.ok(rendered.includes(formatted(sum(key,wh))),label+' warehouse subtotal');
 };
 async function metrics(c,s,scope){
  const m=measures(scope);await compare(metric('available'),m.available);await compare(metric('reserved'),m.reserved);
  if(c)await compare(metric('value'),m.cost);else assert.equal(await metric('value').count(),0);
  if(s)await compare(metric('saleValue'),m.sale);else assert.equal(await metric('saleValue').count(),0);
 }
 async function controls(c,s){
  await cost.setChecked(c);await sale.setChecked(s);
  const r=material(view,items[0].id).first();await r.waitFor();
  if(c)await r.locator('[data-stock-unit="cost"]').waitFor();else assert.equal(await r.locator('[data-stock-unit="cost"]').count(),0);
  if(s)await r.locator('[data-stock-unit="sale"]').waitFor();else assert.equal(await r.locator('[data-stock-unit="sale"]').count(),0);
 }
 await cost.waitFor();assert.equal(await view.getByRole('checkbox').count(),3);
 assert.equal(await cost.isChecked(),false);assert.equal(await sale.isChecked(),false);assert.equal(await zero.isChecked(),true);
 for(const [c,s,label] of [[false,false,'quantity'],[true,false,'cost'],[false,true,'sale'],[true,true,'dual']]){
  await controls(c,s);await metrics(c,s,'all');
  await compare(metric('products'),4);
  assert.equal(await material(view,items[3].id).count(),1);assert.equal(await material(view,items[4].id).count(),0);
  await zero.uncheck();await material(view,items[4].id).waitFor();await metrics(c,s,'all');await compare(metric('products'),5);
  await zero.check();await material(view,items[4].id).waitFor({state:'detached'});
  if(label!=='dual')await report(label,c,s);
 }
 const dualFixed=material(view,items[0].id);
 assert.ok((await dualFixed.locator('[data-stock-value="cost"]').innerText()).includes('2,700,000'));
 assert.ok((await dualFixed.locator('[data-stock-value="sale"]').innerText()).includes('3,375,000'));
 await h.layout(page,'admin-dual-total',dualFixed);
 await view.getByRole('radio',{name:'حسب المخزن',exact:true}).check();const group=wh=>view.locator('[data-stock-warehouse="'+wh+'"]');
 const small=material(group(a),items[0].id);await small.waitFor();
 assert.ok((await group(a).locator('header').innerText()).includes(formatted(sum('sale','a'))));assert.ok((await group(b).locator('header').innerText()).includes(formatted(sum('cost','b'))));
 assert.ok((await small.locator('[data-stock-value="cost"]').innerText()).includes('1,800,000'));
 assert.ok((await small.locator('[data-stock-value="sale"]').innerText()).includes('2,250,000'));
 await metrics(true,true,'all');await h.layout(page,'admin-dual-by-warehouse',small);await report('dual-grouped',true,true,true);
 await view.getByRole('combobox',{name:'عرض رصيد المخزن'}).selectOption(String(a));await group(b).waitFor({state:'detached'});await metrics(true,true,'a');
 const {page:limited}=await h.open(staff,'/?section=stock'),limitedView=limited.locator('.inventoryBalancePanel');
 await limitedView.getByRole('searchbox',{name:'بحث أرصدة المخازن'}).fill(prefix);await limitedView.getByRole('checkbox',{name:'إظهار سعر المادة',exact:true}).check();
 assert.equal(await limitedView.getByRole('checkbox',{name:'إظهار سعر البيع',exact:true}).count(),0);
 await compare(limitedView.locator('[data-stock-metric="available"] bdi'),20);await compare(limitedView.locator('[data-stock-metric="reserved"] bdi'),4);
 await compare(limitedView.locator('[data-stock-metric="value"] bdi'),sum('sale','a'));
 const {page:quantityOnly}=await h.open(warehouse,'/?section=stock'),warehouseView=quantityOnly.locator('.inventoryBalancePanel');
 await warehouseView.getByRole('searchbox',{name:'بحث أرصدة المخازن'}).fill(prefix);await compare(warehouseView.locator('[data-stock-metric="available"] bdi'),20);
 assert.equal(await warehouseView.getByRole('checkbox').count(),1);
 assert.equal(fingerprint(),before,'reading and exporting changed books or inventory');
 h.checks.adminInventory={all:measures('all'),oneWarehouse:measures('a'),fourDisplayModes:true,bothZeroModes:true,restrictedUsersDenied:true};
}
const h=await createHarness('admin-stock-dual-pricing');
try{await exercise(h);await h.finish();console.log('PASS admin independent cost and sale amounts, storage and roles unchanged, four PDF modes, scoped quantities, mobile and desktop');}
catch(error){await h.fail(error);throw error;}finally{await h.close();}
