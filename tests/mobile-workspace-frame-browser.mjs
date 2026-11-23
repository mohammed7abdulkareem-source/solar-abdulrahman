import assert from 'node:assert/strict';
import {createHarness, ids} from './version4-browser-support.mjs';

const harness = await createHarness('mobile-workspace-frame');
async function assertBars(page) {
 await page.waitForFunction(() => {
  const top = document.querySelector('.premiumTopbar');
  const bottom = document.querySelector('.appMobileBar');
  return getComputedStyle(top).position === 'fixed' &&
   Math.abs(top.getBoundingClientRect().top - visualViewport.offsetTop) < 1 &&
   Math.abs(bottom.getBoundingClientRect().bottom - visualViewport.offsetTop - visualViewport.height) < 1;
 });
}
async function useDesign(page, mode) {
 await page.evaluate(({userId, mode}) => window.dispatchEvent(new CustomEvent('solar-section-layout', {
  detail: {userId, layout:{mode, mobileColumns:3, desktopColumns:6, order:[], revision:10000}}
 })), {userId:ids.admin, mode});
 await page.waitForFunction(expected => document.body.dataset.workspaceDesign === expected, mode);
}

try {
 const {page} = await harness.open('admin', '/?section=cash&cashView=entry&cashMode=external_profit');
 const entry = page.getByRole('region', {name:'إضافة حركة مالية'});
 await entry.waitFor();
 const note = page.getByRole('textbox', {name:'بيان الحركة', exact:true});
 for (const mode of ['groups', 'general', 'columns', 'desk', 'solar', 'premium']) {
  await useDesign(page, mode);
  await page.setViewportSize({width:390, height:740});
  await page.evaluate(() => window.scrollTo({top:0, behavior:'instant'}));
  await assertBars(page);
  assert.ok(await page.evaluate(() => {
   const title = document.querySelector('.premiumTopbar').getBoundingClientRect();
   const status = document.querySelector('.workspaceStatusArea').getBoundingClientRect();
   return Math.abs(status.top - title.bottom) < 1;
  }), 'Reserve exactly one header row at the start of the page.');
  await page.evaluate(() => window.scrollTo({top:document.documentElement.scrollHeight, behavior:'instant'}));
  await assertBars(page);
  assert.ok(await page.evaluate(() => window.scrollY > 50), 'The cash entry must have scrolled.');
  const save = await entry.getByRole('button', {name:'حفظ الحركة'}).boundingBox();
  const bar = await page.locator('.appMobileBar').boundingBox();
  assert.ok(save.y + save.height <= bar.y, 'Keep the cash entry save action above the navigation.');
  if(mode === 'groups') await page.screenshot({path:harness.dir+'/cash-entry-390.png', animations:'disabled'});
 }
 await note.focus();
 assert.ok(await note.evaluate(el => parseFloat(getComputedStyle(el).fontSize) >= 16));
 await page.evaluate(() => {
  Object.defineProperties(visualViewport, {
   height:{configurable:true, get:() => document.documentElement.clientHeight-260},
   offsetTop:{configurable:true, get:() => 48}
  });
  visualViewport.dispatchEvent(new Event('scroll'));
 });
 await page.waitForFunction(() => !document.querySelector('.appMobileBar').getClientRects().length &&
  Math.abs(document.querySelector('.premiumTopbar').getBoundingClientRect().top - 48) < 1);
 await note.blur();
 await page.evaluate(() => {
  delete visualViewport.height;
  delete visualViewport.offsetTop;
  visualViewport.dispatchEvent(new Event('resize'));
 });
 await assertBars(page);

 for (const path of ['/', '/?section=stock']) {
  const {page:section} = await harness.open('admin', path);
  await section.setViewportSize({width:360, height:640});
  await section.locator(path === '/' ? '.premiumDashboard' : '.inventoryBalanceMetrics').waitFor();
  await section.evaluate(() => window.scrollTo({top:document.documentElement.scrollHeight, behavior:'instant'}));
  await assertBars(section);
  assert.ok(await section.evaluate(() => window.scrollY>0 && document.documentElement.scrollWidth<=innerWidth+1));
  await section.setViewportSize({width:1366, height:900});
  assert.equal(await section.locator('.premiumTopbar').evaluate(el => getComputedStyle(el).position), 'sticky');
  assert.ok(!await section.locator('.appMobileBar').isVisible());
 }
 await harness.finish();
 console.log('Cash entry, saved designs, keyboard, home, inventory and desktop shell passed.');
} catch(error) {
 await harness.fail(error);
 throw error;
} finally {
 await harness.close();
}
