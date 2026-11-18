// Read-only follow-up after version419-purchase-correction-browser.mjs.
// Proves corrected receipt/current document and immutable original movement are distinct.
import assert from 'node:assert/strict';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v419_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3165';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v419/purchase-correction-documents';
const {createHarness,sql,fingerprint}=await import('./version4-browser-support.mjs');
const owner='00000000-0000-0000-0000-000000419502',h=await createHarness('purchase-correction-documents');
const number=text=>Number((String(text).match(/[−-]?\d[\d,]*(?:\.\d+)?/)?.[0]||'NaN').replaceAll(',','').replace('−','-'));
try{
 const before=fingerprint(),invoice=JSON.parse(sql("select to_jsonb(t) from transactions t where notes='v419-cash-iqd-purchase'"));assert.equal(invoice.total,6000);
 const {page:p,ctx}=await h.open(owner,'/?section=supplierStatement');await p.waitForLoadState('networkidle');await p.getByRole('combobox',{name:'ابحث عن المورد بالاسم أو الهاتف…',exact:true}).fill('مورد الشراء النقدي V419');await p.getByRole('option',{name:'مورد الشراء النقدي V419',exact:true}).click();await p.getByTestId('supplier-statement-balance').waitFor();
 await p.locator('.miniMovementRow').filter({hasText:'شراء نقدي'}).filter({hasText:'#'+invoice.receipt_no}).click();
 const scope=p.getByRole('region',{name:'نسخ وصل الشراء',exact:true});await scope.waitFor();assert.equal(number(await p.locator('.miniDetailHero strong').innerText()),4000);assert.equal(await p.getByRole('button',{name:'نسخة الحركة الأصلية',exact:true}).getAttribute('aria-pressed'),'true');await p.getByRole('button',{name:'تعديل الوصل الحالي',exact:true}).waitFor();
 const plain=html=>p.evaluate(markup=>new DOMParser().parseFromString(markup,'text/html').body.textContent,html);
 const original=await plain(await h.report(p,ctx,p.locator('.miniPartyAccount>.reportExport'),'supplier-original-movement'));assert.match(original,/نسخة الحركة الأصلية قبل التصحيح/);assert.match(original,/2,000/);assert.match(original,/4,000/);assert.doesNotMatch(original,/6,000/);
 await p.getByRole('button',{name:'نسخة الوصل الحالية',exact:true}).click();assert.equal(await p.getByRole('button',{name:'نسخة الوصل الحالية',exact:true}).getAttribute('aria-pressed'),'true');
 const current=await plain(await h.report(p,ctx,p.locator('.miniPartyAccount>.reportExport'),'supplier-current-receipt'));assert.match(current,/النسخة الحالية للوصل بعد التصحيح/);assert.match(current,/3,000/);assert.match(current,/6,000/);assert.ok(original.includes(String(invoice.receipt_no))&&current.includes(String(invoice.receipt_no)));assert.equal(number(await p.locator('.miniDetailHero strong').innerText()),4000);
 await h.layout(p,'supplier-original-current-versions',scope);h.checks.originalMovement4000AndCurrentReceipt6000ExportDistinct=true;
 await p.getByRole('button',{name:'تعديل الوصل الحالي',exact:true}).click();assert.equal(number(await p.getByLabel('سعر الشراء — لوح شراء نقدي V419',{exact:true}).inputValue()),3000);assert.equal(number(await p.getByLabel('الكمية — لوح شراء نقدي V419',{exact:true}).inputValue()),2);await p.getByRole('button',{name:'معاينة تعديل الشراء',exact:true}).waitFor();h.checks.editUsesCurrentReceiptNotHistoricalSnapshot=true;
 assert.equal(fingerprint(),before);assert.equal(h.calls.filter(c=>c.path.endsWith('/solar_invoice_save')).length,0);h.checks.allActionsReadOnly=true;await h.finish();console.log('PASS V419 supplier original/current receipt documents and current editor; no financial writes.');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
