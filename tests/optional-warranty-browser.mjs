process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base='http://127.0.0.1:3073',api='http://127.0.0.1:3079',db='solar_v373_browser',dir='/workspace/solar-review/v373/warranty-browser';await mkdir(dir,{recursive:true});
const sql=q=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:q,encoding:'utf8'}).trim();
const ids={admin:'00000000-0000-0000-0000-000000003710',owner:'00000000-0000-0000-0000-000000003711',other:'00000000-0000-0000-0000-000000003712',history:'00000000-0000-0000-0000-000000003713'};
const errors=[],calls=[],contexts=[],encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
async function open(who,section){
 const uid=ids[who],raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600}),token=raw+'.'+createHmac('sha256','solar-local-test-only-signing-secret-347').update(raw).digest('base64url');
 const ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true});contexts.push(ctx);ctx.setDefaultTimeout(20000);
 await ctx.addInitScript(({uid,token})=>{localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify({access_token:token,refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}}));window.__documentHtmls=[];const descriptor=Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype,'srcdoc');Object.defineProperty(HTMLIFrameElement.prototype,'srcdoc',{...descriptor,set(html){window.__documentHtmls.push(html);return descriptor.set.call(this,html);}});},{uid,token});
 await ctx.routeWebSocket(/supabase/,socket=>socket.close());
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{const req=route.request(),u=new URL(req.url());if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});if(u.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:uid,email:'fixture@local.test',aud:'authenticated'})});if(!u.pathname.startsWith('/rest/v1/'))return route.abort();
  const headers={...req.headers(),authorization:'Bearer '+token};delete headers.apikey;delete headers.host;delete headers.origin;
  const r=await ctx.request.fetch(api+u.pathname.replace('/rest/v1','')+u.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined}),body=await r.text();if(u.pathname.includes('/rpc/'))calls.push({who,path:u.pathname,payload:req.postData()?JSON.parse(req.postData()):null,status:r.status(),...(u.pathname.endsWith('solar_sales_period')?{result:JSON.parse(body)}:{})});if(r.status()>=400)errors.push({who,path:u.pathname,status:r.status(),body});return route.fulfill({response:r,body});});
 await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const page=await ctx.newPage();page.on('pageerror',e=>errors.push(e.message));await page.goto(base+'/?section='+section);return {page,ctx,token};
}



const fingerprint=()=>sql("select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t) order by id) from transactions t),'items',(select jsonb_agg(to_jsonb(i) order by id) from transaction_items i),'stocks',(select jsonb_agg(to_jsonb(w) order by warehouse_id,product_id) from solar_private.warehouse_stocks w))::text)");
try{
 const before=fingerprint(),admin=await open('admin','salesHistory'),page=admin.page;page.on('dialog',d=>d.accept());await page.locator('.saleHistoryCard').first().waitFor();
 const fixture=JSON.parse(sql("select jsonb_agg(jsonb_build_object('id',id,'number',receipt_no,'token',warranty_token,'enabled',warranty->'enabled') order by id) from(select * from transactions where kind='sale' and party_id=-371001 order by id limit 2)t"));
 for(const item of fixture){
  await page.getByPlaceholder('رقم الوصل / اسم الزبون').fill(String(item.number));await page.getByRole('button',{name:'بحث / تحديث',exact:true}).click();const card=page.getByRole('article',{name:'بيع جملة رقم '+item.number,exact:true});await card.waitFor();
  for(const customer of [true,false]){
   const pop=page.waitForEvent('popup');await card.getByRole('button',{name:customer?'معاينة وصل الزبون':'معاينة الوصل المخزني',exact:true}).click();const pdf=await pop;await pdf.locator('.pdfPage img').first().waitFor();if(customer){const saved=pdf.waitForEvent('download');await pdf.locator('#pdfDownload').click();const download=await saved;await download.saveAs(dir+'/'+(item.enabled?'on':'off')+'-customer.pdf');}await pdf.screenshot({path:dir+'/'+(item.enabled?'on':'off')+'-'+(customer?'customer':'warehouse')+'.png'});await pdf.close();
   const html=await page.evaluate(()=>window.__documentHtmls.at(-1));assert.equal(html.includes('class="invoiceWarranty"'),item.enabled);assert.equal(html.includes('class="invoiceQr"'),item.enabled);if(!item.enabled){assert.ok(!html.includes('هذه الفاتورة بدون ضمان'));assert.ok(!html.includes('فحص الفاتورة والضمان'));assert.ok(!html.includes('class="invoiceQr"'));}
  }
 }
 const publicContext=await browser.newContext({viewport:{width:390,height:920}});contexts.push(publicContext);await publicContext.routeWebSocket(/supabase/,socket=>socket.close());
 await publicContext.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{const req=route.request(),u=new URL(req.url());if(!u.pathname.endsWith('/rpc/solar_warranty_verify'))return route.abort();const r=await publicContext.request.fetch(api+'/rpc/solar_warranty_verify',{method:'POST',headers:{'content-type':'application/json'},data:req.postDataBuffer()});assert.equal(r.status(),200);return route.fulfill({response:r});});
 const certificate=await publicContext.newPage();for(const item of fixture){await certificate.goto(base+'/warranty/'+item.token);await certificate.locator('.certificateItem').first().waitFor();const text=await certificate.locator('main').innerText();if(item.enabled){assert.match(text,/شهادة ضمان الفاتورة/);assert.ok(await certificate.locator('.certificateStatus').count()>0);}else{assert.ok(!text.includes('شهادة ضمان'));assert.ok(!text.includes('بدون ضمان'));assert.ok(!text.includes('بداية الضمان'));assert.equal(await certificate.locator('.certificateStatus').count(),0);}await certificate.screenshot({path:dir+'/public-'+(item.enabled?'on':'off')+'.png',fullPage:true});}
 assert.equal(fingerprint(),before);assert.deepEqual(errors,[]);await writeFile(dir+'/results.json',JSON.stringify({pass:true,errors,calls,retainedDisabledToken:true,readOnly:true},null,2));console.log('PASS browser/API/PDF: unchecked retained tokens hide warranty and QR in customer/warehouse copies, checked policies render warranty, anonymous legacy links display truthful invoice-only data when disabled, no business changes');
}catch(e){for(const [i,ctx]of contexts.entries()){const p=ctx.pages()[0];if(p&&!p.isClosed())await p.screenshot({path:dir+'/failure-'+i+'.png',fullPage:true});}await writeFile(dir+'/failure.json',JSON.stringify({message:e.message,errors,calls},null,2));throw e;}finally{await Promise.allSettled(contexts.map(async c=>{await c.unrouteAll({behavior:'ignoreErrors'});await c.close();}));await browser.close();}
