process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
// Browser → real local PostgREST 14 → protected RPC → local PostgreSQL.
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
import {PNG} from 'pngjs';
import jsQR from 'jsqr';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base=process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3048',api=process.env.SOLAR_RPC_TEST_URL||'http://127.0.0.1:3050';
for(const u of [base,api])assert.match(u,/^http:\/\/(127\.0\.0\.1|localhost):\d+$/);
const uid='00000000-0000-0000-0000-000000003490',secret='solar-local-test-only-signing-secret-347',encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
const start=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600}),token=start+'.'+createHmac('sha256',secret).update(start).digest('base64url');
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});const ctx=await browser.newContext({viewport:{width:390,height:900}});ctx.setDefaultTimeout(15000);let saves=0,savedInvoice;const failures=[];
await ctx.addInitScript(({uid,token})=>localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify({access_token:token,refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}})),{uid,token});
await ctx.routeWebSocket(/supabase/,socket=>socket.close());
await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
 const req=route.request(),url=new URL(req.url());
 if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
 if(url.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:uid,email:'fixture@local.test',aud:'authenticated'})});
 if(url.pathname.startsWith('/rest/v1/')){
  const headers={...req.headers(),authorization:'Bearer '+token};delete headers.host;delete headers.apikey;delete headers.origin;
  const response=await ctx.request.fetch(api+url.pathname.replace('/rest/v1','')+url.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});
  if(url.pathname.endsWith('/solar_invoice_save')){saves++;savedInvoice=await response.json();}
  if(response.status()>=400){const data=await response.json();if(!url.pathname.endsWith('/solar_staff_directory'))failures.push({path:url.pathname,status:response.status(),data});}
  return route.fulfill({response});
 }
 return route.abort();
});
await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
await ctx.addInitScript(()=>{const descriptor=Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype,'srcdoc');Object.defineProperty(HTMLIFrameElement.prototype,'srcdoc',{...descriptor,set(value){if(value.includes('class="salesDocument"'))window.__lastInvoiceHTML=value;return descriptor.set.call(this,value);}});});
const page=await ctx.newPage();page.on('dialog',d=>d.accept());page.on('pageerror',e=>failures.push(e.message));await page.goto(base);await page.locator('.premiumDashboard').waitFor();
await page.locator('.sectionDirectory a[href="/?section=sale"]').click();
await page.locator('.partySearch input').fill('زبون فحص الحساب');await page.locator('.partySearchResults button').filter({hasText:'زبون فحص الحساب والضمان'}).click();
await page.getByLabel('البحث عن مادة',{exact:true}).fill('بطارية فحص');await page.getByRole('button',{name:'إضافة بطارية فحص الوصل',exact:true}).click();
await page.getByLabel('الكمية — بطارية فحص الوصل').fill('1');await page.getByLabel('سعر البيع — بطارية فحص الوصل').fill('150000');
await page.getByRole('checkbox',{name:/إضافة ضمان للفاتورة/}).check();await page.getByLabel('مدة ضمان بطارية فحص الوصل').fill('2');await page.getByLabel('وحدة ضمان بطارية فحص الوصل').selectOption('years');await page.getByLabel('مدة ضمان الصيانة').fill('6');await page.getByLabel('شروط الضمان').fill('شروط واضحة للزبون على الفاتورة');
await page.getByRole('button',{name:'حفظ الوصل',exact:true}).click();const receipt=page.locator('.warrantySaved').filter({hasText:'تم حفظ فاتورة'});await receipt.waitFor();await receipt.getByText(/المستند جاهز/).waitFor();assert.equal(saves,1);assert.equal(savedInvoice.invoiceAccount.previousBalance,1700000);assert.equal(savedInvoice.invoiceAccount.balanceAfter,1850000);assert.equal(savedInvoice.invoiceAccount.lastPayment.amount,300000);
const html=await page.evaluate(()=>window.__lastInvoiceHTML);for(const text of ['الحساب السابق','1,700,000','آخر تسديد سابق','300,000','1,850,000','آخر يوم مشمول','شروط واضحة'])assert.ok(html.includes(text),text);
const popupPromise=page.waitForEvent('popup');await receipt.getByRole('button',{name:'معاينة',exact:true}).click();const popup=await popupPromise;const image=popup.locator('.pdfPage img').first();await image.waitFor();
const png=Buffer.from(await image.evaluate(async img=>{await img.decode();const c=document.createElement('canvas');c.width=img.naturalWidth;c.height=img.naturalHeight;c.getContext('2d').drawImage(img,0,0);return c.toDataURL('image/png').split(',')[1];}),'base64');
const decoded=PNG.sync.read(png),qr=jsQR(new Uint8ClampedArray(decoded.data),decoded.width,decoded.height);assert.equal(qr?.data,'https://solar-abdulrahman.vercel.app/warranty/'+savedInvoice.warrantyToken);
const dir='/workspace/solar-review/invoices-v348';await mkdir(dir,{recursive:true});await writeFile(dir+'/actual-saved-invoice.png',png);await popup.screenshot({path:dir+'/mobile-preview.png',fullPage:true});await popup.close();
await page.locator('.premiumMobileBrand').click();await page.locator('.sectionDirectory a[href="/?section=salesHistory"]').click();const archived=page.locator('.archiveInvoice').filter({hasText:'زبون فحص الحساب والضمان'});await archived.waitFor();const archivePopup=page.waitForEvent('popup');await archived.getByRole('button',{name:'معاينة وصل الزبون',exact:true}).click();const view=await archivePopup;await view.locator('.pdfPage img').first().waitFor();await view.close();assert.ok((await page.evaluate(()=>window.__lastInvoiceHTML)).includes('1,850,000'));
const warehousePopup=page.waitForEvent('popup');await archived.getByRole('button',{name:'معاينة الوصل المخزني',exact:true}).click();const warehouse=await warehousePopup;await warehouse.locator('.pdfPage img').first().waitFor();const warehouseHtml=await page.evaluate(()=>window.__lastInvoiceHTML);assert.ok(warehouseHtml.includes('آخر يوم مشمول'));assert.ok(!warehouseHtml.includes('1,850,000'));assert.ok(!warehouseHtml.includes('300,000'));await warehouse.close();
const safe=await ctx.request.post(api+'/rpc/solar_warranty_verify',{data:{certificate_token:savedInvoice.warehouseQrToken}});assert.equal(safe.status(),200);const safeData=await safe.json();assert.equal(safeData.copy,'warehouse');assert.equal(safeData.total,undefined);assert.equal(safeData.items[0].price,undefined);assert.ok(!JSON.stringify(safeData).includes(savedInvoice.warrantyToken));
await page.goto(base+'/warranty/'+savedInvoice.warehouseQrToken);await page.getByRole('heading',{name:'شهادة ضمان الفاتورة'}).waitFor();await page.getByText('زبون فحص الحساب والضمان',{exact:true}).waitFor();assert.equal(await page.getByText('إجمالي الفاتورة',{exact:true}).count(),0);await page.screenshot({path:dir+'/warehouse-public-safe.png',fullPage:true});
assert.deepEqual(failures,[]);console.log('PASS actual browser → PostgREST 14 → protected invoice save: one write, issue-time account/last receipt in saved and archived PDFs, actual PDF QR scans, safe warehouse copy and anonymous QR without prices.');await ctx.close();await browser.close();
