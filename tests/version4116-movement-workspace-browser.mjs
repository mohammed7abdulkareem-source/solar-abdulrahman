// Three distinct reports rendered by the installed app against isolated PostgREST.
// Requires version4116-movement-workspace-browser-fixture.sql and the V415 roles.
import assert from 'node:assert/strict';

process.env.SOLAR_FIXTURE_DB ||= 'solar_v4116_movement_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3228';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3227';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4116/movement-browser';
const {createHarness,fingerprint,rpc}=await import('./version4-browser-support.mjs');

const admin='00000000-0000-0000-0000-000000415501';
const seller='00000000-0000-0000-0000-000000415502';
const warehouse='00000000-0000-0000-0000-000000415503';
const stranger='00000000-0000-0000-0000-000000415504';
const installer='00000000-0000-0000-0000-000000415506';
const A=-411601,B=-411602,codeA='V4116-TWIN-A',codeB='V4116-TWIN-B';
const sharedProduct='انفيرتر توأم 15KW',sharedCustomer='زبون كشف التوأم';
const keyA='customer:-411601',keyB='customer:-411602';
const inventory=(actor,action,payload,status=200)=>rpc(actor,'solar_inventory',{action,payload},status);
const h=await createHarness('movement-workspace');
const which=(page,mode)=>page.locator('[data-movement-mode="'+mode+'"]');
const back=page=>page.getByRole('button',{name:'تغيير نوع الكشف',exact:true}).click();
const edit=page=>page.getByRole('button',{name:'تعديل معايير الكشف',exact:true}).click();
const submit=page=>page.getByRole('button',{name:'عرض الكشف',exact:true});
const material=page=>page.getByRole('combobox',{name:'البحث عن مادة للحركة',exact:true});
const customer=page=>page.getByRole('combobox',{name:'بحث عميل الكشف',exact:true});
const exactRows=page=>page.getByTestId('material-movement-table').locator('tbody tr[data-movement-id]');
const resultRows=page=>page.locator('.movementEntry[data-movement-id]');
const actions=page=>page.locator('[data-active-movement-mode] .reportExport');
const number=value=>Number(value.replaceAll(',','').replaceAll('−','-'));
const ids=rows=>rows.map(row=>row.id);
async function chooseMaterial(page,code){
 await material(page).fill(code);
 await page.getByRole('option',{name:new RegExp(code)}).click();
}
async function chooseCustomer(page,id){
 await customer(page).fill(sharedCustomer);
 await page.getByRole('option',{name:new RegExp(String(id)+'$')}).click();
}
async function assertClear(page){
 assert.equal(await page.locator('.mlCompactTable,.movementEntry,.movementTotals,.mlCurrentMetric').count(),0);
 assert.equal(await actions(page).count(),0);
}
async function rowsMatch(page,expected,{exact=false}={}){
 const locator=exact?exactRows(page):resultRows(page);
 const selector=exact?'[data-testid="material-movement-table"] tbody tr[data-movement-id]':'.movementEntry[data-movement-id]';
 await page.waitForFunction(({selector,n})=>document.querySelectorAll(selector).length===n,{selector,n:expected.length});
 const rows=await locator.evaluateAll(nodes=>nodes.map(node=>({
  id:node.dataset.movementId,product:node.dataset.productId,
  balance:node.querySelector('[data-testid="material-row-balance"],.movementBalance b').textContent,
  quantities:[...node.querySelectorAll('[data-testid="material-row-quantity"],.movementAmount:not(.movementBalance) b')].map(el=>el.textContent)
 })));
 assert.deepEqual(rows.map(row=>row.id),ids(expected));
 for(const [i,row] of rows.entries()){
  const r=expected[i];assert.equal(number(row.balance),r.balance,'stock after '+r.id);
  if(!exact)assert.equal(Number(row.product),r.productId);
  assert.deepEqual(row.quantities.map(number),exact?[r.inQty-r.outQty]:[r.inQty,r.outQty]);
 }
}
async function documentMatches(page,ctx,rows,label){
 const html=await h.report(page,ctx,actions(page),label);
 const rendered=await page.evaluate(source=>{
  const doc=new DOMParser().parseFromString(source,'text/html');
  return [...doc.querySelectorAll('tbody tr[data-movement-id]')].map(row=>({id:row.dataset.movementId,balance:row.cells[row.cells.length-1].textContent}));
 },html);
 assert.deepEqual(rendered.map(r=>r.id),ids(rows),'PDF contains exactly the applied report, including other pages');
 assert.deepEqual(rendered.map(r=>number(r.balance)),rows.map(r=>r.balance),'PDF matches stock after each movement');
 return html;
}
let release;
try{
 const original=fingerprint();
 const [ledgerA,ledgerB,directory,one,two,all]=await Promise.all([
  inventory(admin,'material_report',{productId:A}),inventory(admin,'material_report',{productId:B}),
  inventory(admin,'movement_customers',{productId:A}),
  inventory(admin,'movements',{productId:A,customerKey:keyA}),inventory(admin,'movements',{productId:A,customerKey:keyB}),
  inventory(admin,'movements',{})
 ]);
 assert.equal(ledgerA.product.name,ledgerB.product.name);
 assert.deepEqual(ledgerA.rows.map(r=>r.balance),[28,23,22]);assert.deepEqual(ledgerB.rows.map(r=>r.balance),[37]);
 assert.deepEqual(new Set(directory.map(r=>r.key)),new Set([keyA,keyB]));
 assert.deepEqual(directory.map(r=>r.name),[sharedCustomer,sharedCustomer]);
 assert.deepEqual(one.map(r=>r.balance),[28]);assert.deepEqual(two.map(r=>r.balance),[23]);
 const twins=all.filter(r=>[A,B].includes(r.productId));assert.equal(twins.length,4);
 assert.ok(all.length>30,'general PDF must include multiple pages');
 const {page,ctx}=await h.open(admin,'/');
 await page.locator('.appMobileBar').getByRole('button',{name:'الأقسام'}).click();
 const sectionMenu=page.getByRole('dialog',{name:'جميع الأقسام'});
 await sectionMenu.getByRole('textbox',{name:'البحث عن قسم'}).fill('حركة المواد');
 await sectionMenu.getByRole('link',{name:/حركة المواد/}).click();
 await which(page,'ledger').waitFor();
 assert.deepEqual(await page.locator('[data-movement-mode]').evaluateAll(els=>els.map(el=>el.dataset.movementMode)),['ledger','customer','materials']);
 assert.equal(await page.locator('[data-active-movement-mode] form').count(),0);
 const reportsSent=()=>h.calls.filter(c=>['material_report','movement_customers','movements'].includes(c.body?.action)).length;
 assert.equal(reportsSent(),0);await assertClear(page);
 await h.layout(page,'movement-report-selection',which(page,'ledger'));
 await which(page,'ledger').focus();await which(page,'ledger').press('Enter');
 await material(page).fill(sharedProduct);
 for(const code of [codeA,codeB])await page.getByRole('option',{name:new RegExp(code)}).waitFor();
 await material(page).press('Enter');assert.equal(reportsSent(),0);await assertClear(page);
 await page.getByRole('option',{name:new RegExp(codeA)}).click();await rowsMatch(page,ledgerA.rows,{exact:true});
 assert.equal(number(await page.getByTestId('material-current-qty').innerText()),22);
 assert.equal(await material(page).count(),0);await exactRows(page).first().getByRole('button').click();
 await page.locator('[data-movement-detail="'+ledgerA.rows[0].id+'"]').waitFor();
 await h.layout(page,'ledger-after-each-movement',page.locator('.mlCompactTableScroll'));
 const materialHtml=await documentMatches(page,ctx,ledgerA.rows,'one-material');
 assert.ok(materialHtml.includes(codeA));assert.ok(!materialHtml.includes(codeB));
 await edit(page);await assertClear(page);await chooseMaterial(page,codeB);await rowsMatch(page,ledgerB.rows,{exact:true});
 h.checks.sameNamedProductsAndPerMovementStock=true;

 await back(page);await which(page,'customer').click();await assertClear(page);
 assert.ok(await submit(page).isDisabled());await chooseMaterial(page,codeA);
 await customer(page).fill(sharedCustomer);await page.getByRole('option',{name:/-411602$/}).waitFor();
 assert.equal(await page.getByRole('listbox',{name:'نتائج بحث العملاء'}).getByRole('option').count(),2);
 assert.ok(await submit(page).isDisabled(),'ambiguous customer text cannot submit');
 await h.layout(page,'same-name-customer-picker',customer(page));
 await page.getByRole('option',{name:/-411602$/}).click();await submit(page).click();
 await rowsMatch(page,two);assert.equal(await material(page).count(),0);
 let stats=await page.locator('.movementTotals b').allInnerTexts();assert.deepEqual(stats.map(number),[1,5,0]);
 await h.layout(page,'customer-one-material',resultRows(page).first());
 const customerHtml=await documentMatches(page,ctx,two,'one-material-one-customer');
 assert.ok(customerHtml.includes(codeA));assert.ok(customerHtml.includes(sharedCustomer));assert.ok(customerHtml.includes('-411602'));
 await edit(page);await assertClear(page);await chooseCustomer(page,A);await submit(page).click();await rowsMatch(page,one);
 await edit(page);await chooseMaterial(page,codeB);assert.ok(await submit(page).isDisabled(),'changing material clears the prior customer');
 await customer(page).fill(sharedCustomer);await page.getByRole('option',{name:/-411601$/}).waitFor();
 assert.equal(await page.getByRole('option',{name:/-411602$/}).count(),0);
 await page.getByRole('option',{name:/-411601$/}).click();await submit(page).click();await rowsMatch(page,ledgerB.rows);
 await edit(page);await chooseMaterial(page,'V415-B-15');
 await customer(page).fill('زبون بيع الألواح');
 await page.getByRole('option',{name:/زبون بيع الألواح.*-415501/}).click();await submit(page).click();
 const oldRecord=await inventory(admin,'movements',{productId:-415502,customerKey:'customer:-415501'});
 assert.equal(oldRecord.length,1);await rowsMatch(page,oldRecord);
 h.checks.exactCustomerAndProductIncludingUniqueAndAmbiguousLegacyReceipts=true;

 // Delay a confirmed old customer response while opening the company-wide report.
 await edit(page);await chooseMaterial(page,codeA);await chooseCustomer(page,A);
 let started;const waiting=new Promise(resolve=>{started=resolve;});
 const gate=new Promise(resolve=>{release=resolve;});
 h.setIntercept(async({route,call,response})=>{
  if(call.body?.action!=='movements'||call.body.payload.customerKey!==keyA)return false;
  started();await gate;await route.fulfill({response});return true;
 });
 await submit(page).click();
 await Promise.race([waiting,new Promise((_,reject)=>{const timeout=setTimeout(()=>reject(new Error('Customer movement request was not sent')),10000);timeout.unref();})]);
 await assertClear(page);await back(page);await which(page,'materials').click();
 assert.equal(await material(page).count(),0);assert.equal(await customer(page).count(),0);await assertClear(page);
 await submit(page).click();await rowsMatch(page,all.slice(0,30));release();release=null;h.setIntercept(null);
 await rowsMatch(page,all.slice(0,30));stats=await page.locator('.movementTotals b').allInnerTexts();
 assert.deepEqual(stats.map(number),[all.length,all.filter(r=>r.outQty>0).length,all.filter(r=>r.inQty>0).length]);
 const pagination=page.getByRole('navigation',{name:'صفحات الحركات'});await pagination.getByRole('button',{name:'التالي'}).click();
 await rowsMatch(page,all.slice(30,60));await h.layout(page,'general-all-materials',resultRows(page).first());
 const generalHtml=await documentMatches(page,ctx,all,'all-materials-all-pages');
 const footer=await page.evaluate(html=>[...new DOMParser().parseFromString(html,'text/html').querySelectorAll('.warehouseMovementReport tfoot .wmIn bdi,.warehouseMovementReport tfoot .wmOut bdi')].map(e=>e.textContent),generalHtml);
 assert.deepEqual(footer.map(number),[all.filter(r=>r.inQty>0).length,all.filter(r=>r.outQty>0).length]);
 await edit(page);await assertClear(page);await page.getByLabel('بحث المستند أو الطرف').fill(sharedProduct);await submit(page).click();await rowsMatch(page,twins);
 await edit(page);await assertClear(page);const dates=page.getByLabel('من تاريخ',{exact:true});
 await dates.fill('2099-01-10');await page.getByLabel('إلى تاريخ',{exact:true}).fill('2099-01-01');assert.ok(await submit(page).isDisabled());
 await page.getByRole('alert').filter({hasText:'تاريخ النهاية'}).waitFor();
 h.checks.generalIndependentSaldoTotalsAndStaleCustomerResponse=true;

 const sellerOptions=await inventory(seller,'movement_customers',{productId:A});
 assert.deepEqual(sellerOptions.map(r=>r.key),[keyA]);
 assert.deepEqual(await inventory(seller,'movements',{productId:A,customerKey:keyB}),[]);
 assert.deepEqual(await inventory(stranger,'movement_customers',{productId:A}),[]);
 await inventory(warehouse,'movement_customers',{productId:A,warehouseId:2},403);
 await inventory(installer,'movement_customers',{productId:A},403);
 const peer=await h.open(stranger,'/?section=stockMovement');await which(peer.page,'customer').click();await chooseMaterial(peer.page,codeA);
 await peer.page.getByRole('status').filter({hasText:'لا توجد حركات عميل'}).waitFor();
 assert.ok(await submit(peer.page).isDisabled());assert.equal(await customer(peer.page).count(),0);
 await assertClear(peer.page);
 const wh=await h.open(warehouse,'/?section=stockMovement');await which(wh.page,'ledger').click();
 assert.equal(await wh.page.getByLabel('عرض الأسعار المثبتة بالمستند',{exact:true}).count(),0);
 await chooseMaterial(wh.page,codeA);const warehouseLedger=await inventory(warehouse,'material_report',{productId:A});
 await rowsMatch(wh.page,warehouseLedger.rows,{exact:true});assert.equal(await wh.page.getByTestId('material-row-price').count(),0);
 h.checks.userAndWarehouseScopeAndPriceRestrictions=true;
 assert.equal(fingerprint(),original);h.checks.financialStockFingerprintUnchanged=true;
 await h.finish();console.log('PASS three material reports, exact product/customer IDs, running stock, delayed responses, three real PDFs, mobile/desktop and access.');
}catch(error){release?.();await h.fail(error);throw error;}finally{await h.close();}
