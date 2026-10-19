process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
// All application REST calls go to real local PostgREST, never production data.
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {mkdir} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base=process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3053',api=process.env.SOLAR_RPC_TEST_URL||'http://127.0.0.1:3054';
for(const url of [base,api])assert.match(url,/^http:\/\/(127\.0\.0\.1|localhost):\d+$/);
const ids={admin:'00000000-0000-0000-0000-000000003500',main:'00000000-0000-0000-0000-000000003502',sayada:'00000000-0000-0000-0000-000000003503'},secret='solar-local-test-only-signing-secret-347';
const encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
function session(uid){const raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600});return {access_token:raw+'.'+createHmac('sha256',secret).update(raw).digest('base64url'),refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}};}
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),contexts=[],failures=[],saved=[];
const dir='/workspace/solar-review/v350/browser';await mkdir(dir,{recursive:true});
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
try{
 const admin=await open('admin');await section(admin.page,'stock');await admin.page.locator('.inventoryRows article').first().waitFor();await noOverflow(admin.page);
 await admin.page.getByRole('button',{name:'نقل مواد',exact:true}).click();const dest=admin.page.getByLabel('إلى مخزن',{exact:true});await dest.locator('option').filter({hasText:'مخزن صيادة'}).waitFor({state:'attached'});await dest.selectOption({label:'مخزن صيادة'});
 await admin.page.locator('.inventoryPickList button').filter({hasText:'بطارية 10KW'}).click();await admin.page.getByLabel('كمية نقل بطارية 10KW').fill('3');
 await admin.page.locator('.inventoryPickList button').filter({hasText:'محولة 6KW'}).click();await admin.page.getByLabel('كمية نقل محولة 6KW').fill('2');await noOverflow(admin.page);
 await admin.page.screenshot({path:dir+'/transfer-mobile.png',fullPage:true});await admin.page.getByRole('button',{name:'تأكيد نقل المواد',exact:true}).click();await admin.page.locator('.inventoryTransferReceipt').waitFor();await admin.page.locator('.inventoryReceiptHead').first().click();await admin.page.getByText('كلفة مثبتة: 100,000 د.ع للوحدة',{exact:true}).waitFor();
 await admin.page.getByRole('button',{name:'الأرصدة',exact:true}).click();await admin.page.getByLabel('عرض رصيد المخزن').selectOption({label:'مخزن صيادة'});await admin.page.locator('.inventoryRows article').filter({hasText:'بطارية 10KW'}).locator('strong').filter({hasText:/^3$/}).waitFor();await admin.page.screenshot({path:dir+'/sayada-balances-mobile.png',fullPage:true});
 await section(admin.page,'purchase');await admin.page.getByLabel('مخزن استلام المشتريات').selectOption({label:'مخزن صيادة'});await party(admin.page,'مورد الدولار');await admin.page.getByLabel('عملة الشراء').selectOption('USD');await admin.page.getByLabel('صرف فاتورة الشراء').fill('1660');await add(admin.page,'بطارية 10KW','2','1.25');assert.equal(await admin.page.getByLabel('سعر الشراء — بطارية 10KW').inputValue(),'1.25');
 const purchase=admin.page.waitForResponse(r=>r.url().endsWith('/rpc/solar_invoice_save')&&r.status()===200);await admin.page.getByRole('button',{name:'حفظ الوصل',exact:true}).click();const purchaseData=await(await purchase).json();assert.equal(purchaseData.warehouseName,'مخزن صيادة');
 await section(admin.page,'sale');await admin.page.getByLabel('مخزن تجهيز الفاتورة').selectOption({label:'مخزن صيادة'});await party(admin.page,'زبون تجريبي جملة');await add(admin.page,'بطارية 10KW','1','200000');await admin.page.getByRole('checkbox',{name:/إضافة ضمان للفاتورة/}).check();await admin.page.getByLabel('مدة ضمان بطارية 10KW').fill('2');await admin.page.getByLabel('وحدة ضمان بطارية 10KW').selectOption('years');await admin.page.getByLabel('مدة ضمان الصيانة').fill('6');
 await admin.page.getByRole('button',{name:'حفظ الوصل',exact:true}).click();await admin.page.locator('.warrantySaved').waitFor();assert.equal(saved.at(-1).warehouseName,'مخزن صيادة');assert.ok(saved.at(-1).invoiceAccount);assert.ok(saved.at(-1).warrantyToken);await noOverflow(admin.page);
 await section(admin.page,'system');await admin.page.getByLabel('مخزن تجهيز المنظومة').selectOption({label:'مخزن صيادة'});await party(admin.page,'زبون منظومة');await admin.page.getByLabel('مهندس التنصيب',{exact:true}).selectOption({label:'Engineer'});await admin.page.getByLabel('عنوان التنصيب').fill('صيادة — عنوان فحص');await add(admin.page,'محولة 6KW','1');await admin.page.getByLabel('سعر بيع المنظومة',{exact:true}).fill('800000');await admin.page.getByRole('button',{name:'حفظ المنظومة وإسناد التنصيب',exact:true}).click();await admin.page.locator('.warrantySaved').waitFor();assert.equal(saved.at(-1).warehouseName,'مخزن صيادة');
 const main=await open('main');await section(main.page,'warehouse');await main.page.locator('.warehouseEmpty').waitFor();assert.equal(await main.page.locator('.warehouseOrder').count(),0);assert.equal(await main.page.getByLabel('مخزن التجهيز').locator('option').filter({hasText:'مخزن صيادة'}).count(),0);
 const preparer=await open('sayada');await section(preparer.page,'warehouse');await preparer.page.waitForFunction(()=>document.querySelectorAll('.warehouseOrder').length===2);for(const row of await preparer.page.locator('.warehouseOrder').all())assert.ok((await row.innerText()).includes('مخزن صيادة'));assert.ok(!(await preparer.page.locator('body').innerText()).includes('200,000'));await noOverflow(preparer.page);await preparer.page.screenshot({path:dir+'/sayada-queue-mobile.png',fullPage:true});
 await preparer.page.locator('.warehouseOrder').first().getByRole('button',{name:'تم التجهيز ✓',exact:true}).click();await preparer.page.waitForFunction(()=>document.querySelectorAll('.warehouseOrder').length===1);await section(preparer.page,'stock');await preparer.page.locator('.inventoryRows article').first().waitFor();assert.equal(await preparer.page.getByLabel('عرض رصيد المخزن').locator('option').filter({hasText:'المخزن الرئيسي'}).count(),0);assert.equal(await preparer.page.getByText('إظهار الكلفة',{exact:true}).count(),0);
 await section(admin.page,'stock');await admin.page.getByRole('button',{name:'إدارة المخازن',exact:true}).click();await admin.page.getByLabel('مستخدم صلاحيات المخازن').selectOption(ids.main);await admin.page.getByRole('radio',{name:'جميع المخازن الحالية والمستقبلية'}).check();await admin.page.getByRole('checkbox',{name:'السماح بنقل المواد بين مخازنه'}).check();await admin.page.getByRole('button',{name:'حفظ صلاحيات المخازن',exact:true}).click();await admin.page.getByRole('status').filter({hasText:'تم حفظ مخازن المستخدم'}).waitFor();
 await section(main.page,'warehouse');await main.page.locator('.warehouseOrder').waitFor();await main.page.getByLabel('مخزن التجهيز').selectOption({label:'مخزن صيادة'});await main.page.locator('.warehouseOrder').waitFor();
 await admin.page.setViewportSize({width:1366,height:900});await section(admin.page,'stock');await admin.page.locator('.inventoryRows article').first().waitFor();await noOverflow(admin.page);await admin.page.screenshot({path:dir+'/inventory-desktop.png',fullPage:true});await admin.page.getByRole('button',{name:'إدارة المخازن',exact:true}).click();await admin.page.getByLabel('مستخدم صلاحيات المخازن').selectOption(ids.main);await noOverflow(admin.page);await admin.page.screenshot({path:dir+'/warehouse-access-desktop.png',fullPage:true});
 const response=await admin.ctx.request.post(api+'/rpc/solar_inventory',{headers:admin.headers,data:{action:'stock',payload:{}}});assert.equal(response.status(),200);const data=await response.json();const battery=data.products.find(p=>p.id===-350001);assert.equal(battery.qty,21);assert.ok(Math.abs(battery.cost-91097.727273)<0.00001);assert.equal(saved.length,3);
 assert.deepEqual(failures,[]);console.log('PASS real browser + PostgREST: multi-line transfer, frozen cost, USD fractional purchase in Sayada, wholesale warranty, system warehouse, two-order fulfillment, Main/Sayada permissions, admin all-warehouse grant, mobile and desktop without overflow.');
}catch(error){console.error('API failures:',failures);for(const [n,ctx] of contexts.entries()){const p=ctx.pages()[0];if(p)await p.screenshot({path:dir+'/failure-'+n+'.png',fullPage:true}).catch(()=>{});}throw error;}
finally{for(const ctx of contexts)await ctx.close();await browser.close();}
