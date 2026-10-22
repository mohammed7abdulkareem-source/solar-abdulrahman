process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
// Browser → protected RPC → local database. Simulate a lost acknowledgment after commit.
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {salesDocument} from '../app/sales-document.mjs';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base=process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3072',api=process.env.SOLAR_RPC_TEST_URL||'http://127.0.0.1:3078',database=process.env.SOLAR_FIXTURE_DB||'solar_v364_browser';
for(const url of [base,api])assert.match(url,/^http:\/\/(127\.0\.0\.1|localhost):\d+$/);
assert.match(database,/^solar_v\d+_browser$/);
const uid='00000000-0000-0000-0000-000000003631',encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
const raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600});
const token=raw+'.'+createHmac('sha256','solar-local-test-only-signing-secret-347').update(raw).digest('base64url');
const sql=q=>execFileSync('python',['/workspace/solar-review/v359/db.py',database],{input:q,encoding:'utf8'}).trim();
const saleCount=()=>Number(sql(`select count(*) from transactions where kind='sale' and created_by='${uid}';`));
const before=saleCount(),requests=[],failures=[],dir='/workspace/solar-review/v364/browser';await mkdir(dir,{recursive:true});
let committed=null,releaseLostAck;const hold=new Promise(resolve=>{releaseLostAck=resolve;});
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),ctx=await browser.newContext({viewport:{width:390,height:900}});ctx.setDefaultTimeout(20000);
await ctx.addInitScript(({uid,token})=>{
 localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify({access_token:token,refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}}));
 window.__invoiceHtmls=[];window.__saveSounds=[];window.__shares=[];
 const descriptor=Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype,'srcdoc');Object.defineProperty(HTMLIFrameElement.prototype,'srcdoc',{...descriptor,set(value){if(value.includes('class="salesDocument"'))window.__invoiceHtmls.push(value);return descriptor.set.call(this,value);}});
 const Audio=window.AudioContext||window.webkitAudioContext;if(Audio){const create=Audio.prototype.createOscillator;Audio.prototype.createOscillator=function(){const o=create.call(this),start=o.start.bind(o);o.start=(...args)=>{window.__saveSounds.push(performance.now());return start(...args);};return o;};}
 Object.defineProperty(navigator,'canShare',{value:()=>true});Object.defineProperty(navigator,'share',{value:async({files})=>{const f=files[0];window.__shares.push({name:f.name,size:f.size,type:f.type,header:new TextDecoder().decode((await f.arrayBuffer()).slice(0,8))});}});
},{uid,token});
await ctx.routeWebSocket(/supabase/,socket=>socket.close());
await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
 const req=route.request(),url=new URL(req.url());
 if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
 if(url.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:uid,email:'fixture@local.test',aud:'authenticated'})});
 if(url.pathname.startsWith('/rest/v1/')){
  const headers={...req.headers(),authorization:'Bearer '+token};delete headers.host;delete headers.apikey;delete headers.origin;
  const response=await ctx.request.fetch(api+url.pathname.replace('/rest/v1','')+url.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});
  if(url.pathname.endsWith('/solar_invoice_save')){requests.push(JSON.parse(req.postData()));committed=await response.json();assert.equal(response.status(),200,JSON.stringify(committed));if(requests.length===1){await hold;return route.abort('failed');}}
  if(response.status()>=400)failures.push({path:url.pathname,status:response.status(),body:await response.text()});
  return route.fulfill({response});
 }return route.abort();
});
await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
const page=await ctx.newPage();page.on('dialog',d=>d.accept());page.on('pageerror',e=>failures.push(e.message));
const sounds=()=>page.evaluate(()=>window.__saveSounds.length);
async function noOverflow(){assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'horizontal overflow');}
async function ready(scope){const button=scope.getByRole('button',{name:'حفظ PDF',exact:true});await button.waitFor();await page.waitForFunction(el=>!el.disabled,await button.elementHandle(),{timeout:60000});return button;}
await page.goto(base+'/?section=sale');await page.locator('.saleWorkspace').waitFor();
await page.locator('.partySearch input').fill('زبون الوصولات الأصلية');await page.locator('.partySearchResults button').filter({hasText:'زبون الوصولات الأصلية'}).click();
await page.getByLabel('البحث عن مادة',{exact:true}).fill('انفيرتر الوصل الأصلي');await page.getByRole('button',{name:'إضافة انفيرتر الوصل الأصلي',exact:true}).click();
await page.getByLabel('الكمية — انفيرتر الوصل الأصلي').fill('2');await page.getByLabel('سعر البيع — انفيرتر الوصل الأصلي').fill('1500');
await page.getByRole('checkbox',{name:/إضافة ضمان للفاتورة/}).check();await page.getByLabel('مدة ضمان انفيرتر الوصل الأصلي').fill('2');await page.getByLabel('وحدة ضمان انفيرتر الوصل الأصلي').selectOption('years');await page.getByLabel('مدة ضمان الصيانة').fill('6');
assert.equal(await page.getByRole('button',{name:'معاينة',exact:true}).isDisabled(),true);assert.equal(await page.getByRole('button',{name:'حفظ PDF',exact:true}).isDisabled(),true);assert.equal(await page.getByRole('button',{name:'مشاركة',exact:true}).isDisabled(),true);assert.equal(await sounds(),0);
await page.getByRole('button',{name:'حفظ وإرسال للمخزن',exact:true}).evaluate(b=>{b.click();b.click();});
for(let i=0;i<100&&!committed;i++)await new Promise(resolve=>setTimeout(resolve,50));assert.ok(committed);assert.equal(requests.length,1);assert.equal(saleCount(),before+1);assert.equal(await sounds(),0);assert.equal(await page.locator('.invoiceSavedReceipt').count(),0);
releaseLostAck();await page.locator('.workflowError').waitFor();assert.equal(await sounds(),0);assert.equal(await page.getByLabel('الكمية — انفيرتر الوصل الأصلي').inputValue(),'2');assert.equal(await page.locator('.invoiceSavedReceipt').count(),0);
await page.getByRole('button',{name:'حفظ وإرسال للمخزن',exact:true}).click();const saved=page.locator('.invoiceSavedReceipt');await saved.waitFor();await ready(saved);
assert.equal(requests.length,2);assert.equal(requests[0].request_id,requests[1].request_id);assert.deepEqual(requests[0].payload,requests[1].payload);assert.equal(saleCount(),before+1);assert.equal(await sounds(),3);assert.equal(await page.locator('.invoiceWorkspace').count(),0);
await saved.getByRole('heading',{name:'تم حفظ الفاتورة وإرسالها للمخزن',exact:true}).waitFor();assert.equal(committed.invoiceAccount.previousBalance,7500);assert.equal(committed.invoiceAccount.balanceAfter,10500);assert.equal(committed.invoiceAccount.lastPayment.amount,600);
const captured=await page.evaluate(()=>window.__invoiceHtmls.at(-1));await writeFile(dir+'/new-sale.html',captured);
for(const s of ['الحساب السابق','7,500','10,500','آخر تسديد سابق','600','انفيرتر الوصل الأصلي','07700003631','07800003631','invoiceQr'])assert.ok(captured.includes(s),s);assert.ok(!captured.includes('ملخص الحساب وآخر تسديد يظهران بعد حفظ الفاتورة.'));
const r=await ctx.request.post(api+'/rpc/solar_customer_movement',{headers:{authorization:'Bearer '+token},data:{customer_id:-363001,movement_id:committed.id}});assert.equal(r.status(),200);const original=await r.json();
const body=salesDocument({...original.invoice,customer_phone:'07800003631'}).body;
assert.equal(await page.evaluate(({captured,body})=>{const p=new DOMParser();return p.parseFromString(captured,'text/html').querySelector('.salesDocument').outerHTML===p.parseFromString(body,'text/html').querySelector('.salesDocument').outerHTML;},{captured,body}),true,'new receipt matches original stored invoice');
const row=JSON.parse(sql(`select json_build_object('status',warehouse_status,'warehouse',warehouse_id,'items',(select count(*) from transaction_items where transaction_id=t.id),'requests',(select count(*) from solar_private.invoice_requests where request_id='${requests[0].request_id}'),'notifications',(select count(*) from solar_notifications where job_id=t.id and event='warehouse_new')) from transactions t where id=${committed.id};`));assert.equal(row.status,'pending');assert.equal(row.warehouse,1);assert.equal(row.items,1);assert.equal(row.requests,1);assert.ok(row.notifications>0);
const downloadWait=page.waitForEvent('download');await saved.getByRole('button',{name:'حفظ PDF',exact:true}).click();await (await downloadWait).saveAs(dir+'/new-sale.pdf');assert.equal((await readFile(dir+'/new-sale.pdf')).subarray(0,8).toString(),'%PDF-1.4');
await saved.getByRole('button',{name:'مشاركة',exact:true}).click();await saved.getByText('تمت مشاركة ملف PDF.',{exact:true}).waitFor();const shares=await page.evaluate(()=>window.__shares);assert.equal(shares.length,1);assert.equal(shares[0].header,'%PDF-1.4');assert.ok(shares[0].name.includes(String(committed.receiptNo)));
const popupWait=page.waitForEvent('popup');await saved.getByRole('button',{name:'معاينة',exact:true}).click();const popup=await popupWait;await popup.locator('.pdfPage img').first().waitFor();await popup.screenshot({path:dir+'/new-sale-preview.png',fullPage:true});await popup.close();
await noOverflow();await page.screenshot({path:dir+'/saved-receipt-mobile.png',fullPage:false});
await saved.locator('summary').filter({hasText:'نسخة المخزن'}).click();await ready(saved.locator('.invoiceSavedWarehouse'));
const warehouseHtml=await page.evaluate(()=>window.__invoiceHtmls.at(-1));assert.ok(warehouseHtml.includes('انفيرتر الوصل الأصلي'));assert.ok(warehouseHtml.includes('invoiceQr'));assert.ok(!warehouseHtml.includes('الحساب السابق'));assert.ok(!warehouseHtml.includes('10,500'));assert.ok(!warehouseHtml.includes('1,500'));
await page.setViewportSize({width:320,height:800});await noOverflow();await page.screenshot({path:dir+'/saved-receipt-320px.png',fullPage:false});await page.setViewportSize({width:1024,height:768});await noOverflow();await page.screenshot({path:dir+'/saved-receipt-tablet.png',fullPage:false});
assert.equal(await sounds(),3);assert.equal(saleCount(),before+1);assert.equal(requests.length,2);
await saved.getByRole('button',{name:'فاتورة جديدة',exact:true}).click();await page.locator('.saleWorkspace').waitFor();assert.equal(await page.locator('.invoiceSavedReceipt').count(),0);assert.equal(await page.locator('.deskTable tbody tr').count(),0);assert.equal(await page.getByRole('button',{name:'حفظ PDF',exact:true}).isDisabled(),true);assert.equal(await page.locator('.partySearch input').inputValue(),'');
await page.getByRole('button',{name:'حفظ وإرسال للمخزن',exact:true}).click();await page.locator('.workflowError').waitFor();assert.equal(requests.length,2);assert.equal(await sounds(),3);
assert.deepEqual(failures,[]);
const result={ok:true,requests:requests.length,committedInvoices:1,sameRequestId:true,originalInvoiceMatches:true,soundNotes:await sounds(),notificationCount:row.notifications,pdfShared:shares[0],productionWriteRequests:0};await writeFile(dir+'/results.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result));await ctx.close();await browser.close();
