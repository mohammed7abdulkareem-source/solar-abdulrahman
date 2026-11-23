import assert from 'node:assert/strict';
import {createHarness} from './version4-browser-support.mjs';

const harness = await createHarness('mobile-invoice-frame');
try {
 const {page} = await harness.open(process.env.SOLAR_INVOICE_SELLER||'owner', '/?section=sale');
 const header = page.locator('.premiumTopbar');
 const nav = page.getByRole('navigation', {name:'التنقل السريع'});
 const checkout = page.locator('.deskCheckout');
 await checkout.waitFor();

 for (const width of [360, 390]) {
  await page.setViewportSize({width, height:844});
  for (const fraction of [0, 0.4, 1]) {
   await page.evaluate(f => window.scrollTo({top:f*(document.documentElement.scrollHeight-innerHeight),behavior:'instant'}), fraction);
   await page.waitForFunction(() => Math.abs(document.querySelector('.premiumTopbar').getBoundingClientRect().top)<1 && Math.abs(document.querySelector('.appMobileBar').getBoundingClientRect().bottom-visualViewport.height)<1);
   assert.ok(await page.evaluate(() => document.documentElement.scrollWidth<=innerWidth+1));
  }
  await page.screenshot({path:harness.dir+'/checkout-'+width+'.png',animations:'disabled'});
  const panel=await checkout.boundingBox(), bar=await nav.boundingBox();
  assert.ok(panel.y+panel.height<=bar.y, 'Final receipt controls must clear the bottom navigation.');
  assert.ok(await page.locator('.invoiceWorkspace input, .invoiceWorkspace textarea, .invoiceWorkspace select').evaluateAll(els=>els.filter(el=>el.clientHeight && !['checkbox','radio'].includes(el.type)).every(el=>parseFloat(getComputedStyle(el).fontSize)>=16)), 'Editable fields must avoid automatic focus zoom on iPhone.');
 }
 const field=page.getByRole('textbox',{name:'ملاحظات الفاتورة'});
 await field.focus();
 // Mobile keyboards can pan the visible viewport without resizing the document.
 // Dispatch scroll and resize separately to check the real shell subscribers.
 await page.evaluate(() => {
  Object.defineProperties(visualViewport, {
   height:{configurable:true,get:()=>document.documentElement.clientHeight-285},
   offsetTop:{configurable:true,get:()=>72}
  });
  visualViewport.dispatchEvent(new Event('resize'));
 });
 await page.waitForFunction(() => !document.querySelector('.appMobileBar').getClientRects().length && Math.abs(document.querySelector('.premiumTopbar').getBoundingClientRect().top-72)<1);
 await page.evaluate(() => {
  Object.defineProperty(visualViewport,'offsetTop',{configurable:true,get:()=>38});
  visualViewport.dispatchEvent(new Event('scroll'));
 });
 await page.waitForFunction(() => Math.abs(document.querySelector('.premiumTopbar').getBoundingClientRect().top-38)<1);
 await field.blur();
 await page.evaluate(() => {
  delete visualViewport.height;
  delete visualViewport.offsetTop;
  visualViewport.dispatchEvent(new Event('resize'));
 });
 await page.waitForFunction(() => Math.abs(document.querySelector('.premiumTopbar').getBoundingClientRect().top)<1 && Math.abs(document.querySelector('.appMobileBar').getBoundingClientRect().bottom-visualViewport.height)<1);
 await page.setViewportSize({width:844,height:390});
 await field.focus();
 await page.evaluate(() => new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
 assert.ok(await nav.isVisible(), 'A change to landscape alone must not be treated as a keyboard.');
 await field.blur();
 await page.setViewportSize({width:1366,height:900});
 assert.equal(await header.evaluate(el=>getComputedStyle(el).position),'sticky');
 assert.equal(await nav.count(),0);
 await page.screenshot({path:harness.dir+'/checkout-desktop.png',animations:'disabled'});
 await harness.finish();
 console.log('Invoice checkout, viewport panning, keyboard dismissal, rotation and desktop navigation passed.');
} catch(error) {
 await harness.fail(error);
 throw error;
} finally {
 await harness.close();
}
