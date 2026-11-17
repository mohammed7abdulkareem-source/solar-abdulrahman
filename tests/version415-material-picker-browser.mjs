// V4.1.5: exact material picker → compiled UI → real isolated API/stock → PDFs.
// Every external request is denied or redirected to local PostgREST. Read-only after fixture setup.
import assert from 'node:assert/strict';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v415_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3157';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v415/material-browser';
const {rpc,sql,fingerprint,createHarness}=await import('./version4-browser-support.mjs');
const u={admin:'00000000-0000-0000-0000-000000415501',seller:'00000000-0000-0000-0000-000000415502',warehouse:'00000000-0000-0000-0000-000000415503',other:'00000000-0000-0000-0000-000000415504',quantity:'00000000-0000-0000-0000-000000415505',installer:'00000000-0000-0000-0000-000000415506'};
const A=-415501,B=-415502,Z=-415503,codeA='V415-A-15',codeB='V415-B-15',codeZ='V415-ZERO-15';
const report=(who,productId,filters={},status=200)=>rpc(u[who],'solar_inventory',{action:'material_report',payload:{productId,...filters}},status);
const qty=text=>Number(text.replaceAll(',',''));
const h=await createHarness('material-browser');
const picker=p=>p.getByRole('combobox',{name:'البحث عن مادة للحركة',exact:true});
async function choose(p,code,{touch=false}={}){await picker(p).fill(code);const option=p.getByRole('option',{name:new RegExp(code)});await option.waitFor();if(touch)await option.tap();else await option.click();}
async function loaded(p,code){await p.locator('.mlProduct').filter({hasText:code}).waitFor();await p.getByTestId('material-current-qty').waitFor();}
async function rowsEqual(p,rows){await p.waitForFunction(count=>document.querySelectorAll('.mlMovement').length===count,rows.length);assert.equal(await p.locator('.mlMovement').count(),rows.length);for(const r of rows){const el=p.locator('[data-movement-id="'+r.id+'"]');await el.waitFor();for(const [selector,field]of[['.mlQty.in b','inQty'],['.mlQty.out b','outQty'],['.mlQty.balance b','balance']])assert.equal(qty(await el.locator(selector).innerText()),Number(r[field]),r.id+' '+field);}}
async function noOldReport(p){assert.equal(await p.locator('.mlProduct').count(),0);assert.equal(await p.locator('.mlMovement').count(),0);assert.equal(await p.locator('.mlWorkspace>.reportExport').count(),0);}
let heldRelease;
try{
 const before=fingerprint(),today=sql("select(now()at time zone'Asia/Baghdad')::date::text"),full=await report('admin',A),alternate=await report('admin',B),zero=await report('admin',Z),dated=await report('admin',A,{from:today});
 assert.equal(full.product.id,A);assert.ok(full.rows.length>10);assert.ok(full.rows.every(r=>r.productId===A));assert.equal(full.currentQty,12);assert.equal(alternate.currentQty,1);assert.equal(zero.currentQty,0);assert.ok(zero.rows.length>0);
 for(const r of dated.rows)assert.equal(r.balance,full.rows.find(x=>x.id===r.id).balance);assert.equal(dated.rows.some(r=>r.kind==='stock_adjustment'),false);
 const plainJson=JSON.stringify(full);assert.doesNotMatch(plainJson,/"pricing"|"unitCost"|"cost"/);
 const priced=await report('admin',A,{withPrices:true});assert.ok(priced.rows.some(r=>r.pricing?.unitPrice===2075));assert.ok(priced.rows.some(r=>r.pricing?.unitPrice===3000));assert.ok(priced.rows.some(r=>r.kind==='system'&&r.pricing.kind==='system_total'&&!Object.hasOwn(r.pricing,'unitPrice')));
 const own=await report('seller',A),foreign=await report('other',A),warehouse=await report('warehouse',A);assert.equal(own.scope,'own');assert.ok(own.rows.length>0);for(const row of own.rows){const original=full.rows.find(r=>r.id===row.id);assert.ok(original);assert.equal(row.balance,original.balance);}assert.equal(foreign.rows.length,0);assert.equal(warehouse.canShowPrices,false);assert.ok(warehouse.rows.every(r=>r.warehouseId===1));
 await report('warehouse',A,{withPrices:true},403);await report('warehouse',A,{warehouseId:2},403);await report('quantity',A,{withPrices:true},403);await report('installer',A,{},403);
 h.checks.realApiExactIdentityBalancesPermissions=true;
 const admin=await h.open(u.admin,'/?section=stockMovement'),p=admin.page;
 await picker(p).waitFor();await picker(p).fill('15KW');
 for(const code of[codeA,codeB,codeZ])await p.getByRole('option',{name:new RegExp(code)}).waitFor();
 const requestCount=()=>h.calls.filter(c=>c.body?.action==='material_report').length,initial=requestCount();
 await picker(p).press('Enter');await noOldReport(p);assert.equal(requestCount(),initial,'ambiguous text must not select a material');
 await h.layout(p,'picker-15kw',p.locator('.mmPicker'));
 const options=await p.getByRole('option').allTextContents(),idx=options.findIndex(text=>text.includes(codeA));assert.ok(idx>=0);
 await picker(p).focus();for(let i=0;i<=idx;i++)await picker(p).press('ArrowDown');await picker(p).press('Enter');await loaded(p,codeA);
 await rowsEqual(p,full.rows);assert.equal(await p.locator('[data-selected-product-id="'+A+'"]').count(),1);assert.equal(qty(await p.getByTestId('material-current-qty').innerText()),12);
 const sale=p.locator('.mlMovement').filter({hasText:'زبون بيع الألواح'});assert.ok((await sale.innerText()).includes('مجهز كشف المواد'));assert.ok((await sale.innerText()).includes('مسؤول تجهيز المخزن'));
 await p.locator('.mlMovement').filter({hasText:'مورد كشف المواد'}).waitFor();for(const row of full.rows.filter(r=>['purchase','stock_adjustment'].includes(r.kind))){const text=await p.locator('[data-movement-id="'+row.id+'"]').innerText();assert.ok(!text.includes('بانتظار التجهيز'));assert.ok(!text.includes('مسؤول تجهيز المخزن'));}h.checks.purchaseAndAdjustmentNeverClaimPendingPreparation=true;await p.locator('.mlMovement').filter({hasText:'حجز نقل ملغى'}).waitFor();assert.equal(await p.locator('.mlPrice').count(),0);
 await h.layout(p,'exact-material',p.locator('.mlProduct'));await h.layout(p,'movement-cards',p.locator('.mlMovement').filter({hasText:'زبون بيع الألواح'}));
 const plainHtml=await h.report(p,admin.ctx,p.locator('.mlWorkspace>.reportExport'),'material-plain');
 assert.ok(plainHtml.includes(codeA));assert.ok(!plainHtml.includes(codeB));assert.ok(plainHtml.includes('الرصيد بعد الحركة'));assert.ok(!plainHtml.includes('3,000 د.ع'));assert.ok(!plainHtml.includes('2,075 د.ع'));
 h.checks.keyboardExplicitSelectionAndPlainPdf=true;
 await picker(p).fill('15KW');await noOldReport(p);assert.equal(requestCount(),initial+1,'typing must not request a broad report');
 await p.getByRole('option',{name:new RegExp(codeB)}).tap();await loaded(p,codeB);await rowsEqual(p,alternate.rows);assert.ok(!(await p.locator('.mlProduct').innerText()).includes(codeA));
 await choose(p,codeZ,{touch:true});await loaded(p,codeZ);await rowsEqual(p,zero.rows);assert.equal(qty(await p.getByTestId('material-current-qty').innerText()),0);
 h.checks.touchExactDuplicateAndZeroStockHistory=true;
 // An old successful response must not restore a previous selected material.
 let held=false;const gate=new Promise(resolve=>{heldRelease=resolve;});
 h.setIntercept(async({route,call,response})=>{if(!held&&call.body?.action==='material_report'&&call.body.payload.productId===A){held=true;await gate;await route.fulfill({response});return true;}return false;});
 await choose(p,codeA);await p.waitForFunction(()=>document.querySelector('.mlEmpty[role="status"]')!==null);for(let tries=0;!held&&tries<100;tries++)await new Promise(resolve=>setTimeout(resolve,20));assert.ok(held,'expected delayed local report');
 await choose(p,codeB);await loaded(p,codeB);heldRelease();heldRelease=null;h.setIntercept(null);await p.waitForTimeout(200);await rowsEqual(p,alternate.rows);assert.ok((await p.locator('.mlProduct').innerText()).includes(codeB));
 h.checks.delayedOldResponseDiscarded=true;
 await choose(p,codeA);await loaded(p,codeA);
 await p.getByLabel('بداية حركة المادة',{exact:true}).fill(today);await p.getByRole('button',{name:'عرض حركة المادة',exact:true}).click();await loaded(p,codeA);await rowsEqual(p,dated.rows);
 for(const w of dated.warehouses){const card=p.locator('.mlWarehouseGrid>article').filter({has:p.getByRole('heading',{name:w.name,exact:true})});const parts=await card.locator('div>span').allTextContents();assert.ok(parts.some(t=>t.startsWith('الرصيد قبل أول حركة')&&t.endsWith(w.beforeFirst==null?'—':String(w.beforeFirst))));}
 const direction=p.getByRole('group',{name:'اتجاه حركة المادة',exact:true});await direction.getByRole('button',{name:'خروج',exact:true}).click();await rowsEqual(p,dated.rows.filter(r=>r.outQty>0));
 await direction.getByRole('button',{name:'دخول',exact:true}).click();await rowsEqual(p,dated.rows.filter(r=>r.inQty>0));
 await direction.getByRole('button',{name:'الكل',exact:true}).click();await p.getByLabel('بحث تفاصيل حركة المادة',{exact:true}).fill('مورد كشف دولار');await rowsEqual(p,dated.rows.filter(r=>r.party==='مورد كشف دولار'));await p.getByLabel('بحث تفاصيل حركة المادة',{exact:true}).fill('');
 await p.getByLabel('مخزن كشف المادة',{exact:true}).selectOption('2');await p.getByRole('button',{name:'عرض حركة المادة',exact:true}).click();await loaded(p,codeA);await rowsEqual(p,dated.rows.filter(r=>r.warehouseId===2));assert.equal(qty(await p.getByTestId('material-current-qty').innerText()),2);
 h.checks.dateDirectionSearchWarehousePreserveOriginalBalances=true;
 const future=sql("select((now()at time zone'Asia/Baghdad')::date+10)::text"),empty=await report('admin',A,{from:future});assert.equal(empty.currentQty,12);assert.equal(empty.rows.length,0);assert.ok(empty.warehouses.every(w=>w.beforeFirst===null&&w.afterLast===null));
 await p.getByLabel('مخزن كشف المادة',{exact:true}).selectOption('');await p.getByLabel('بداية حركة المادة',{exact:true}).fill(future);await p.getByRole('button',{name:'عرض حركة المادة',exact:true}).click();await loaded(p,codeA);assert.equal(await p.locator('.mlMovement').count(),0);assert.equal(qty(await p.getByTestId('material-current-qty').innerText()),12);assert.ok((await p.locator('.mlWarehouseGrid').innerText()).includes('—'));h.checks.emptyPeriodRetainsCurrentStockWithoutInventedOpening=true;
 await p.getByLabel('مخزن كشف المادة',{exact:true}).selectOption('');await p.getByLabel('بداية حركة المادة',{exact:true}).fill('');await p.getByLabel('عرض الأسعار المثبتة بالمستند',{exact:true}).check();await loaded(p,codeA);await p.locator('.mlPrice').filter({hasText:'2,075 د.ع'}).waitFor();await rowsEqual(p,priced.rows);
 const pricedHtml=await h.report(p,admin.ctx,p.locator('.mlWorkspace>.reportExport'),'material-priced');assert.ok(pricedHtml.includes('3,000 د.ع'));assert.ok(pricedHtml.includes('2,075 د.ع'));assert.ok(pricedHtml.includes('سعر المادة غير موزّع'));assert.ok(pricedHtml.includes('مسؤول تجهيز المخزن'));assert.ok(pricedHtml.includes('مورد كشف المواد'));assert.ok(!pricedHtml.includes(codeB));
 h.checks.historicalIqdPricesSupplierCustomerPreparerPdf=true;
 // Wrong-product success cannot reach a card or PDF; a retry restores confirmed data.
 let wrong=true;h.setIntercept(async({route,call,response})=>{if(wrong&&call.body?.action==='material_report'){wrong=false;const data=await response.json();data.rows[0].productId=B;await route.fulfill({status:200,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify(data)});return true;}return false;});
 await p.getByRole('button',{name:'عرض حركة المادة',exact:true}).click();await p.getByRole('alert').filter({hasText:'تغيّر نطاق الكشف'}).waitFor();await noOldReport(p);h.setIntercept(null);await p.getByRole('button',{name:'إعادة المحاولة',exact:true}).click();await loaded(p,codeA);
 let fail=true;h.setIntercept(async({route,call})=>{if(fail&&call.body?.action==='material_report'){fail=false;await route.fulfill({status:503,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify({code:'TEST503',message:'تعذر تأكيد كشف الاختبار'})});return true;}return false;});
 await p.getByRole('button',{name:'عرض حركة المادة',exact:true}).click();await p.getByRole('button',{name:'إعادة المحاولة',exact:true}).waitFor();await noOldReport(p);h.setIntercept(null);await p.getByRole('button',{name:'إعادة المحاولة',exact:true}).click();await loaded(p,codeA);await rowsEqual(p,priced.rows);
 h.checks.mismatchedResponseAndFailedRefreshHideStaleExport=true;
 // The general and customer tabs use the same explicit-ID picker, never broad text matching.
 await p.getByRole('tab',{name:'جميع الحركات',exact:true}).click();await picker(p).waitFor();await choose(p,codeB,{touch:true});await p.locator('.movementEntry').first().waitFor();assert.equal(await p.locator('.movementEntry').count(),alternate.rows.length);assert.ok((await p.locator('.movementEntry').allTextContents()).every(text=>text.includes('انفيرتر 15KW بديل')));
 await p.getByRole('tab',{name:'جميع الحركات',exact:true}).click();assert.equal(await p.locator('[data-selected-product-id="'+B+'"]').count(),1);assert.equal(await p.locator('.movementEntry').count(),alternate.rows.length);
 const generalRequests=()=>h.calls.filter(call=>call.body?.action==='movements').length,previousRequests=generalRequests();await p.getByRole('button',{name:'تغيير المادة',exact:true}).click();await picker(p).fill('15KW');await picker(p).fill('');assert.equal(await p.locator('.movementEntry').count(),0);assert.equal(await p.locator('.movementReportActions').count(),0);assert.equal(generalRequests(),previousRequests,'blank search must not load all products');await p.getByRole('button',{name:'عرض جميع المواد',exact:true}).click();await p.locator('.movementEntry').first().waitFor();assert.ok(await p.locator('.movementEntry').count()>1);
 await picker(p).fill('15KW');assert.equal(await p.locator('.movementEntry').count(),0);assert.equal(await p.locator('.movementReportActions').count(),0);await p.getByRole('option',{name:new RegExp(codeA)}).click();await p.locator('.movementEntry').first().waitFor();assert.equal(await p.locator('.movementEntry').count(),full.rows.length);assert.ok((await p.locator('.movementEntry').allTextContents()).every(text=>text.includes('انفيرتر 15KW فحص دقيق')));
 let failGeneral=true;h.setIntercept(async({route,call})=>{if(failGeneral&&call.body?.action==='movements'){failGeneral=false;await route.fulfill({status:503,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify({code:'TEST503',message:'تعذر تحديث كشف الاختبار'})});return true;}return false;});await p.locator('.movementRefresh').click();await p.locator('.movementError').waitFor();assert.equal(await p.locator('.movementEntry').count(),0);assert.equal(await p.locator('.movementReportActions .reportButton.download:not([disabled])').count(),0);h.setIntercept(null);await p.locator('.movementRefresh').click();await p.locator('.movementEntry').first().waitFor();assert.equal(await p.locator('.movementEntry').count(),full.rows.length);
 await p.getByRole('tab',{name:'مادة وعميل',exact:true}).click();await choose(p,codeA);await p.getByLabel('اسم العميل في الحركة',{exact:true}).fill('زبون بيع الألواح');await p.getByRole('button',{name:'عرض السجل',exact:true}).click();await p.locator('.movementEntry').filter({hasText:'زبون بيع الألواح'}).waitFor();assert.equal(await p.locator('.movementEntry').count(),1);assert.equal(qty(await p.locator('.movementEntry .movementBalance b').innerText()),full.rows.find(row=>row.kind==='sale').balance);
 h.checks.generalAndCustomerTabsUseExactProductId=true;
 const stock=await h.open(u.warehouse,'/?section=stockMovement');await choose(stock.page,codeA);await loaded(stock.page,codeA);await rowsEqual(stock.page,warehouse.rows);assert.equal(await stock.page.getByLabel('عرض الأسعار المثبتة بالمستند',{exact:true}).count(),0);assert.equal(await stock.page.locator('.mlPrice').count(),0);
 const other=await h.open(u.other,'/?section=stockMovement');await choose(other.page,codeA);await loaded(other.page,codeA);assert.equal(await other.page.locator('.mlMovement').count(),0);assert.ok(!(await other.page.locator('.mlWorkspace').innerText()).includes('زبون بيع الألواح'));
 h.checks.uiWarehouseNoPricesAndForeignSellerNoReceiptDetails=true;
 assert.equal(fingerprint(),before);h.checks.stockFinanceFingerprintUnchanged=before;await h.finish();console.log('PASS V4.1.5 exact material picker, balances, scoped details, stale-response safety, real PDF and responsive layout.');
}catch(error){heldRelease?.();await h.fail(error);throw error;}finally{await h.close();}
