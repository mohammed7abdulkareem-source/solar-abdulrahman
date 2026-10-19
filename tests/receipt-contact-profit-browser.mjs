process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
// All application REST calls go to real local PostgREST, never production data.
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {mkdir} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base=process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3053',api=process.env.SOLAR_RPC_TEST_URL||'http://127.0.0.1:3054';
for(const url of [base,api])assert.match(url,/^http:\/\/(127\.0\.0\.1|localhost):\d+$/);
const ids={seller:'00000000-0000-0000-0000-000000003501',admin:'00000000-0000-0000-0000-000000003500',main:'00000000-0000-0000-0000-000000003502',sayada:'00000000-0000-0000-0000-000000003503',recipient:'00000000-0000-0000-0000-000000003504'},secret='solar-local-test-only-signing-secret-347';
const encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
function session(uid){const raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600});return {access_token:raw+'.'+createHmac('sha256',secret).update(raw).digest('base64url'),refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}};}
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),contexts=[],failures=[],saved=[];
const dir='/workspace/solar-review/v352/browser';await mkdir(dir,{recursive:true});
async function open(name,width=390){
 const auth=session(ids[name]),ctx=await browser.newContext({viewport:{width,height:900}});contexts.push(ctx);ctx.setDefaultTimeout(20000);
 await ctx.addInitScript(({auth})=>localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify(auth)),{auth});await ctx.routeWebSocket(/supabase/,socket=>socket.close());
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),url=new URL(req.url());
  if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
  if(url.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:ids[name],email:'fixture@local.test',aud:'authenticated'})});
  if(url.pathname.includes('/functions/v1/solar-admin-users')){const response=await ctx.request.get(api+'/profiles?select=*',{headers:{authorization:'Bearer '+auth.access_token}});return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({users:await response.json()})});}
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
async function rpc(who,name,data){const r=await who.ctx.request.post(api+'/rpc/'+name,{headers:who.headers,data});assert.equal(r.status(),200,await r.text());return r.json();}
try{
 const seller=await open('seller');await section(seller.page,'profit');await seller.page.getByLabel('رقم هاتفي للوصولات').fill('٠٧٧٠ ١٢٣ ٤٥٦٧');await seller.page.getByRole('button',{name:'حفظ رقم الهاتف',exact:true}).click();await seller.page.locator('.staffProfitRows .profitMovement').first().waitFor();
 const oldRows=await rpc(seller,'solar_profit_workspace',{action:'overview'});assert.equal(oldRows.rows.length,2);const firstId=oldRows.rows[0].key.slice(3),secondId=oldRows.rows[1].key.slice(3);
 const movement=seller.page.locator('.staffProfitRows .profitMovement').first();await movement.locator('summary').click();await movement.getByText('بطارية 10KW',{exact:true}).waitFor();assert.match(await movement.innerText(),/07701234567/);await noOverflow(seller.page);await seller.page.screenshot({path:dir+'/own-invoice-details-mobile.png',fullPage:true});
 const popupPromise=seller.page.waitForEvent('popup');await movement.getByRole('button',{name:'معاينة',exact:true}).click();const popup=await popupPromise;await popup.locator('.pdfPage img').first().waitFor();await popup.screenshot({path:dir+'/invoice-pdf-mobile.png',fullPage:true});await popup.close();
 await section(seller.page,'sale');await seller.page.getByLabel('البحث عن مادة',{exact:true}).fill('');await seller.page.getByLabel('البحث عن مادة',{exact:true}).focus();await seller.page.getByRole('button',{name:'إضافة بطارية 10KW',exact:true}).waitFor();assert.equal(await seller.page.getByRole('button',{name:'إضافة مادة صفرية',exact:true}).count(),0);assert.equal(await seller.page.getByRole('button',{name:'إضافة محولة 6KW',exact:true}).count(),0);
 await seller.page.getByLabel('البحث عن مادة',{exact:true}).fill('مادة صفرية');await seller.page.getByText('لا توجد مواد متوفرة مطابقة في المخزن المختار',{exact:true}).waitFor();await seller.page.screenshot({path:dir+'/only-available-search-mobile.png',fullPage:true});
 await party(seller.page,'زبون تجريبي جملة');await add(seller.page,'بطارية 10KW','1','150000');await seller.page.getByRole('button',{name:'حفظ الوصل',exact:true}).click();await seller.page.locator('.warrantySaved').waitFor();assert.equal(saved.at(-1).creatorPhone,'07701234567');
 await section(seller.page,'customerPayment');await seller.page.locator('.accountPicker input').fill('زبون تجريبي');await seller.page.locator('.accountPickerResults button').first().click();await seller.page.getByLabel('مبلغ حركة الجملة').fill('50000');await seller.page.getByRole('button',{name:'حفظ التسديد',exact:true}).click();await seller.page.locator('.supplierMovementSaved').waitFor();
 const admin=await open('admin');await section(admin.page,'profit');await admin.page.getByRole('button',{name:'تحويل الأرباح لمستخدم آخر',exact:true}).click();await admin.page.getByRole('checkbox',{name:'تحويل ربح الفاتورة 1',exact:true}).check();await admin.page.getByRole('checkbox',{name:'تحويل ربح الفاتورة 2',exact:true}).check();await admin.page.getByLabel('المستخدم المستفيد من الربح').selectOption(ids.recipient);await admin.page.getByRole('button',{name:'معاينة التغيير',exact:true}).click();await admin.page.locator('.profitTransferPreview').waitFor();assert.match(await admin.page.locator('.profitTransferPreview').innerText(),/100,000/);await noOverflow(admin.page);await admin.page.screenshot({path:dir+'/transfer-preview-mobile.png',fullPage:true});await admin.page.getByRole('button',{name:'تأكيد حفظ التغيير',exact:true}).click();await admin.page.getByRole('status').filter({hasText:'تم حفظ تغيير الأرباح'}).waitFor();
 const assignment=await rpc(admin,'solar_profit_transfer',{action:'list'});assert.equal(assignment.assignments.length,2);assert.ok(assignment.assignments.every(r=>r.ownerId===ids.recipient));
 const original=await admin.ctx.request.get(api+'/transactions?select=id,created_by,cashbox_user_id,profit&id=in.('+firstId+','+secondId+')',{headers:admin.headers});const originalRows=await original.json();assert.ok(originalRows.every(r=>r.created_by===ids.seller&&r.cashbox_user_id===ids.seller&&Number(r.profit)===50000));
 await admin.page.getByLabel('مستخدم تقرير الأرباح').selectOption(ids.recipient);await admin.page.locator('.profitList .profitMovement').first().locator('summary').click();await admin.page.locator('.profitMovementAuthor').getByText('Multi Seller',{exact:false}).waitFor();assert.match(await admin.page.locator('.profitMovementAuthor').innerText(),/07701234567/);await admin.page.setViewportSize({width:1366,height:900});await noOverflow(admin.page);await admin.page.screenshot({path:dir+'/admin-original-author-desktop.png',fullPage:true});
 const recipient=await open('recipient');await section(recipient.page,'profit');await recipient.page.locator('.staffProfitRows .profitMovement').first().waitFor();assert.equal(await recipient.page.locator('.staffProfitRows .profitMovement').count(),2);assert.ok(!(await recipient.page.locator('.staffProfitRows').innerText()).includes('زبون تجريبي'));await recipient.page.locator('.staffProfitRows .profitMovement').first().locator('summary').click();await recipient.page.getByText('ربح محوّل لك من الإدارة. تفاصيل الوصل محفوظة عند صاحبه الأصلي.',{exact:true}).waitFor();assert.equal(await recipient.page.locator('.profitMovementTable').count(),0);await noOverflow(recipient.page);await recipient.page.screenshot({path:dir+'/recipient-redacted-profit-mobile.png',fullPage:true});
 await section(seller.page,'profit');await seller.page.locator('.staffProfitRows .profitMovement').first().waitFor();assert.equal(await seller.page.locator('.staffProfitRows .profitMovement').count(),1);const denied=await recipient.ctx.request.post(api+'/rpc/solar_profit_transfer',{headers:recipient.headers,data:{action:'list'}});assert.equal(denied.status(),403);
 await section(admin.page,'purchase');await admin.page.getByLabel('البحث عن مادة',{exact:true}).fill('مادة صفرية');await admin.page.getByRole('button',{name:'إضافة مادة صفرية',exact:true}).waitFor();
 await section(seller.page,'system');await seller.page.getByLabel('البحث عن مادة',{exact:true}).fill('مادة صفرية');await seller.page.getByText('لا توجد مواد متوفرة مطابقة في المخزن المختار',{exact:true}).waitFor();
 assert.deepEqual(failures,[]);console.log('PASS real browser/PostgREST: first-login phone and old/new customer receipts; readable profit arrows/PDF; only free warehouse stock in sale/system search; zero stock remains purchasable; admin batch preview/save; original invoice author/cash preserved; recipient profit redacted; mobile and desktop.');
}catch(error){console.error('API failures:',failures);for(const [n,ctx] of contexts.entries()){const page=ctx.pages()[0];if(page)await page.screenshot({path:dir+'/failure-'+n+'.png',fullPage:true}).catch(()=>{});}throw error;}
finally{for(const ctx of contexts){await ctx.unrouteAll({behavior:'ignoreErrors'});await ctx.close();}await browser.close();}
