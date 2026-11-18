import assert from 'node:assert/strict';

process.env.SOLAR_FIXTURE_DB ||= 'solar_v4113_warehouse_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3182';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4113/warehouse-browser';
const {createHarness,sql,base,db,api}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4113_warehouse_browser');
assert.equal(new URL(api).hostname,'127.0.0.1');

const staff='00000000-0000-0000-0000-000000411351';
const invoiceId=Number(sql('select id from public.transactions where party_id=-411351'));
const pricingId=Number(sql('select id from public.transactions where party_id=-411352'));
assert.ok(invoiceId>0&&pricingId>0);
const cardSelector=id=>'#warehouse-order-'+id;
const state=()=>sql('select warehouse_status from public.transactions where id='+invoiceId);
const balances=()=>sql(`select md5(jsonb_build_array(
 (select jsonb_agg(to_jsonb(p) order by id) from products p),
 (select jsonb_agg(to_jsonb(i) order by id) from transaction_items i),
 (select jsonb_agg(to_jsonb(s) order by warehouse_id,product_id) from solar_private.warehouse_stocks s),
 (select jsonb_agg(jsonb_build_array(id,total,profit) order by id) from transactions),
 (select jsonb_agg(to_jsonb(c) order by id) from solar_cash_entries c)
 )::text)`);
async function search(page,term){
 await page.getByRole('textbox',{name:'بحث فواتير التجهيز'}).fill(term);
 await page.getByRole('button',{name:'بحث / تحديث',exact:true}).click();
}
const h=await createHarness('warehouse-daily');
try{
 const start=balances();
 assert.equal(state(),'pending');
 const {page}=await h.open(staff,'/?section=home');
 await page.locator('main a[href="/?section=warehouse"]:visible').first().click();
 const queue=page.getByTestId('warehouse-daily-queue');
 await queue.waitFor();
 const scope=queue.getByRole('combobox',{name:'مخزن التجهيز'});
 await scope.locator('option[value="1"]').waitFor({state:'attached'});
 assert.equal(await scope.locator('option[value="2"]').count(),0);
 assert.equal(await queue.locator('.warehousePricing').count(),0);
 const panes=queue.getByRole('navigation',{name:'نوع تجهيز المخزن'});
 assert.equal(await panes.getByRole('button',{name:'فواتير البيع'}).getAttribute('aria-pressed'),'true');
 await search(page,'فحص تجهيز');
 await page.waitForFunction(()=>document.querySelectorAll('.warehouseOrder').length===2);
 const card=queue.locator(cardSelector(invoiceId));
 const pricing=queue.locator(cardSelector(pricingId));
 assert.equal(await card.getAttribute('data-preparation-state'),'pending');
 assert.equal(await pricing.getAttribute('data-preparation-state'),'pricing');
 assert.equal(await card.getByTestId('warehouse-required-quantity').innerText(),'3');
 assert.equal(await pricing.getByTestId('warehouse-required-quantity').innerText(),'3');
 assert.equal(await queue.getByTestId('warehouse-prepared-quantity').count(),0);
 assert.equal(await pricing.getByRole('button',{name:'تم التجهيز ✓'}).isDisabled(),true);
 await queue.getByRole('button',{name:/مراجعة وصل/}).click();
 await card.locator('.warehousePickList[open]').waitFor();
 assert.equal(await page.evaluate(()=>document.activeElement.id),'warehouse-order-'+invoiceId);
 await card.getByRole('button',{name:'تعديل المواد'}).click();
 assert.equal(await card.getByLabel('عدد لوح فحص التجهيز').inputValue(),'3');
 await card.getByRole('button',{name:'إلغاء',exact:true}).click();
 assert.equal(balances(),start);
 await h.layout(page,'warehouse-pending',card);
 const prepare=card.getByRole('button',{name:'تم التجهيز ✓'});
 const bounds=await prepare.boundingBox();
 assert.ok(bounds.width>=44&&bounds.height>=40);
 await prepare.click();
 await queue.getByText('تم التجهيز وإشعار صاحب الفاتورة.',{exact:true}).waitFor();
 assert.equal(state(),'ready');
 assert.equal(sql('select warehouse_prepared_by from public.transactions where id='+invoiceId),staff);
 const lists=queue.getByRole('navigation',{name:'قوائم التجهيز'});
 await lists.getByRole('button',{name:/^تم التجهيز/}).click();
 await card.locator('[data-testid="warehouse-prepared-quantity"]').waitFor();
 assert.equal(await card.getByTestId('warehouse-prepared-quantity').innerText(),'3');
 assert.equal(await card.getByTestId('warehouse-required-quantity').count(),0);
 assert.ok((await card.innerText()).includes('أمين تجهيز الاختبار'));
 assert.equal(balances(),start);
 await page.goto(base+'/?section=warehouse&job='+invoiceId);
 await card.locator('.warehousePickList[open]').waitFor();
 assert.ok((await card.getAttribute('class')).includes('highlighted'));
 await card.getByRole('button',{name:'معاينة',exact:true}).waitFor();
 await card.getByRole('button',{name:'إعادة للتجهيز'}).click();
 await queue.getByText('أعيدت الفاتورة لقائمة التجهيز.',{exact:true}).waitFor();
 assert.equal(state(),'pending');
 await page.goto(base+'/?section=warehouse');
 await lists.getByRole('button',{name:/^كل الفواتير/}).click();
 await search(page,'فحص تجهيز خارج الصلاحية');
 await queue.getByText('لا توجد فواتير مطابقة للبحث.',{exact:true}).waitFor();
 assert.equal(await queue.locator(cardSelector(-411353)).count(),0);
 await panes.getByRole('button',{name:/طلبات نقل المخازن/}).click();
 await queue.locator('.warehouseTransferQueue').waitFor();
 await panes.getByRole('button',{name:'فواتير البيع'}).click();
 await scope.waitFor();
 const {page:admin}=await h.open('admin','/?section=warehouse&job='+pricingId);
 const adminQueue=admin.getByTestId('warehouse-daily-queue');
 const adminPricing=adminQueue.getByRole('region',{name:'تسعير إضافات المخزن'});
 await adminQueue.locator(cardSelector(pricingId)+' .warehousePickList[open]').waitFor();
 await adminPricing.getByRole('button',{name:/فحص تجهيز بانتظار التسعير/}).click();
 await adminPricing.getByLabel('سعر المادة الجديدة بطارية فحص التجهيز').waitFor();
 await adminPricing.getByRole('button',{name:'رجوع',exact:true}).click();
 await adminQueue.getByRole('button',{name:'عرض قائمة التجهيز كاملة'}).click();
 await adminQueue.getByRole('combobox',{name:'مخزن التجهيز'}).selectOption('2');
 await search(admin,'فحص تجهيز خارج الصلاحية');
 const foreign=adminQueue.locator(cardSelector(-411353));
 await foreign.waitFor();
 assert.equal(await adminQueue.locator('.warehouseOrder').count(),1);
 await h.layout(admin,'warehouse-admin-scope',foreign);
 assert.equal(balances(),start);
 assert.deepEqual(h.calls.filter(c=>c.path.endsWith('/solar_warehouse_action')).map(c=>c.body.action),['ready','reopen']);
 Object.assign(h.checks,{staffScope:true,adminScopeAndPricing:true,pendingPricingBlocked:true,reviewAndEditCancel:true,preparationAndReopen:true,deepLink:true,transferNavigation:true,financialAndStockFingerprintStable:true});
 await h.finish();
 console.log('PASS warehouse staff and admin browser workflows, 360/390/1366 px; preparation and reopen persisted with stable stock and financial balances');
}catch(e){await h.fail(e);throw e;}finally{await h.close();}
