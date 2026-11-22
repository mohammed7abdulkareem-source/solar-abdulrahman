// Seed settled receipts on the previous release with --seed-legacy, apply migrations, then run without arguments.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {join} from 'node:path';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4130_material_prices_final_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3392';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3393';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4130/integration/final';
const {db,sql,rpc,createHarness,fingerprint}=await import('./version4-browser-support.mjs');
assert.match(db,/^solar_(v4126_wholesale_[a-z0-9_]+|v4130_[a-z0-9_]+)_browser$/);
const fixturePath=join(process.env.SOLAR_ARTIFACT_DIR,'prior-receipt.json');
const state=(who,payload={})=>rpc(who,'solar_wholesale_pricing',{action:'state',payload});
async function rate(value){const r=await rpc('admin','solar_exchange_rate_get',{});return rpc('admin','solar_exchange_rate_set',{rate:value,expected_revision:r.revision});}
async function seed(){
const sample=Date.now(),seller=randomUUID(),hidden=randomUUID(),outside=randomUUID();
const item=sample,custom=sample+1,party=sample+2,supplier=sample+3;
const productName='لوح تلقائي '+sample,customName='لوح مخصص '+sample,customerName='متجر اختبار الحد '+sample,vendorName='مورد اختبار الحد '+sample;
for(const [user,name] of [[seller,'بائع الحد التلقائي'],[hidden,'بائع الحد المخفي'],[outside,'بائع خارج النطاق']]){
 sql("insert into public.profiles(id,username,display_name,is_admin,active,user_type,permissions,phone)values('"+user+"','auto_"+user+"','"+name+"',false,true,'admin_staff','{\"sale\":true,\"profit\":true,\"customers\":true,\"stock\":true,\"salesHistory\":true}','07700000000')");
}
sql("insert into public.products(id,code,name,qty,cost)values("+item+",'AUTO-"+item+"','"+productName+"',0,0),("+custom+",'CUSTOM-"+custom+"','"+customName+"',50,72000);insert into public.suppliers(id,name,account_currency) values("+supplier+",'"+vendorName+"','IQD');");
for(const [n,u] of [[0,seller],[1,hidden],[2,outside]])sql("insert into public.customers(id,name,customer_type,owner_id) values("+(party+n)+",'"+customerName+n+"','wholesale','"+u+"');");

async function configure(enabled){const revision=(await state('admin')).revision;return rpc('admin','solar_wholesale_pricing',{action:'configure',request_id:randomUUID(),payload:{enabled,mode:'selected',userIds:[seller,hidden],expectedRevision:revision}});}

const buy=(ccy,price,qty,fx)=>({kind:'purchase',mode:'credit',warehouseId:1,partyId:supplier,party:vendorName,sourceCurrency:ccy,cashCurrency:'IQD',marketRate:fx,exchangeRate:ccy==='USD'?fx:1,accountRevision:0,expenses:0,items:[{id:item,qty,price}]});
const sale=(id,price,idx=0)=>({kind:'sale',mode:'credit',warehouseId:1,partyId:party+idx,party:customerName+idx,sourceCurrency:'IQD',exchangeRate:1,items:[{id,price,qty:1}]});
const save=(who,payload,request_id=randomUUID())=>rpc(who,'solar_invoice_save',{request_id,payload});
await rate(1500);await configure(false);
const q1=await save('admin',buy('IQD',142591,10,1500));
const q2=await save('admin',buy('USD',100,10,1500));
const value=()=>Number(sql('select solar_private.current_unit_cost(id,cost_basis,cost) from public.products where id='+item));
assert.equal(value(),146295.5,'mixed basis at 1500');
const legacyNonce=randomUUID(),legacy=await save(seller,sale(item,145000),legacyNonce);
const basis=await rpc('admin','solar_profit_basis_users',{action:'state'});await rpc('admin','solar_profit_basis_users',{action:'save',request_id:randomUUID(),payload:{token:basis.token,changes:[{id:hidden,enabled:true}]}});
await configure(true);
const fixture={seller,hidden,outside,item,custom,party,supplier,productName,customName,customerName,vendorName,sample,legacy,legacyNonce,usdPurchase:q2.id};
console.log({item,q1:q1.id,q2:q2.id,legacy:legacy.id,firstFloor:value()});
mkdirSync(process.env.SOLAR_ARTIFACT_DIR,{recursive:true});
await seedHistoricalSystem(fixture);
}
async function seedHistoricalSystem(f){
 const engineer=randomUUID(),customer=f.sample+20,systemName='زبون المنظومة '+f.sample;
 sql("insert into public.profiles(id,username,display_name,user_type,active,permissions,phone) values('"+engineer+"','sys_"+engineer+"','مهندس اختبار مادة المنظومة','installer',true,'{}','07700000000');update public.profiles set permissions=permissions||'{\"system\":true}'::jsonb where id in('"+f.seller+"','"+f.hidden+"');insert into public.customers(id,name,owner_id,customer_type) values("+customer+",'"+systemName+"','"+f.seller+"','system'),("+(customer+1)+",'"+systemName+" خاص','"+f.hidden+"','system');");
 const body={kind:'system',mode:'credit',warehouseId:1,partyId:customer,party:systemName,installerId:engineer,customerAddress:'عنوان الوصل السابق',total:450000,items:[{id:f.item,qty:1,price:0},{id:f.custom,qty:1,price:0}]};
 const request_id=randomUUID(),receipt=await rpc(f.seller,'solar_invoice_save',{request_id,payload:body});
 const privateReceipt=await rpc(f.hidden,'solar_invoice_save',{request_id:randomUUID(),payload:{...body,partyId:customer+1,party:systemName+' خاص'}});
 Object.assign(f,{engineer,systemName,systemCustomer:customer,priorSystem:receipt.id,priorPersonalSystem:privateReceipt.id,priorSystemRequest:{request_id,payload:body}});
 writeFileSync(fixturePath,JSON.stringify(f));
}
async function run(h){
 const f=JSON.parse(readFileSync(fixturePath,'utf8'));
 const {seller,hidden,outside,item,custom,party,customerName,legacy,legacyNonce,productName}=f;
 const product=(s,id)=>s.products.find(row=>Number(row.id)===id);
 const policy=async(who,id)=>product(await state(who),id);
 const sale=(id,price,idx=0,qty=1)=>({kind:'sale',mode:'credit',warehouseId:1,partyId:party+idx,party:customerName+idx,
  sourceCurrency:'IQD',exchangeRate:1,items:[{id,price,qty}]});
 const invoice=(who,body,status=200,nonce=randomUUID())=>rpc(who,'solar_invoice_save',{request_id:nonce,payload:body},status);
 const totals=(id)=>sql("select jsonb_build_array(total,cost,profit,items) from (select t.total,t.cost,t.profit,(select jsonb_agg(jsonb_build_array(i.product_id,i.qty,i.price,i.cost,i.cost_basis) order by i.id) from public.transaction_items i where i.transaction_id=t.id) items from public.transactions t where t.id="+id+") x");
 const checkedValue=69099.13;
 async function configure(enabled){const s=await state('admin');await rpc('admin','solar_wholesale_pricing',{action:'configure',request_id:randomUUID(),payload:{enabled,mode:'selected',userIds:[seller,hidden],expectedRevision:s.revision}});}
 async function rule(id,minPrice,enabled){const p=await policy('admin',id);await rpc('admin','solar_wholesale_pricing',{action:'save',request_id:randomUUID(),payload:{items:[{productId:id,minPrice,enabled,expectedRevision:p.revision}]}});}
 const first=await policy(seller,item);
 assert.equal(first.floorSource,'cost');assert.equal(Number(first.effectiveMinPrice),146295.5);assert.ok(first.floorToken);
 await rule(item,325000,false);
 const stored=await policy(seller,item);
 assert.equal(Number(stored.effectiveMinPrice),146295.5);assert.equal(stored.enabled,false);
 assert.equal(Number((await policy('admin',item)).minPrice),325000,'unchecked manual amount was lost');
 await rule(custom,checkedValue,true);
 assert.equal(Number((await policy(seller,custom)).effectiveMinPrice),checkedValue);
 assert.equal(Number((await policy(hidden,custom)).effectiveMinPrice),checkedValue,'personal users must see checked floors');
 const personal=await policy(hidden,item);
 assert.equal(personal.floorSource,'cost');assert.equal(personal.effectiveMinPrice,null);assert.equal(personal.cost,null);assert.ok(personal.floorToken);
 const catalog=await rpc(hidden,'solar_inventory',{action:'catalog'});
 const ordinaryItem=catalog.find(p=>p.id===item);assert.equal(ordinaryItem.cost,null);assert.ok(!Object.hasOwn(ordinaryItem,'cost_basis'));
 await rpc(hidden,'solar_wholesale_pricing',{action:'state',payload:{invoiceId:legacy.id,saleMaterialPrices:true}},403);
 const personalInvoice=product(await state(hidden,{saleMaterialPrices:true}),item);
 assert.equal(personalInvoice.effectiveMinPrice,146295.5);assert.equal(personalInvoice.cost,null);
 const blockedFingerprint=fingerprint();
 await invoice(seller,sale(item,146295.49),422);
 const secret=await invoice(hidden,sale(item,146295.49,1),422);
 assert.ok(!JSON.stringify(secret).replaceAll(',','').includes('146295'),'restricted error disclosed cost');
 assert.equal(fingerprint(),blockedFingerprint,'rejected sales changed the books');
 await invoice(seller,sale(custom,checkedValue-.01),422);await invoice(seller,sale(custom,checkedValue));
 const accepted=await invoice(seller,{...sale(item,146295.5),wholesaleFloorTokens:{[item]:stored.floorToken}});
 const personalSale=await invoice(hidden,{...sale(item,146295.5,1),wholesaleFloorTokens:{[item]:personal.floorToken}});
 assert.ok(personalSale.id);
 const originalAgreed=totals(legacy.id),before=totals(accepted.id);
 await rate(1600);
 const updated=await policy(seller,item);
 assert.equal(Number(updated.effectiveMinPrice),151295.5);assert.notEqual(updated.floorToken,stored.floorToken);
 assert.equal(Number((await policy(seller,custom)).effectiveMinPrice),checkedValue);
 await invoice(seller,{...sale(item,160000),wholesaleFloorTokens:{[item]:stored.floorToken}},409);
 await invoice(seller,sale(item,150000),422);
 const replay=await invoice(seller,sale(item,145000),200,legacyNonce);
 assert.equal(Number(replay.id),Number(legacy.id));assert.equal(originalAgreed,totals(legacy.id));
 const row=JSON.parse(sql('select jsonb_build_object(\'revision\',pricing_revision,\'warehouse\',warehouse_id) from public.transactions where id='+legacy.id));
 const edit={...sale(item,145000),invoiceId:legacy.id,expectedRevision:row.revision,warehouseId:row.warehouse,notes:'تصحيح وصف سابق'};
 await invoice(seller,edit);assert.equal(originalAgreed,totals(legacy.id));
 edit.expectedRevision=Number(sql('select pricing_revision from public.transactions where id='+legacy.id));
 await invoice(seller,{...edit,items:[{id:item,qty:2,price:145000}]},422);
 assert.equal(before,totals(accepted.id),'repricing touched a posted deal');
 await invoice(outside,sale(item,100000,2));await configure(false);await invoice(seller,sale(item,100000));await configure(true);
 // Replacing only the purchase price through the reviewed correction path affects its current floor.
 const extra=f.sample+10;
 sql("insert into public.products(id,code,name,qty,cost)values("+extra+",'FIX-"+extra+"','مادة تصحيح الكلفة',0,0)");
 const body={kind:'purchase',mode:'credit',warehouseId:1,partyId:f.supplier,party:f.vendorName,sourceCurrency:'USD',cashCurrency:'IQD',marketRate:1600,exchangeRate:1600,accountRevision:0,items:[{id:extra,qty:5,price:75}]};
 const purchase=await invoice('admin',body);
 assert.equal(Number((await policy(seller,extra)).effectiveMinPrice),120000);
 const corrected={...body,invoiceId:purchase.id,expectedRevision:Number(sql('select pricing_revision from public.transactions where id='+purchase.id)),items:[{id:extra,qty:5,price:80}]};
 const review=await rpc('admin','solar_purchase_correction_preview',{payload:corrected});
 assert.equal(review.canApply,true);await invoice('admin',{...corrected,purchaseCorrectionToken:review.token});
 assert.equal(Number((await policy(seller,extra)).effectiveMinPrice),128000);
 await invoice(seller,sale(extra,127999.99),422);await invoice(seller,sale(extra,128000));
 assert.equal(before,totals(accepted.id));assert.equal(originalAgreed,totals(legacy.id));
 const {page}=await h.open(seller,'/?section=sale');
 await page.getByRole('textbox',{name:'البحث عن مادة',exact:true}).fill(productName);
 await page.getByRole('button',{name:'إضافة '+productName,exact:true}).click();
 const field=page.getByLabel('سعر المادة — '+productName,{exact:true});
 const show=page.getByTestId('wholesale-minimum-'+item);
 await show.waitFor();assert.ok((await show.innerText()).replaceAll(',','').includes('151295.5'));
 assert.equal(Number((await field.inputValue()).replaceAll(',','')),151295.5);
 await field.fill('151295.49');assert.equal(await field.getAttribute('aria-invalid'),'true');
 await field.fill('151295.50');assert.notEqual(await field.getAttribute('aria-invalid'),'true');await h.layout(page,'visible-floor',show);
 const {page:personalPage}=await h.open(hidden,'/?section=sale');
 await addMaterial(personalPage,productName);
 await displayedPrice(personalPage,'approved-material-price-'+item,151295.5);
 assert.equal(await fieldPrice(personalPage,productName),151295.5);
 await addMaterial(personalPage,f.customName);
 await displayedPrice(personalPage,'approved-material-price-'+custom,checkedValue);
 assert.ok(!(await personalPage.locator('.invoiceWorkspace').innerText()).replaceAll(',','').includes('72000'));
 await h.layout(personalPage,'personal-sale-material-price',personalPage.getByTestId('approved-material-price-'+item));
 await configure(false);
 await personalPage.reload();await addMaterial(personalPage,productName);
 await displayedPrice(personalPage,'approved-material-price-'+item,151295.5);
 assert.equal(await fieldPrice(personalPage,productName),null,'Free price is entered by seller');
 await configure(true);
 await systemCoverage(h,f,151295.5,checkedValue);
 h.checks.accounting={from:146295.5,to:151295.5,fixed:checkedValue,corrected:128000,scoped:true,legacyNotesUnchanged:true,replayUnchanged:true,protectedEmployee:true};
}
async function systemCoverage(h,f,mixedUnit,customUnit){
 const {seller,hidden,item,custom,productName,customName,sample}=f;
 const {engineer,systemName,systemCustomer:customer}=f;
 const status=await rpc('admin','solar_operation_status',{});
 await rpc('admin','solar_operation_control',{request_id:randomUUID(),payload:{kind:'system_pricing',freePricing:false,markupPercent:15,expectedRevision:status.revision}});
 const quote=(who,invoiceId=null)=>rpc(who,'solar_system_material_prices',{product_ids:[item,custom],invoice_id:invoiceId});
 const row=(q,id)=>q.items.find(p=>Number(p.productId)===id);
 const prices=await quote(seller),privatePrices=await quote(hidden);
 assert.equal(Number(row(prices,item).materialPrice),mixedUnit);assert.equal(Number(row(prices,custom).materialPrice),customUnit);
 assert.equal(row(privatePrices,item).materialPrice,mixedUnit);assert.equal(row(privatePrices,item).priceHidden,false);
 const priorPrivate=await quote(hidden,f.priorPersonalSystem);
 assert.equal(row(priorPrivate,item).materialPrice,null);assert.equal(row(priorPrivate,item).priceHidden,true);
 await rpc(hidden,'solar_system_material_prices',{product_ids:[item],invoice_id:f.priorSystem},403);
 assert.equal(Number(row(privatePrices,custom).materialPrice),customUnit);
 const old=await quote(seller,f.priorSystem);
 assert.equal(Number(row(old,item).materialPrice),146295.5);assert.equal(Number(row(old,custom).materialPrice),72000);
 assert.equal(Number((await rpc(seller,'solar_invoice_save',f.priorSystemRequest)).id),Number(f.priorSystem));
 const min=Math.ceil(Math.round((mixedUnit+customUnit)*100)*115/100)/100;
 const base={kind:'system',mode:'credit',warehouseId:1,partyId:customer,party:systemName,installerId:engineer,customerAddress:'عنوان محلي',expenses:0,items:[{id:item,qty:1,price:0},{id:custom,qty:1,price:0}]};
 const save=(body,code=200,request_id=randomUUID())=>rpc(seller,'solar_invoice_save',{request_id,payload:body},code);
 await save({...base,total:min-.01},422);
 const restrictedFailure=await rpc(hidden,'solar_invoice_save',{request_id:randomUUID(),payload:{...base,total:min-.01,partyId:customer+1,party:systemName+' خاص'}},422);
 const err=JSON.stringify(restrictedFailure).replaceAll(',','');assert.ok(!err.includes(String(min))&&!err.includes(String(mixedUnit)),'hidden system validation disclosed the auto floor or derived total');
 const tokens=Object.fromEntries(prices.items.map(p=>[p.productId,p.priceToken]));
 assert.ok(Object.values(tokens).every(Boolean));
 const request_id=randomUUID(),body={...base,total:min,systemMaterialPriceTokens:tokens},saved=await save(body,200,request_id);
 const id=Number(saved.id),frozen=await quote(seller,id);
 assert.equal(Number(row(frozen,item).materialPrice),mixedUnit);assert.equal(Number(row(frozen,custom).materialPrice),customUnit);
 const accounting=sql('select jsonb_build_array(t.total,t.cost,t.profit,items) from public.transactions t cross join lateral(select jsonb_agg(jsonb_build_array(i.product_id,i.qty,i.cost) order by i.id) items from public.transaction_items i where i.transaction_id=t.id) i where t.id='+id);
 const trueBook=Number(sql('select cost from public.transactions where id='+id));assert.notEqual(trueBook,mixedUnit+customUnit,'material pricing changed company valuation');
 await rate(1700);
 await save({...base,total:min+50000,systemMaterialPriceTokens:tokens},409);
 const later=await quote(seller);assert.equal(Number(row(later,item).materialPrice),mixedUnit+5000);
 assert.equal(Number(row(await quote(seller,id),item).materialPrice),mixedUnit);
 assert.equal(Number((await save(body,200,request_id)).id),id);
 const {page}=await h.open(seller,'/?section=system');
 for(const [name,id,amount] of [[productName,item,mixedUnit+5000],[customName,custom,customUnit]]){
  await page.getByRole('textbox',{name:'البحث عن مادة',exact:true}).fill(name);await page.getByRole('button',{name:'إضافة '+name,exact:true}).click();
  const price=page.getByTestId('system-material-price-'+id);await price.waitFor();await page.waitForFunction(({id,amount})=>(document.querySelector('[data-testid="system-material-price-'+id+'"]')?.textContent||'').replaceAll(',','').includes(String(amount)),{id,amount});
 }
 await h.layout(page,'new-system-material-prices',page.getByTestId('system-material-price-'+item));
 await page.goto(process.env.SOLAR_APP_URL+'/?section=salesHistory');await page.getByLabel('بحث الوصل أو الزبون').fill(systemName);await page.getByRole('button',{name:'بحث / تحديث',exact:true}).click();
 const number=Number(sql('select receipt_no from public.transactions where id='+id));
 const card=page.getByRole('article',{name:'بيع منظومة رقم '+number,exact:true});await card.getByRole('button',{name:'تعديل الفاتورة',exact:true}).click();
 const editor=page.getByRole('region',{name:'تعديل فاتورة بيع منظومة',exact:true});await editor.getByTestId('system-material-price-'+item).waitFor();
 await page.waitForFunction(({id,amount})=>(document.querySelector('[data-testid="system-material-price-'+id+'"]')?.textContent||'').replaceAll(',','').includes(String(amount)),{id:item,amount:mixedUnit});
 await h.layout(page,'existing-system-material-prices',editor.getByTestId('system-material-price-'+item));
 const unchanged=sql('select jsonb_build_array(t.total,t.cost,t.profit,items) from public.transactions t cross join lateral(select jsonb_agg(jsonb_build_array(i.product_id,i.qty,i.cost) order by i.id) items from public.transaction_items i where i.transaction_id=t.id) i where t.id='+id);assert.equal(unchanged,accounting);
 const priceInput=editor.getByLabel('تعديل سعر المنظومة',{exact:true});
 const liveMinimum=Math.ceil(Math.round((mixedUnit+5000+customUnit)*100)*115/100)/100;
 await editor.getByRole('button',{name:'استخدام الحد الأدنى الحالي للمنظومة',exact:true}).click();
 await page.waitForFunction(amount=>Number((document.querySelector('[aria-label="تعديل سعر المنظومة"]')?.value||'').replaceAll(',',''))===amount,liveMinimum);
 await priceInput.fill('325000');
 await page.waitForFunction(({id,amount})=>(document.querySelector('[data-testid="system-material-price-'+id+'"]')?.textContent||'').replaceAll(',','').includes(String(amount)),{id:item,amount:mixedUnit+5000});
 const savedEdit=page.waitForResponse(r=>r.url().endsWith('/rpc/solar_invoice_save')&&r.request().method()==='POST');
 await editor.getByRole('button',{name:'حفظ التعديل',exact:true}).click();assert.equal((await savedEdit).status(),200);
 assert.equal(Number(row(await quote(seller,id),item).materialPrice),mixedUnit+5000,'economic edit kept old material prices');
 assert.equal(Number(sql('select total from public.transactions where id='+id)),325000);
 assert.equal(Number(row(await quote(seller,f.priorSystem),item).materialPrice),146295.5);
 await personalMaterialCases(h,f,customUnit);
 h.checks.system={customUnit,mixedUnit,afterFx:mixedUnit+5000,minimum:min,oneClickCurrentMinimum:liveMinimum,trueBook,replayAndOriginalPriceFrozen:true};
}
async function addMaterial(page,name){
 await page.getByRole('textbox',{name:'البحث عن مادة',exact:true}).fill(name);
 await page.getByRole('button',{name:'إضافة '+name,exact:true}).click();
}
async function displayedPrice(page,testId,amount){
 await page.waitForFunction(({testId,amount})=>{
  const badge=document.querySelector('[data-testid="'+testId+'"]');
  const digits=badge?.textContent.replaceAll(',','').match(/[0-9]+(?:\.[0-9]+)?/);
  return digits&&Number(digits[0])===amount;
 },{testId,amount});
}
async function fieldPrice(page,name){
 const input=await page.getByLabel('سعر المادة — '+name,{exact:true}).inputValue();
 return input===''?null:Number(input.replaceAll(',',''));
}
async function personalMaterialCases(h,f,manual){
 const fraction=f.sample+51,zero=f.sample+52;
 const fractionName='مادة كسرية '+fraction,zeroName='مادة مجانية '+zero;
 sql("insert into public.products(id,code,name,qty,cost,cost_basis) values ("+fraction+",'F-"+fraction+"','"+fractionName+"',25,901,'{\"currencyComponents\":{\"iqd\":1.001234,\"usd\":0.1}}'),("+zero+",'Z-"+zero+"','"+zeroName+"',25,0,'{}')");
 const ids=[fraction,zero,f.custom];
 const current=async()=>rpc(f.hidden,'solar_system_material_prices',{product_ids:ids,invoice_id:null});
 const prices=result=>Object.fromEntries(result.items.map(p=>[p.productId,p.materialPrice]));
 assert.deepEqual(prices(await current()),{[fraction]:171.001234,[zero]:0,[f.custom]:manual});
 for(const user of ['warehouse','installer']){
  await rpc(user,'solar_system_material_prices',{product_ids:ids,invoice_id:null},403);
  await rpc(user,'solar_wholesale_pricing',{action:'state',payload:{saleMaterialPrices:true}},403);
 }
 const {page}=await h.open(f.hidden,'/?section=sale');await addMaterial(page,fractionName);await addMaterial(page,zeroName);
 await displayedPrice(page,'approved-material-price-'+fraction,171.001234);
 await displayedPrice(page,'approved-material-price-'+zero,0);
 assert.equal(await fieldPrice(page,fractionName),171.01);
 assert.equal(await fieldPrice(page,zeroName),0);
 await rate(1500);await page.evaluate(()=>window.dispatchEvent(new Event('focus')));
 await displayedPrice(page,'approved-material-price-'+fraction,151.001234);
 assert.equal(await fieldPrice(page,fractionName),151.01);
 const system=(await h.open(f.hidden,'/?section=system')).page;
 for(const [name,id,expected] of [[fractionName,fraction,151.001234],[zeroName,zero,0],[f.customName,f.custom,manual]]){
  await addMaterial(system,name);await displayedPrice(system,'system-material-price-'+id,expected);
 }
 await h.layout(system,'personal-system-mandatory',system.getByTestId('system-material-price-'+fraction));
 const status=await rpc('admin','solar_operation_status',{});
 await rpc('admin','solar_operation_control',{request_id:randomUUID(),payload:{kind:'system_pricing',freePricing:true,markupPercent:15,expectedRevision:status.revision}});
 await system.reload();await addMaterial(system,fractionName);await addMaterial(system,f.customName);
 await displayedPrice(system,'system-material-price-'+fraction,151.001234);
 await displayedPrice(system,'system-material-price-'+f.custom,manual);
 assert.equal(await system.getByTestId('system-minimum-price').count(),0);
 await h.layout(system,'personal-system-free',system.getByTestId('system-material-price-'+fraction));
 h.checks.personalInvoicePrices={manual,originalExact:171.001234,afterFx:151.001234,roundedDefault:151.01,zero:0,restrictedRolesDenied:true,previousReceiptStillMasked:true};
}
if(process.argv.includes('--seed-legacy'))await seed();
else{
 const harness=await createHarness('automatic-wholesale-floor');
 try{await run(harness);await harness.finish();console.log('PASS mixed-cost sale, safe pricing, scope/replay and supplier correction across desktop and mobile');}
 catch(error){await harness.fail(error);throw error;}finally{await harness.close();}
}
