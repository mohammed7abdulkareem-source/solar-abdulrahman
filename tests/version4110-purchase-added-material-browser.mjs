// Use an isolated database loaded with the V4.1.9 purchase browser fixtures.
import assert from 'node:assert/strict';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4110_ui_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3166';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4110/purchase-add-browser';
const {createHarness, base, sql, scalar} = await import('./version4-browser-support.mjs');
const harness = await createHarness('purchase-add-browser');
const ownerId = '00000000-0000-0000-0000-000000419502';
const addedId = -419502;
const addedName = sql('select name from products where id=' + addedId);
const purchase = JSON.parse(sql("select to_jsonb(t) from transactions t where notes='v419-cash-usd-purchase'"));
const originalTotal = Number(purchase.total);
const stock = () => JSON.parse(sql('select jsonb_build_array(qty,cost) from products where id=' + addedId));
const addedLine = () => sql('select jsonb_build_array(qty,source_price) from transaction_items where transaction_id=' + purchase.id + ' and product_id=' + addedId);
const priorSale = () => sql("select to_jsonb(t) from transactions t where notes='v419-consumed-sale'");

async function openEdit(page) {
 await page.goto(base + '/?section=purchase');
 await page.waitForLoadState('networkidle');
 await page.locator('.deskHistory > summary').click();
 await page.getByLabel('بحث الفواتير السابقة').fill(String(purchase.receipt_no));
 const card = page.locator('.historyItem').filter({
  has: page.locator('summary').filter({hasText: 'فاتورة شراء رقم ' + purchase.receipt_no})
 });
 await card.getByRole('button', {name: 'تعديل', exact: true}).click();
 await page.getByRole('button', {name: 'معاينة تعديل الشراء', exact: true}).waitFor();
}

try {
 assert.equal(stock()[0], 0);
 assert.equal(addedLine(), '');
 const originalSale = priorSale();
 const {page} = await harness.open(ownerId);
 await openEdit(page);
 const search = page.getByLabel('البحث عن مادة', {exact: true});
 await search.fill('V419-CONSUMED');
 await page.getByRole('button', {name: 'إضافة ' + addedName, exact: true}).click();
 const qty = page.getByLabel('الكمية — ' + addedName, {exact: true});
 const price = page.getByLabel('سعر الشراء — ' + addedName, {exact: true});
 const preview = page.getByRole('button', {name: 'معاينة تعديل الشراء', exact: true});
 const save = page.getByRole('button', {name: 'تأكيد تعديل الشراء', exact: true});
 const review = page.locator('[data-purchase-correction-review]');
 const reviewedItem = review.locator('[data-purchase-correction-product="' + addedId + '"]');
 await qty.fill('2');
 await price.fill('4');
 await preview.click();
 await review.waitFor();
 assert.equal(await save.isEnabled(), true, await review.innerText());
 await price.fill('5');
 await review.waitFor({state: 'hidden'});
 await preview.click();
 await reviewedItem.waitFor();
 assert.match(await reviewedItem.innerText(), /مادة مضافة للوصل/);
 const invoiceQty = reviewedItem.locator('.purchaseCompare').filter({hasText: 'كمية الفاتورة'});
 assert.equal((await invoiceQty.locator('bdi').first().innerText()).trim(), '0');
 assert.equal((await invoiceQty.locator('strong').innerText()).trim(), '2');
 const unitPrice = reviewedItem.locator('.purchaseCompare').filter({hasText: 'سعر شراء الوحدة'});
 assert.equal((await unitPrice.locator('bdi').first().innerText()).trim(), '—');
 assert.match(await unitPrice.locator('strong').innerText(), /5\s*\$/);
 assert.equal(addedLine(), '');
 await harness.layout(page, 'added-purchase-material', reviewedItem);
 await save.click();
 await qty.waitFor({state: 'hidden'});
 assert.deepEqual(JSON.parse(addedLine()), [2, 5]);
 assert.deepEqual(stock(), [2, 8300]);
 assert.equal(scalar('select total from transactions where id=' + purchase.id), originalTotal + 16600);
 assert.equal(priorSale(), originalSale);
 await openEdit(page);
 assert.equal(await qty.inputValue(), '2');
 assert.equal(await price.inputValue(), '5');
 await page.getByRole('button', {name: 'حذف ' + addedName, exact: true}).click();
 await preview.click();
 await review.waitFor();
 assert.equal(await save.isEnabled(), true, await review.innerText());
 await save.click();
 await review.waitFor({state: 'hidden'});
 assert.equal(addedLine(), '');
 assert.equal(stock()[0], 0);
 assert.equal(scalar('select total from transactions where id=' + purchase.id), originalTotal);
 assert.equal(priorSale(), originalSale);
 harness.checks.zeroStockMaterialAddedToSameUsdReceiptAndRemovable = true;
 await harness.finish();
 console.log('PASS purchase edit: search, add, re-preview in USD, save, reopen, remove and verify original invoice and stock.');
} catch (error) {
 await harness.fail(error);
 throw error;
} finally {
 await harness.close();
}
