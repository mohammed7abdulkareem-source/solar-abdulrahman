// Uses a separate, seeded local database because the public product form is saved twice.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

process.env.SOLAR_FIXTURE_DB ||= 'solar_v4110_autocomplete_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3173';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4110/product-name-browser';
const {createHarness, sql, fingerprint, base, db} = await import('./version4-browser-support.mjs');
assert.equal(db, 'solar_v4110_autocomplete_browser');
const h = await createHarness('product-name');
const name = page => page.getByRole('combobox', {name: 'اسم المادة', exact: true});
const list = page => page.getByRole('listbox', {name: 'المواد المشابهة', exact: true});
const panel = page => list(page).getByRole('option', {name: /QTY-PNL/});
const form = page => page.locator('.productsManager form');
const createButton = page => form(page).getByRole('button', {name: 'حفظ المادة', exact: true});
const newName = 'لوح تجريبي مستقل ' + randomUUID();
const selectTags = async (page, brand, category) => {
 await form(page).locator('[name=brand]').selectOption(brand);
 await form(page).locator('[name=category]').selectOption(category);
};

try {
 const initial = fingerprint();
 const {page} = await h.open('admin', '/?section=products');
 await createButton(page).waitFor();
 await name(page).fill('6');
 await panel(page).waitFor();
 assert.equal(await name(page).getAttribute('aria-expanded'), 'true');
 for (const query of ['600', '٦٠٠']) {
  await name(page).fill(query);
  await panel(page).waitFor();
  const info = await panel(page).innerText();
  assert.match(info, /600W/);
  assert.match(info, /FULLMAX/);
  assert.match(info, /الواح/);
 }
 assert.equal(await list(page).evaluate(node => getComputedStyle(node).direction), 'rtl');
 await h.layout(page, 'product-name-options', list(page));
 const count = await list(page).getByRole('option').count();
 for (let index = 0; index < count; index++) {
  await name(page).press('ArrowDown');
  if (await panel(page).getAttribute('aria-selected') === 'true') break;
 }
 assert.equal(await name(page).getAttribute('aria-activedescendant'), await panel(page).getAttribute('id'));
 await name(page).press('Enter');
 await form(page).getByRole('button', {name: 'حفظ التعديل', exact: true}).waitFor();
 assert.equal(await name(page).inputValue(), '600W');
 assert.equal(await form(page).locator('[name=category]').inputValue(), 'الواح');
 assert.equal(await form(page).locator('[name=brand]').inputValue(), 'FULLMAX');
 assert.equal(await list(page).count(), 0);
 await form(page).getByRole('button', {name: 'إلغاء التعديل', exact: true}).click();
 assert.equal(await name(page).inputValue(), '');
 assert.equal(await form(page).locator('[name=category]').inputValue(), '');

 await name(page).fill('٦٠٠');
 await panel(page).tap();
 assert.equal(await name(page).inputValue(), '600W');
 await form(page).getByRole('button', {name: 'إلغاء التعديل', exact: true}).click();
 await name(page).fill('600');
 await name(page).press('Escape');
 assert.equal(await list(page).count(), 0);
 assert.equal(await name(page).inputValue(), '600');
 await name(page).fill('8KW/IP21');
 await list(page).waitFor();
 await name(page).press('Tab');
 assert.equal(await list(page).count(), 0);
 await selectTags(page, 'FULLMAX', 'انفيرتر');
 await createButton(page).click();
 await form(page).getByRole('alert').waitFor();
 assert.equal(fingerprint(), initial, 'Suggestion selection or duplicate submission changed stored data');
 h.checks.firstKeystrokeArabicWesternDigitsTouchKeyboardAndNoDuplicate = true;

 await name(page).fill(newName);
 assert.equal(await list(page).count(), 0);
 assert.equal(await form(page).getByRole('alert').count(), 0);
 await selectTags(page, 'FULLMAX', 'ألواح');
 await createButton(page).click();
 await page.getByRole('status').filter({hasText: 'تم حفظ المادة'}).waitFor();
 assert.equal(await name(page).inputValue(), '');
 assert.equal(await form(page).locator('[name=brand]').inputValue(), '');
 assert.equal(sql("select count(*) from products where name='" + newName + "' and qty=0 and cost=0"), '1');
 h.checks.newNameCanBeSavedAtZeroStockAndFormResets = true;

 await page.goto(base + '/?section=purchasesHub');
 await page.getByRole('button', {name: 'تعريف مادة جديدة', exact: true}).click();
 await createButton(page).waitFor();
 await name(page).fill(newName);
 await list(page).waitFor();
 await name(page).press('Escape');
 await selectTags(page, 'FULLMAX', 'مستلزمات');
 await createButton(page).click();
 await page.locator('[data-purchases-hub]').waitFor();
 assert.equal(sql("select count(*) from products where name='" + newName + "' and qty=0 and cost=0"), '2');
 h.checks.sameNameDistinctCategorySavedAndReturnedToPurchases = true;
 await h.finish();
 console.log('PASS product name autocomplete, Arabic and Western digits, existing stock, keyboard and touch, duplicate guard, save and return.');
} catch (error) {
 await h.fail(error);
 throw error;
} finally {
 await h.close();
}
