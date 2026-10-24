process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base=process.env.SOLAR_TEST_BASE||'http://127.0.0.1:3073',api=process.env.SOLAR_TEST_API||'http://127.0.0.1:3079',dir='/workspace/solar-review/v369/browser';await mkdir(dir,{recursive:true});
const ids={admin:'00000000-0000-0000-0000-000000003690',owner:'00000000-0000-0000-0000-000000003691'},encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),contexts=[],errors=[],saves=[];
let race=false,loseAck=false,admin,revision=2,rate=1800,lostRequest=null;
async function updateRate(next){const r=await admin.ctx.request.post(api+'/rpc/solar_exchange_rate_set',{headers:{authorization:'Bearer '+admin.token},data:{rate:next,expected_revision:revision}});assert.equal(r.status(),200,await r.text());const result=await r.json();revision=result.revision;rate=result.rate;}
async function open(who,section){const uid=ids[who],raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600}),token=raw+'.'+createHmac('sha256','solar-local-test-only-signing-secret-347').update(raw).digest('base64url');
 const ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true});contexts.push(ctx);ctx.setDefaultTimeout(20000);
 await ctx.addInitScript(({uid,token})=>localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify({access_token:token,refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}})),{uid,token});
 await ctx.routeWebSocket(/supabase/,socket=>socket.close());
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),u=new URL(req.url());
  if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
  if(u.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:uid,email:'fixture@local.test',aud:'authenticated'})});
  if(!u.pathname.startsWith('/rest/v1/'))return route.abort();
  const saving=u.pathname.endsWith('/solar_invoice_save');
  if(saving&&race){race=false;await updateRate(2000);}
  const headers={...req.headers(),authorization:'Bearer '+token};delete headers.apikey;delete headers.host;delete headers.origin;
  const r=await ctx.request.fetch(api+u.pathname.replace('/rest/v1','')+u.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined}),body=await r.text();
  if(saving){saves.push({status:r.status(),payload:JSON.parse(req.postData()),body:JSON.parse(body)});if(loseAck&&r.status()===200){loseAck=false;lostRequest=saves.at(-1);await updateRate(2100);return route.abort('failed');}}
  if(r.status()>=400&&!(saving&&r.status()===409))errors.push({path:u.pathname,status:r.status(),body});
  return route.fulfill({response:r,body});
 });
 await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const page=await ctx.newPage();page.on('dialog',d=>d.accept());page.on('pageerror',e=>errors.push(e.message));await page.goto(base+'/?section='+section);return {ctx,page,token};
}
try{
 admin=await open('admin','exchangeRate');await admin.page.getByLabel('سعر الصرف',{exact:true}).waitFor();
 const owner=await open('owner','sale'),page=owner.page;
 async function fillSale(){await page.getByRole('combobox',{name:'ابحث عن الزبون بالاسم أو الهاتف…'}).fill('عميل الصرف');await page.getByRole('option',{name:'عميل الصرف'}).click();await page.getByLabel('البحث عن مادة',{exact:true}).fill('انفيرتر');await page.getByRole('button',{name:'إضافة انفيرتر دولار',exact:true}).click();await page.getByLabel('الكمية — انفيرتر دولار',{exact:true}).fill('2');await page.getByLabel('سعر البيع — انفيرتر دولار',{exact:true}).fill('250000');}
 await fillSale();assert.match(await page.locator('.deskUnitCost').innerText(),/180,100/);
 await admin.page.getByLabel('سعر الصرف',{exact:true}).fill('1900');await admin.page.getByRole('button',{name:'حفظ سعر الصرف',exact:true}).click();await admin.page.getByRole('status').filter({hasText:'تم حفظ الصرف'}).waitFor();revision=3;rate=1900;
 await page.waitForFunction(()=>document.querySelector('.deskUnitCost')?.textContent.includes('190,100'),null,{timeout:17000});
 assert.equal(await page.getByLabel('الكمية — انفيرتر دولار',{exact:true}).inputValue(),'2');assert.equal(await page.getByLabel('سعر البيع — انفيرتر دولار',{exact:true}).inputValue(),'250,000');
 await page.screenshot({path:dir+'/live-fx-sale.png',fullPage:true});
 await page.getByRole('button',{name:'حفظ وإرسال للمخزن',exact:true}).click();await page.locator('.invoiceSavedReceipt').waitFor();assert.equal(saves.at(-1).body.cost,380200);assert.equal(saves.at(-1).body.profit,119800);assert.equal(saves.at(-1).payload.payload.valuationRevision,3);
 const first=saves.at(-1).body;
 await page.getByRole('button',{name:'فاتورة جديدة',exact:true}).click();await fillSale();race=true;await page.getByRole('button',{name:'حفظ وإرسال للمخزن',exact:true}).click();await page.locator('.workflowError').filter({hasText:'تغير سعر الصرف'}).waitFor();await page.waitForFunction(()=>document.querySelector('.deskUnitCost')?.textContent.includes('200,100'));
 assert.equal(await page.getByLabel('الكمية — انفيرتر دولار',{exact:true}).inputValue(),'2');assert.equal(saves.at(-1).status,409);
 await page.getByRole('button',{name:'حفظ وإرسال للمخزن',exact:true}).click();await page.locator('.invoiceSavedReceipt').waitFor();assert.equal(saves.at(-1).body.cost,400200);assert.equal(saves.at(-1).body.profit,99800);
 await page.getByRole('button',{name:'فاتورة جديدة',exact:true}).click();await fillSale();loseAck=true;await page.getByRole('button',{name:'حفظ وإرسال للمخزن',exact:true}).click();await page.locator('.workflowError').waitFor();
 await page.waitForFunction(()=>document.querySelector('.deskUnitCost')?.textContent.includes('210,100'),null,{timeout:17000});
 await page.waitForLoadState('networkidle');
 await page.getByRole('button',{name:'حفظ وإرسال للمخزن',exact:true}).click();await page.locator('.invoiceSavedReceipt').waitFor();
 assert.deepEqual(saves.at(-1).payload,lostRequest.payload);assert.deepEqual(saves.at(-1).body,lostRequest.body);assert.equal(saves.at(-1).body.cost,400200);
 const tx=await owner.ctx.request.get(api+'/transactions?select=id,kind,cost,profit&id=eq.'+first.id,{headers:{authorization:'Bearer '+owner.token}});assert.equal((await tx.json())[0].cost,380200);
 await page.screenshot({path:dir+'/confirmed-sale.png',fullPage:true});
 await page.goto(base+'/?section=system');await page.getByLabel('البحث عن مادة',{exact:true}).fill('انفيرتر');await page.getByRole('button',{name:'إضافة انفيرتر دولار',exact:true}).click();await page.getByLabel('الكمية — انفيرتر دولار',{exact:true}).fill('1');await page.getByLabel('سعر بيع المنظومة',{exact:true}).fill('300000');if(await page.getByRole('button',{name:'تفاصيل المجموع',exact:true}).isVisible())await page.getByRole('button',{name:'تفاصيل المجموع',exact:true}).click();
 assert.match(await page.locator('[data-summary-label="كلفة المواد"]').innerText(),/210,100/);assert.match(await page.locator('[data-summary-label="الربح الصافي"]').innerText(),/89,900/);await page.screenshot({path:dir+'/system-current-profit.png',fullPage:true});
 assert.deepEqual(errors,[]);await writeFile(dir+'/results.json',JSON.stringify({pass:true,saves,errors,rate,revision},null,2));console.log('PASS real UI → PostgREST → database: FX sync keeps entries, current cost/profit, stale quote rejected, lost ACK exact retry, historical receipt frozen, system quote/profit');
}catch(e){await writeFile(dir+'/failure.json',JSON.stringify({saves,errors,message:e.message},null,2));for(const ctx of contexts){const page=ctx.pages()[0];if(page){console.log((await page.locator('.workflowError').allTextContents()).join(' | '));await page.screenshot({path:dir+'/failure-'+contexts.indexOf(ctx)+'.png',fullPage:true});}}throw e;}finally{await Promise.all(contexts.map(c=>c.close()));await browser.close();}
