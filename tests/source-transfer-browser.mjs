process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
// All application REST calls go to real local PostgREST, never production data.
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {mkdir} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base=process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3053',api=process.env.SOLAR_RPC_TEST_URL||'http://127.0.0.1:3054';
for(const url of [base,api])assert.match(url,/^http:\/\/(127\.0\.0\.1|localhost):\d+$/);
const ids={seller:'00000000-0000-0000-0000-000000003501',admin:'00000000-0000-0000-0000-000000003500',main:'00000000-0000-0000-0000-000000003502',sayada:'00000000-0000-0000-0000-000000003503'},secret='solar-local-test-only-signing-secret-347';
const encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
function session(uid){const raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600});return {access_token:raw+'.'+createHmac('sha256',secret).update(raw).digest('base64url'),refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}};}
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),contexts=[],failures=[],saved=[];
const dir='/workspace/solar-review/v351/browser';await mkdir(dir,{recursive:true});
async function open(name,width=390){
 const auth=session(ids[name]),ctx=await browser.newContext({viewport:{width,height:900}});contexts.push(ctx);ctx.setDefaultTimeout(20000);
 await ctx.addInitScript(({auth})=>localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify(auth)),{auth});await ctx.routeWebSocket(/supabase/,socket=>socket.close());
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),url=new URL(req.url());
  if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
  if(url.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:ids[name],email:'fixture@local.test',aud:'authenticated'})});
  if(url.pathname.startsWith('/rest/v1/')){
   const headers={...req.headers()};delete headers.host;delete headers.apikey;delete headers.origin;
   const response=await ctx.request.fetch(api+url.pathname.replace('/rest/v1','')+url.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});
   if(response.status()>=400)failures.push({path:url.pathname,status:response.status(),body:await response.json()});
   if(url.pathname.endsWith('/solar_invoice_save')&&response.status()===200)saved.push(await response.json());
   return route.fulfill({response});
  }
  return route.abort();
 });
 await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const page=await ctx.newPage();page.on('pageerror',e=>failures.push(e.message));page.on('dialog',d=>d.accept());
 return {ctx,page,headers:{authorization:'Bearer '+auth.access_token}};
}
async function section(page,name){await page.goto(base+'/?section='+name);}
async function noOverflow(page){assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth+1),'horizontal overflow');}
async function party(page,name){await page.locator('.partySearch input').fill(name);await page.locator('.partySearchResults button').filter({hasText:name}).click();}
async function add(page,name,qty,price){await page.getByLabel('البحث عن مادة',{exact:true}).fill(name);await page.getByRole('button',{name:'إضافة '+name,exact:true}).click();await page.getByLabel('الكمية — '+name).fill(qty);if(price)await page.getByLabel(/سعر (البيع|الشراء) —/).fill(price);}
async function apiRead(ctx,action,payload={}){const response=await ctx.ctx.request.post(api+'/rpc/solar_inventory',{headers:ctx.headers,data:{action,payload}});assert.equal(response.status(),200,await response.text());return response.json();}
try{
 const admin=await open('admin');await section(admin.page,'stock');await admin.page.locator('.inventoryRows article').first().waitFor();
 const context=await apiRead(admin,'context'),primary=context.warehouses.find(w=>w.primary),secondary=context.warehouses.find(w=>!w.primary);
 await admin.page.getByRole('button',{name:'إدارة المخازن',exact:true}).click();await admin.page.getByLabel('مستخدم صلاحيات المخازن').selectOption(ids.seller);await admin.page.getByRole('radio',{name:'جميع المخازن الحالية والمستقبلية'}).check();await admin.page.getByRole('checkbox',{name:'من المخزن الرئيسي إلى المخازن الأخرى',exact:true}).check();await admin.page.getByRole('button',{name:'حفظ صلاحيات المخازن',exact:true}).click();await admin.page.getByRole('status').filter({hasText:'تم حفظ مخازن المستخدم'}).waitFor();
 await admin.page.screenshot({path:dir+'/direction-permissions-mobile.png',fullPage:true});
 const seller=await open('seller');await section(seller.page,'stock');await seller.page.getByRole('button',{name:'نقل مواد',exact:true}).click();await seller.page.getByLabel('من مخزن',{exact:true}).locator('option').filter({hasText:primary.name}).waitFor({state:'attached'});
 assert.equal(await seller.page.getByLabel('من مخزن',{exact:true}).locator('option').filter({hasText:secondary.name}).count(),0);await seller.page.getByLabel('إلى مخزن',{exact:true}).selectOption(String(secondary.id));
 await seller.page.locator('.inventoryPickList button').filter({hasText:'بطارية 10KW'}).click();await seller.page.getByLabel('كمية نقل بطارية 10KW').fill('20');await seller.page.getByRole('button',{name:'إرسال طلب النقل للتجهيز',exact:true}).click();await seller.page.locator('.inventoryTransferReceipt').waitFor();await seller.page.getByText('بانتظار التجهيز',{exact:true}).waitFor();
 const outgoing=(await apiRead(seller,'transfers'))[0];assert.equal(outgoing.status,'pending');let stock=await apiRead(admin,'stock',{warehouseId:secondary.id});assert.equal(stock.products.find(p=>p.id===-350001).qty,0);
 stock=await apiRead(admin,'stock',{warehouseId:primary.id});assert.equal(stock.products.find(p=>p.id===-350001).qty,0);assert.equal(stock.products.find(p=>p.id===-350001).reservedQty,20);assert.equal(stock.products.find(p=>p.id===-350001).bookQty,20);
 await section(admin.page,'stock');await admin.page.getByLabel('عرض رصيد المخزن').selectOption(String(primary.id));await admin.page.locator('.inventoryRows article').filter({hasText:'بطارية 10KW'}).getByText('محجوز للنقل: 20',{exact:true}).waitFor();await admin.page.getByRole('checkbox',{name:'إظهار الكلفة',exact:true}).check();assert.ok((await admin.page.locator('.inventoryMetrics').innerText()).includes('4,000,000'));await admin.page.screenshot({path:dir+'/fully-reserved-capital-mobile.png',fullPage:true});
 const main=await open('main');await section(main.page,'warehouse');await main.page.locator('.sourceTransferOrder').waitFor();assert.ok((await main.page.locator('.sourceTransferOrder').innerText()).includes(primary.name));assert.ok(!(await main.page.locator('.sourceTransferOrder').innerText()).includes('100,000'));await noOverflow(main.page);await main.page.screenshot({path:dir+'/main-pending-mobile.png',fullPage:true});
 await main.page.getByRole('button',{name:'فتح الإشعارات',exact:true}).click();await main.page.locator('.notificationList button').filter({hasText:'طلب نقل جديد'}).first().click();await main.page.locator('.sourceTransferOrder.highlighted').waitFor();assert.equal(await main.page.locator('.sourceTransferOrder').count(),1);
 await main.page.getByRole('button',{name:'تأكيد تجهيز النقل',exact:true}).click();await main.page.getByRole('status').filter({hasText:'تم تجهيز النقل وإضافة الكميات'}).waitFor();
 assert.equal((await apiRead(admin,'stock',{warehouseId:secondary.id})).products.find(p=>p.id===-350001).qty,20);assert.equal((await apiRead(admin,'stock',{warehouseId:primary.id})).products.find(p=>p.id===-350001).qty,0);
 await seller.page.getByRole('button',{name:'فتح الإشعارات',exact:true}).click();await seller.page.locator('.notificationList button').filter({hasText:'تم تجهيز النقل'}).first().click();await seller.page.locator('.inventoryReceiptDetails').waitFor();assert.ok((await seller.page.locator('.inventoryReceiptDetails').innerText()).includes('جهّزها Main preparer'));
 await section(admin.page,'stock');await admin.page.getByRole('button',{name:'إدارة المخازن',exact:true}).click();await admin.page.getByLabel('مستخدم صلاحيات المخازن').selectOption(ids.seller);await admin.page.getByRole('checkbox',{name:'من المخزن الرئيسي إلى المخازن الأخرى',exact:true}).uncheck();await admin.page.getByRole('checkbox',{name:'من المخازن الأخرى إلى المخزن الرئيسي',exact:true}).check();await admin.page.getByRole('button',{name:'حفظ صلاحيات المخازن',exact:true}).click();await admin.page.getByRole('status').filter({hasText:'تم حفظ مخازن المستخدم'}).waitFor();
 await section(seller.page,'stock');await seller.page.getByRole('button',{name:'نقل مواد',exact:true}).click();await seller.page.waitForFunction(id=>document.querySelector('select[aria-label="من مخزن"]')?.value===String(id),secondary.id);assert.equal(await seller.page.getByLabel('من مخزن',{exact:true}).locator('option').filter({hasText:primary.name}).count(),0);await seller.page.getByLabel('إلى مخزن',{exact:true}).selectOption(String(primary.id));await seller.page.locator('.inventoryPickList button').filter({hasText:'بطارية 10KW'}).click();await seller.page.getByLabel('كمية نقل بطارية 10KW').fill('1');await seller.page.getByRole('button',{name:'إرسال طلب النقل للتجهيز',exact:true}).click();await seller.page.locator('.inventoryTransferReceipt').first().waitFor();const returning=(await apiRead(seller,'transfers')).find(t=>t.fromId===secondary.id);assert.equal(returning.status,'pending');
 const noPermission=await main.ctx.request.post(api+'/rpc/solar_inventory',{headers:main.headers,data:{action:'transfer_get',payload:{id:returning.id}}});assert.equal(noPermission.status(),403);
 await section(main.page,'warehouse');await main.page.getByRole('button',{name:/طلبات نقل المخازن/}).click();await main.page.locator('.warehouseTransferQueue .warehouseQueueTabs button').last().click();await main.page.locator('.sourceTransferOrder').waitFor();assert.equal(await main.page.locator('.sourceTransferOrder').count(),1);assert.ok((await main.page.locator('.sourceTransferOrder').innerText()).includes('#'+outgoing.receiptNo));
 const sayada=await open('sayada');await section(sayada.page,'warehouse');await sayada.page.locator('.sourceTransferOrder').waitFor();assert.ok((await sayada.page.locator('.sourceTransferOrder').innerText()).includes('#'+returning.receiptNo));await sayada.page.setViewportSize({width:1366,height:900});await noOverflow(sayada.page);await sayada.page.screenshot({path:dir+'/sayada-source-desktop.png',fullPage:true});await sayada.page.getByRole('button',{name:'تأكيد تجهيز النقل',exact:true}).click();await sayada.page.getByRole('status').filter({hasText:'تم تجهيز النقل وإضافة الكميات'}).waitFor();
 stock=await apiRead(admin,'stock',{warehouseId:primary.id});assert.equal(stock.products.find(p=>p.id===-350001).qty,1);assert.equal(stock.products.find(p=>p.id===-350001).reservedQty,0);assert.equal((await apiRead(admin,'stock',{warehouseId:secondary.id})).products.find(p=>p.id===-350001).qty,19);assert.equal((await apiRead(admin,'catalog')).find(p=>p.id===-350001).companyQty,20);
 assert.deepEqual(failures,[]);console.log('PASS real browser/PostgREST: per-direction user permissions; source request reservation; Ahmad/Main-only queue and notices; one preparation credits destination; reverse direction appears only to Sayada; safe notification links; mobile and desktop.');
}catch(error){console.error('API failures:',failures);for(const [n,ctx] of contexts.entries()){const page=ctx.pages()[0];if(page)await page.screenshot({path:dir+'/failure-'+n+'.png',fullPage:true}).catch(()=>{});}throw error;}
finally{for(const ctx of contexts){await ctx.unrouteAll({behavior:'ignoreErrors'});await ctx.close();}await browser.close();}
