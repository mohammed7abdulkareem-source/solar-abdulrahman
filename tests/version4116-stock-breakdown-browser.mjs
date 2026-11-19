// Read-only browser regression. Load version4116-stock-breakdown-browser-fixture.sql
// into a disposable V415 material-picker fixture with the stock breakdown migration.
import assert from 'node:assert/strict';
process.env.SOLAR_FIXTURE_DB||='solar_v4116_stock_browser';
process.env.SOLAR_FIXTURE_API||='http://127.0.0.1:3232';
process.env.SOLAR_APP_URL||='http://127.0.0.1:3233';
process.env.SOLAR_ARTIFACT_DIR||='/workspace/solar-review/v4116/stock-breakdown-browser';
const {createHarness,rpc,fingerprint}=await import('./version4-browser-support.mjs');

const admin='00000000-0000-0000-0000-000000415501';
const staff='00000000-0000-0000-0000-000000415503';
const saleOnly='00000000-0000-0000-0000-000000415504';
const a=-411670,b=-411671,zero=-411672,search='V4116-STOCK';
const stock=(actor,payload,status=200)=>rpc(actor,'solar_inventory',{action:'stock',payload},status);
const h=await createHarness('stock-breakdown');
const view=p=>p.locator('.inventoryWorkspace');
const radio=(p,name)=>view(p).getByRole('radio',{name,exact:true});
const searchField=p=>view(p).getByLabel('بحث أرصدة المخازن',{exact:true});
const select=p=>view(p).getByLabel('عرض رصيد المخزن',{exact:true});
const zeroToggle=p=>view(p).getByLabel('إخفاء الأرصدة الصفرية',{exact:true});
const costToggle=p=>view(p).getByLabel('إظهار الكلفة',{exact:true});
const row=(root,id)=>root.locator('article[data-stock-product="'+id+'"]');
const group=(p,id)=>view(p).locator('[data-stock-warehouse="'+id+'"]');
const actions=p=>view(p).locator('.inventoryBalanceExport .reportExport, .inventoryBalanceExport.reportExport');
const n=text=>Number(text.replaceAll(',','').replaceAll('−','-').trim());
async function metric(p,key){
 return n(await view(p).locator('[data-stock-metric="'+key+'"] bdi').innerText());
}
async function metrics(p,products,available,reserved){
 assert.deepEqual(await Promise.all(['products','available','reserved'].map(key=>metric(p,key))),[products,available,reserved]);
}
async function assertNoStaleData(p){
 assert.equal(await view(p).locator('article[data-stock-product]').count(),0);
 assert.equal(await actions(p).locator('button:not(:disabled)').count(),0);
}
let release;
try{
 const original=fingerprint();
 const adminStock=await stock(admin,{byWarehouse:true});
 const primary=adminStock.warehouses.find(w=>w.primary).id;
 const secondary=adminStock.warehouseBalances.find(v=>v.productId===a&&v.warehouseId!==primary).warehouseId;
 const primaryName=adminStock.warehouses.find(w=>w.id===primary).name;
 const secondaryName=adminStock.warehouses.find(w=>w.id===secondary).name;
 const relevant=adminStock.warehouseBalances.filter(r=>[a,b,zero].includes(r.productId));
 assert.deepEqual(relevant.map(r=>[r.warehouseId,r.productId,r.qty,r.reservedQty,r.bookQty]).sort(),
  [[primary,a,3.125,2,5.125],[primary,b,0,4,4],[secondary,a,4,0,4]].sort());
 for(const balance of relevant)assert.deepEqual(Object.keys(balance).sort(),['bookQty','productId','qty','reservedQty','warehouseId']);
 for(const product of adminStock.products.filter(p=>[a,b,zero].includes(p.id))){
  const sum=(key)=>relevant.filter(r=>r.productId===product.id).reduce((total,r)=>total+r[key],0);
  for(const key of ['qty','reservedQty','bookQty'])assert.equal(sum(key),product[key]);
 }
 const visible=await stock(staff,{byWarehouse:true});
 assert.deepEqual(visible.warehouses.map(w=>w.id),[primary]);assert.ok(visible.warehouseBalances.every(r=>r.warehouseId===primary));
 assert.equal(visible.showCost,false);assert.ok(visible.products.every(p=>p.cost==null));
 await stock(staff,{warehouseId:secondary,byWarehouse:true},403);await stock(saleOnly,{byWarehouse:true},403);
 assert.equal(Object.hasOwn(await stock(admin,{}),'warehouseBalances'),false);
 const {page:p,ctx}=await h.open(admin,'/?section=stock');
 await radio(p,'المجموع').waitFor();assert.equal(await radio(p,'المجموع').isChecked(),true);
 await searchField(p).fill(search);
 await row(view(p),a).waitFor();await metrics(p,2,7.125,6);
 assert.equal(await row(view(p),a).count(),1);assert.equal(await row(view(p),zero).count(),0);
 assert.equal(await group(p,primary).count(),0);
 await costToggle(p).check();assert.equal(await metric(p,'value'),9.125*87654+4*12345);
 assert.equal(await zeroToggle(p).isChecked(),true);
 const aggregateHtml=await h.report(p,ctx,actions(p),'aggregate-valued');
 assert.ok(aggregateHtml.includes('87,654'));assert.ok(aggregateHtml.includes('V4116-STOCK-B'));assert.ok(!aggregateHtml.includes('V4116-STOCK-Z'));
 await costToggle(p).uncheck();
 await radio(p,'حسب المخزن').check();await row(group(p,primary),b).waitFor();await metrics(p,2,7.125,6);
 assert.equal(await row(group(p,secondary),a).count(),1);assert.equal(await row(group(p,secondary),b).count(),0);
 assert.equal(await row(view(p),a).count(),2);assert.equal(await row(view(p),zero).count(),0);
 await h.layout(p,'stock-by-warehouse',row(group(p,primary),a));
 const groupedHtml=await h.report(p,ctx,actions(p),'scoped-quantities');
 const report=await p.evaluate(html=>{
  const doc=new DOMParser().parseFromString(html,'text/html');
  return [...doc.querySelectorAll('table')].map(table=>({
   warehouse:table.tHead.rows[0].textContent,
   rows:[...table.tBodies[0].rows].filter(row=>row.cells.length>1).map(row=>[row.cells[0].textContent,row.cells[2].textContent,row.cells[3].textContent])
  }));
 },groupedHtml);
 assert.deepEqual(report.find(r=>r.warehouse===primaryName).rows.sort(),[['V4116-STOCK-A','3.125','2'],['V4116-STOCK-B','0','4']]);
 assert.deepEqual(report.find(r=>r.warehouse===secondaryName).rows,[['V4116-STOCK-A','4','0']]);
 assert.doesNotMatch(groupedHtml,/87,654|12,345|77,777/);
 await zeroToggle(p).uncheck();
 assert.equal(await row(view(p),zero).count(),adminStock.warehouses.length);await metrics(p,3,7.125,6);
 await searchField(p).fill('STOCK-Z');assert.equal(await row(view(p),a).count(),0);await metrics(p,1,0,0);
 await zeroToggle(p).check();await metrics(p,0,0,0);
 await searchField(p).fill(search);
 const loaded=new Promise(resolve=>{
  const until=new Promise(done=>{release=done;});
  h.setIntercept(async({route,call,response})=>{
   if(call.body?.action!=='stock'||call.body.payload.warehouseId!==secondary||call.body.payload.byWarehouse!==true)return false;
   resolve();await until;await route.fulfill({response});return true;
  });
 });
 await select(p).selectOption(String(secondary));
 const missed=setTimeout(()=>release?.(),12000);
 try{await Promise.race([loaded,new Promise((_,reject)=>{const timer=setTimeout(()=>reject(new Error('Scoped stock was not requested')),10000);timer.unref();})]);}finally{clearTimeout(missed);}
 await assertNoStaleData(p);
 await select(p).selectOption(String(primary));await row(group(p,primary),a).waitFor();await metrics(p,2,3.125,6);
 release();release=null;h.setIntercept(null);
 await row(group(p,primary),a).waitFor();assert.equal(await group(p,secondary).count(),0);
 h.setIntercept(async({route,call})=>{
  if(call.body?.action!=='stock'||call.body.payload.warehouseId!==secondary)return false;
  await route.fulfill({status:503,json:{code:'PGRST000',message:'اختبار تعذّر تحميل الرصيد'}});return true;
 });
 await select(p).selectOption(String(secondary));await view(p).getByRole('alert').filter({hasText:'اختبار تعذّر تحميل الرصيد'}).first().waitFor();
 await assertNoStaleData(p);h.setIntercept(null);
 await view(p).getByRole('button',{name:'تحديث أرصدة المخازن'}).click();await row(group(p,secondary),a).waitFor();
 await metrics(p,1,4,0);assert.equal(await group(p,primary).count(),0);
 const employee=await h.open(staff,'/?section=stock');await searchField(employee.page).fill(search);
 await radio(employee.page,'حسب المخزن').check();await row(group(employee.page,primary),a).waitFor();await metrics(employee.page,2,3.125,6);
 assert.equal(await costToggle(employee.page).count(),0);assert.equal(await group(employee.page,secondary).count(),0);
 assert.equal(await select(employee.page).locator('option[value="'+secondary+'"]').count(),0);
 const ownHtml=await h.report(employee.page,employee.ctx,actions(employee.page),'warehouse-employee');
 assert.ok(ownHtml.includes(primaryName));assert.ok(!ownHtml.includes(secondaryName));assert.doesNotMatch(ownHtml,/87,654|12,345|77,777/);
 assert.equal(fingerprint(),original);Object.assign(h.checks,{scopeAndExactFractions:true,reservedOnlyAndTrueZero:true,matchingDocuments:true,confirmedScopeAcrossLateReplyAndRetry:true,financialAndStockFingerprintUnchanged:true});
 await h.finish();console.log('PASS aggregate and per-warehouse stock, quantities/value, PDFs, scopes, responsive layouts, withheld and failed replies.');
}catch(err){await h.fail(err);throw err;}finally{release?.();await h.close();}
