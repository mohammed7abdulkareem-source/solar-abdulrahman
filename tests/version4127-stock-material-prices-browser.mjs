// Run --seed on the isolated 4.1.26 baseline, upgrade its database, then run the browser checks.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4127_stock_release_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3364';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3363';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4127/integration/release';
const {db,sql,rpc,fingerprint,createHarness}=await import('./version4-browser-support.mjs');
assert.match(db,/^solar_v4127_stock_[a-z0-9_]+_browser$/);
const path=join(process.env.SOLAR_ARTIFACT_DIR,'fixture.json');
const prices={fixed:130000,fixedBook:111123.45,missing:72661.75,zero:0,noStock:88777,before:95000,after:98000};
const money=value=>Number(String(value).replace(/[^0-9.-]/g,''));
async function rate(to){
 const now=await rpc('admin','solar_exchange_rate_get',{});
 await rpc('admin','solar_exchange_rate_set',{rate:to,expected_revision:now.revision});
}
const stock=(who,payload={})=>rpc(who,'solar_inventory',{action:'stock',payload});
const priced=(who,payload={})=>stock(who,{inventoryMaterialPrices:true,...payload});
const product=(rows,id)=>rows.find(row=>Number(row.id)===id);
async function seed(){
 const marked=randomUUID(),warehouse=randomUUID(),base=Date.now(),key='INV-QA-'+base;
 const items={auto:base,fixed:base+1,missing:base+2,zero:base+3,noStock:base+4};
 const a=base+10,b=base+11,foreign=base+12,supplier=base+13;
 for(const [uid,role,permissions] of [[marked,'admin_staff',{stock:true,capital:true,sale:true}],[warehouse,'warehouse',{stock:true}]]){
  sql("insert into public.profiles(id,username,display_name,user_type,active,permissions,phone) values('"+uid+"','inv_"+uid+"','اختبار المخزون "+role+"','"+role+"',true,'"+JSON.stringify(permissions)+"','07700000000')");
 }
 sql("insert into solar_private.warehouses(id,name,code,active) overriding system value values("+a+",'مخزن ألف "+base+"','A"+a+"',true),("+b+",'مخزن باء "+base+"','B"+b+"',true),("+foreign+",'مخزن خارج الصلاحية "+base+"','F"+foreign+"',true);insert into solar_private.warehouse_access(user_id,warehouse_ids) values('"+marked+"',array["+a+","+b+"]::bigint[]),('"+warehouse+"',array["+a+"]::bigint[])");
 for(const [k,qty,cost] of [['auto',0,0],['fixed',9,prices.fixedBook],['missing',10,prices.missing],['zero',2,0],['noStock',0,prices.noStock]]){
  sql("insert into public.products(id,code,name,qty,cost) values("+items[k]+",'"+key+"-"+k+"','مادة "+k+" "+base+"',"+qty+","+cost+")");
 }
 sql("insert into public.suppliers(id,name,account_currency) values("+supplier+",'مورد المخزون "+base+"','IQD')");
 await rate(1500);
 for(const [sourceCurrency,price] of [['IQD',100000],['USD',60]]){
  await rpc('admin','solar_invoice_save',{request_id:randomUUID(),payload:{kind:'purchase',mode:'credit',partyId:supplier,party:'مورد المخزون '+base,warehouseId:1,sourceCurrency,
   cashCurrency:'IQD',exchangeRate:sourceCurrency==='USD'?1500:1,marketRate:1500,accountRevision:0,items:[{id:items.auto,qty:8,price}]}});
 }
 const all=Object.values(items).join(',');
 const allocate=['update solar_private.warehouse_stocks set qty=0,reserved_qty=0 where product_id in('+all+')'];
 for(const [wh,entries] of [[a,[['auto',8,2],['fixed',2,0],['missing',1,0],['zero',2,0]]],[b,[['auto',3,0],['fixed',3,1],['missing',2,0]]],[foreign,[['auto',3,0],['fixed',3,0],['missing',7,0]]]]){
  for(const [k,q,res] of entries)allocate.push('insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty,reserved_qty) values('+[wh,items[k],q+res,0].join(',')+') on conflict(warehouse_id,product_id) do update set qty=excluded.qty,reserved_qty=excluded.reserved_qty');
 }
 sql('begin;'+allocate.join(';')+';commit;');
 for(const [from,id,num] of [[a,items.auto,2],[b,items.fixed,1]]){
  const branch=await stock('admin',{warehouseId:from}),row=product(branch.products,id);
  await rpc('admin','solar_inventory',{action:'transfer',request_id:randomUUID(),payload:{fromId:from,toId:foreign,note:'حجز كمية الاختبار',items:[{productId:id,qty:num,revision:row.stockRevision}]}});
 }
 const management=await rpc('admin','solar_wholesale_pricing',{action:'state'});
 const rules=[['fixed',prices.fixed,true],['auto',999999,false]].map(([k,minPrice,enabled])=>({productId:items[k],minPrice,enabled,expectedRevision:product(management.products,items[k]).revision}));
 await rpc('admin','solar_wholesale_pricing',{action:'save',request_id:randomUUID(),payload:{items:rules}});
 const userState=await rpc('admin','solar_profit_basis_users',{action:'state'});
 await rpc('admin','solar_profit_basis_users',{action:'save',request_id:randomUUID(),payload:{token:userState.token,changes:[{id:marked,enabled:true}]}});
 const previous=await priced(marked);
 assert.equal(product(previous.products,items.auto).cost,null,'prior screenshot issue was not reproduced');
 assert.equal(product(previous.products,items.fixed).cost,prices.fixed);
 const f={marked,warehouse,items,a,b,foreign,key,base};
 await mkdir(process.env.SOLAR_ARTIFACT_DIR,{recursive:true});await writeFile(path,JSON.stringify(f));
 console.log('PASS baseline reproduces empty unchecked mixed-currency inventory price with real purchases');
}
async function verify(h){
 const f=JSON.parse(await readFile(path,'utf8')),{marked,warehouse,items,a,b,foreign,key}=f;
 await rate(1500);
 const office=await priced(marked,{byWarehouse:true});
 assert.equal(office.showCost,true);
 for(const [kind,value,source] of [['fixed',prices.fixed,'configured'],['auto',prices.before,'cost'],['missing',prices.missing,'cost'],['zero',0,'cost'],['noStock',prices.noStock,'cost']]){
  const row=product(office.products,items[kind]);assert.equal(row.cost,value,kind+' inventory price');assert.equal(row.floorSource,source);
  assert.ok(!Object.hasOwn(row,'bookCost')&&!Object.hasOwn(row,'cost_basis'));
 }
 await rpc(marked,'solar_inventory',{action:'stock',payload:{warehouseId:foreign,inventoryMaterialPrices:true}},403);
 assert.deepEqual(office.warehouses.map(r=>Number(r.id)).sort(),[a,b].sort());
 assert.equal(product(office.products,items.auto).bookQty,13);assert.equal(product(office.products,items.auto).qty,11);
 assert.equal(product(office.products,items.fixed).bookQty,6);assert.equal(product(office.products,items.fixed).qty,5);
 const warehouseOnly=await priced(warehouse,{byWarehouse:true});assert.equal(warehouseOnly.showCost,false);
 const staffItem=product(warehouseOnly.products,items.auto);for(const k of ['cost','bookCost','cost_basis','floorSource'])assert.ok(!Object.hasOwn(staffItem,k),'quantity-only stock includes '+k);
 const saleCatalog=await rpc(marked,'solar_inventory',{action:'catalog'});assert.equal(product(saleCatalog,items.auto).cost,null);
 const plain=await stock(marked);assert.equal(product(plain.products,items.auto).cost,null,'ordinary sale inventory changed');
 const companyCapital=await rpc('admin','solar_capital_current_snapshot',{}),companyStock=await priced('admin');
 assert.equal(product(companyCapital.stock.rows,items.fixed).cost,prices.fixedBook);assert.equal(product(companyStock.products,items.fixed).cost,prices.fixedBook);
 const personalCapital=await rpc(marked,'solar_capital_current_snapshot',{});assert.equal(product(personalCapital.stock.rows,items.auto).cost,prices.before);
 assert.equal(product(personalCapital.stock.rows,items.fixed).cost,prices.fixed);
 const totals=(automatic)=>13*automatic+6*prices.fixed+3*prices.missing;
 assert.equal(personalCapital.stock.value,totals(prices.before),'capital omitted scoped stock or counted foreign stock');
 const dataBeforeChange=fingerprint();await rate(1600);const changed=await priced(marked);
 assert.equal(product(changed.products,items.auto).cost,prices.after);
 assert.equal(product(changed.products,items.fixed).cost,prices.fixed);
 assert.equal(fingerprint(),dataBeforeChange,'valuation updated historic financial or inventory rows');
 for(const name of ['solar_capital_snapshot','solar_capital_current_snapshot']){
  const valuation=await rpc(marked,name,{});assert.equal(valuation.stock.value,totals(prices.after));
  const company=await rpc('admin',name,{});assert.equal(company.stock.value,companyCapital.stock.value);
  assert.equal(product(company.stock.rows,items.auto).cost,prices.before,'company book cost followed FX');
 }
 const {page,ctx}=await h.open(marked,'/?section=stock');
 const view=page.getByRole('region',{name:'أرصدة المواد'}),search=view.getByRole('searchbox',{name:'بحث أرصدة المخازن'});
 await search.fill(key);
 const toggle=view.getByRole('checkbox',{name:/إظهار (سعر|أسعار|قيمة)/});await toggle.waitFor();
 const available=view.locator('[data-stock-metric="available"] bdi'),value=view.locator('[data-stock-metric="value"] bdi');
 assert.equal(await toggle.isChecked(),false);assert.equal(await value.count(),0);
 await toggle.check();await value.waitFor();assert.equal(money(await value.innerText()),totals(prices.after));
 assert.equal(money(await available.innerText()),21);assert.equal(money(await view.locator('[data-stock-metric="reserved"] bdi').innerText()),3);
 const autoRow=view.locator('[data-stock-product="'+items.auto+'"]');
 await rate(1700);await page.evaluate(()=>window.dispatchEvent(new Event('focus')));
 await page.waitForFunction(total=>Number(document.querySelector('[data-stock-metric="value"] bdi')?.textContent.replaceAll(',',''))===total,totals(101000));
 assert.ok((await autoRow.innerText()).includes('101,000'));assert.ok((await view.locator('[data-stock-product="'+items.fixed+'"]').innerText()).includes('130,000'));
 await rate(1600);await page.evaluate(()=>window.dispatchEvent(new Event('focus')));
 await page.waitForFunction(total=>Number(document.querySelector('[data-stock-metric="value"] bdi')?.textContent.replaceAll(',',''))===total,totals(prices.after));
 assert.ok((await autoRow.innerText()).includes('98,000'));assert.ok((await autoRow.innerText()).includes('1,274,000'));
 assert.ok((await view.locator('[data-stock-product="'+items.zero+'"]').innerText()).includes('0'));
 assert.equal(await view.locator('[data-stock-product="'+items.noStock+'"]').count(),0);
 await view.getByLabel('إخفاء الأرصدة الصفرية',{exact:true}).uncheck();
 assert.ok((await view.locator('[data-stock-product="'+items.noStock+'"]').innerText()).includes('88,777'));assert.equal(money(await value.innerText()),totals(prices.after));
 await view.getByLabel('إخفاء الأرصدة الصفرية',{exact:true}).check();
 await h.layout(page,'scoped-total-inventory',autoRow);
 const exportActions=page.locator('.inventoryBalanceExport .reportExport');
 const totalPDF=await h.report(page,ctx,exportActions,'scoped-total');
 assert.ok(totalPDF.includes('2,271,985.25')&&totalPDF.includes('1,274,000'));
 for(const sentinel of ['999,999','111,123.45','مخزن خارج الصلاحية'])assert.ok(!totalPDF.includes(sentinel));
 await view.getByRole('radio',{name:'حسب المخزن',exact:true}).check();const branch=view.locator('[data-stock-warehouse="'+a+'"]');await branch.waitFor();
 assert.equal(await view.locator('[data-stock-warehouse="'+foreign+'"]').count(),0);
 assert.ok((await branch.locator('[data-stock-product="'+items.auto+'"]').innerText()).includes('980,000'));
 assert.ok((await view.locator('[data-stock-warehouse="'+b+'"] [data-stock-product="'+items.auto+'"]').innerText()).includes('294,000'));
 await h.layout(page,'scoped-grouped-inventory',branch);
 const grouped=await h.report(page,ctx,exportActions,'scoped-warehouses');
 assert.ok(grouped.includes('980,000')&&grouped.includes('294,000')&&grouped.includes('2,271,985.25'));
 await toggle.uncheck();assert.equal(await value.count(),0);
 const quantityPDF=await h.report(page,ctx,exportActions,'scoped-quantity');
 assert.ok(!quantityPDF.includes('98,000')&&!quantityPDF.includes('130,000')&&!quantityPDF.includes('2,271,985.25'),'quantity PDF includes a price');
 const {page:capital}=await h.open(marked,'/?section=capital');
 const tile=capital.getByRole('button',{name:'تفاصيل المخزون بأسعار المواد',exact:true});
 assert.ok((await tile.innerText()).includes('2,271,985.25'));
 const [preview]=await Promise.all([capital.waitForEvent('popup'),tile.click()]);
 await preview.locator('.pdfPage img').first().waitFor({timeout:90000});
 const capitalHtml=await capital.evaluate(()=>window.__documentHtmls.findLast(html=>html.includes('كشف المخزون بأسعار المواد')));
 assert.ok(capitalHtml?.includes('2,271,985.25')&&capitalHtml.includes('1,274,000'));
 assert.ok(!capitalHtml.includes('111,123.45')&&!capitalHtml.includes('999,999'));
 const download=preview.waitForEvent('download');await preview.locator('#pdfDownload').click();await (await download).saveAs(join(h.dir,'scoped-capital.pdf'));await preview.close();
 const {page:warehousePage}=await h.open(warehouse,'/?section=stock');
 const warehouseView=warehousePage.locator('.inventoryBalancePanel');await warehouseView.locator('[data-stock-metric="available"]').waitFor();
 assert.equal(await warehouseView.getByRole('checkbox',{name:/إظهار (الكلفة|سعر|أسعار|قيمة)/}).count(),0);
 const {page:admin}=await h.open('admin','/?section=stock');
 const adminView=admin.locator('.inventoryBalancePanel');await adminView.getByRole('searchbox',{name:'بحث أرصدة المخازن'}).fill(key);
 await adminView.getByRole('checkbox',{name:'إظهار الكلفة',exact:true}).check();
 const adminManual=adminView.locator('[data-stock-product="'+items.fixed+'"]');
 await admin.waitForFunction(id=>(document.querySelector('[data-stock-product="'+id+'"]')?.innerText||'').includes('111,123.45'),items.fixed);
 assert.ok(!(await adminManual.innerText()).includes('130,000'));
 h.checks.valuation={openTabFx:true,before:totals(prices.before),after:totals(prices.after),stockOnlyFallback:prices.after,manual:prices.fixed,
  allowedWarehouses:2,available:21,reserved:3,zeroCostShown:true,companyBookCost:prices.before,quantityOnly:true};
}
if(process.argv.includes('--seed'))await seed();
else{const h=await createHarness('scoped-stock-price');
 try{await verify(h);await h.finish();console.log('PASS scoped invoice-independent inventory, valuation, quantity-only reports, actual PDF/preview/share and mobile/desktop');}
 catch(error){await h.fail(error);throw error;}finally{await h.close();}}
