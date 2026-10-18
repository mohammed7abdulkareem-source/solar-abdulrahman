// Browser → real local PostgREST 14 → protected RPC → local PostgreSQL.
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {mkdir} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base=process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3046',api=process.env.SOLAR_RPC_TEST_URL||'http://127.0.0.1:3045';
for(const u of [base,api])assert.match(u,/^http:\/\/(127\.0\.0\.1|localhost):\d+$/);
const uid='00000000-0000-0000-0000-000000003490',secret='solar-local-test-only-signing-secret-347',encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
const start=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600}),token=start+'.'+createHmac('sha256',secret).update(start).digest('base64url');
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});const ctx=await browser.newContext({viewport:{width:390,height:900}});ctx.setDefaultTimeout(15000);let saves=0;const failures=[];
await ctx.addInitScript(({uid,token})=>localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify({access_token:token,refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}})),{uid,token});
await ctx.routeWebSocket(/supabase/,socket=>socket.close());
await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
 const req=route.request(),url=new URL(req.url());
 if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
 if(url.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:uid,email:'fixture@local.test',aud:'authenticated'})});
 if(url.pathname.startsWith('/rest/v1/')){
  const headers={...req.headers(),authorization:'Bearer '+token};delete headers.host;delete headers.apikey;delete headers.origin;
  const response=await ctx.request.fetch(api+url.pathname.replace('/rest/v1','')+url.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});
  if(url.pathname.endsWith('/solar_system_payment_save'))saves++;
  if(response.status()>=400){const data=await response.json();if(!url.pathname.endsWith('/solar_staff_directory'))failures.push({path:url.pathname,status:response.status(),data});}
  return route.fulfill({response});
 }
 return route.abort();
});
await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
const page=await ctx.newPage();page.on('dialog',d=>d.accept());page.on('pageerror',e=>failures.push(e.message));await page.goto(base);await page.locator('.premiumDashboard').waitFor();await page.locator('.sectionDirectory a[href="/?section=systemPayment"]').click();await page.getByRole('combobox',{name:'بحث عميل الكشف'}).fill('زبون اختبار الحقل الواضح');await page.getByRole('option').filter({hasText:'زبون اختبار الحقل الواضح'}).click();await page.getByRole('button',{name:'كامل المبلغ',exact:true}).click();const amount=page.getByLabel('مبلغ حركة المنظومات');assert.equal(await amount.inputValue(),'3,707,000');
const dir='/workspace/solar-review/v347-real-api';await mkdir(dir,{recursive:true});
for(const width of [320,390,591,1366]){
 await page.setViewportSize({width,height:900});const dimensions=await amount.evaluate(input=>{const style=getComputedStyle(input),parent=input.closest('.accountFilterPanel'),canvas=document.createElement('canvas'),context=canvas.getContext('2d');context.font=style.font;return {width:input.getBoundingClientRect().width,form:parent.getBoundingClientRect().width,text:context.measureText(input.value).width,inner:input.clientWidth-parseFloat(style.paddingLeft)-parseFloat(style.paddingRight),background:style.backgroundColor,height:input.getBoundingClientRect().height};});
 assert.ok(dimensions.width>=dimensions.form*.8,'amount is not full width: '+JSON.stringify(dimensions));assert.ok(dimensions.text<dimensions.inner,'complete amount clipped: '+JSON.stringify(dimensions));assert.ok(dimensions.height>=64);assert.equal(dimensions.background,'rgb(231, 250, 241)');assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 if([390,1366].includes(width))await page.screenshot({path:dir+'/amount-'+width+'.png',fullPage:true});
}
await page.setViewportSize({width:390,height:900});await page.getByLabel('ملاحظات حركة المنظومات').fill('بيد محمد — اختبار محلي');await page.getByRole('button',{name:'حفظ التسديد',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ تسديد المنظومات'}).waitFor();assert.equal(await page.getByTestId('system-saved-balance').innerText(),'0 د.ع');assert.equal(saves,1);await page.screenshot({path:dir+'/saved-mobile.png',fullPage:true});assert.deepEqual(failures,[]);console.log('PASS browser to actual PostgREST: production-style deleted highest ID skipped, one full 3,707,000 payment saved, zero remaining, colored full-width amount completely readable at 320/390/591/1366 px');await ctx.close();await browser.close();
