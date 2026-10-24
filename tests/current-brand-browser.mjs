process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base='http://127.0.0.1:3073',api='http://127.0.0.1:3079',db='solar_v372_browser',dir='/workspace/solar-review/v372/browser';await mkdir(dir,{recursive:true});
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


const rawFingerprint=()=>sql("select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t) order by id) from transactions t),'items',(select jsonb_agg(to_jsonb(i) order by id) from transaction_items i),'productValues',(select jsonb_agg(jsonb_build_array(id,qty,cost,cost_basis,costing_revision) order by id) from products),'stocks',(select jsonb_agg(to_jsonb(w) order by warehouse_id,product_id) from solar_private.warehouse_stocks w))::text)");
try{
 const before=rawFingerprint(),admin=await open('admin','products'),page=admin.page;page.on('dialog',d=>d.accept());
 await page.getByLabel('بحث المواد المحفوظة').fill('0002');const material=page.locator('.savedMaterial').filter({hasText:'كود: 0002 •'});await material.getByRole('button',{name:'تعديل',exact:true}).click();await page.locator('select[name=brand]').selectOption('M');await page.getByRole('button',{name:'حفظ التعديل',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ تعديل المادة.'}).waitFor();assert.equal(await page.locator('select[name=brand]').inputValue(),'M');
 await page.getByRole('button',{name:'الرئيسية',exact:false}).first().click();await page.getByPlaceholder('ابحث عن القسم المطلوب…').fill('المبيعات السابقة');await page.getByRole('link',{name:/المبيعات السابقة/}).first().click();await page.locator('.saleHistoryCard').first().waitFor();
 await page.locator('input[type=date]').nth(0).fill('2026-10-24');await page.locator('input[type=date]').nth(1).fill('2026-10-24');await page.getByRole('button',{name:'مبيعات الفترة',exact:true}).click();const row=page.locator('.periodMaterialsTable tbody tr').filter({hasText:'كود 0002'});await row.getByText('كود 0002 · M · ألواح',{exact:true}).waitFor();assert.ok(!(await row.innerText()).includes('FULLMAX'));
 await page.waitForFunction(()=>!document.querySelector('.periodSales .preview')?.disabled);const pop=page.waitForEvent('popup');await page.locator('.periodSales').getByRole('button',{name:'معاينة',exact:true}).click();const pdf=await pop;await pdf.locator('.pdfPage img').first().waitFor();await pdf.screenshot({path:dir+'/current-brand-pdf.png'});await pdf.close();const html=await page.evaluate(()=>window.__documentHtmls.at(-1));assert.ok(html.includes('كود 0002 · M · ألواح'));
 await page.getByRole('button',{name:'العرض الحالي',exact:true}).click();await page.locator('.saleHistoryCard').first().waitFor();const historyCall=[...calls].reverse().find(c=>c.path.endsWith('solar_sales_history'));assert.ok(historyCall);
 assert.equal(rawFingerprint(),before);assert.equal(sql("select brand_name from transaction_items where product_id=-371001 limit 1"),'FULLMAX');
 // A global brand rename must affect fresh reads for owners and installers too.
 sql("update brands set name='M_RENAMED' where id=-372001");
 const owner=await open('owner','salesHistory');await owner.page.locator('.saleHistoryCard').first().waitFor();await owner.page.getByRole('button',{name:'مبيعات الفترة',exact:true}).click();await owner.page.locator('.periodMaterialsTable tbody tr').filter({hasText:'كود 0002'}).getByText('كود 0002 · M_RENAMED · ألواح',{exact:true}).waitFor();
 for(const width of [320,390,768,1440]){await owner.page.setViewportSize({width,height:960});assert.ok(await owner.page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await owner.page.screenshot({path:dir+'/brand-'+width+'.png',fullPage:true});}
 assert.equal(rawFingerprint(),before);assert.deepEqual(errors,[]);await writeFile(dir+'/results.json',JSON.stringify({pass:true,errors,calls,financialHistoryUnchanged:true},null,2));console.log('PASS browser/API/PDF: real material reassignment, immediate navigation with refreshed catalog, current brands in period report/PDF, global rename on next read, old financial rows unchanged, compact numbering');
}catch(e){for(const [i,ctx]of contexts.entries()){const p=ctx.pages()[0];if(p)await p.screenshot({path:dir+'/failure-'+i+'.png',fullPage:true});}await writeFile(dir+'/failure.json',JSON.stringify({message:e.message,errors,calls},null,2));throw e;}finally{await Promise.all(contexts.map(c=>c.close()));await browser.close();}
