process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base='http://127.0.0.1:3073',api='http://127.0.0.1:3079',db='solar_v373_browser',dir='/workspace/solar-review/v373/browser';await mkdir(dir,{recursive:true});
const sql=q=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:q,encoding:'utf8'}).trim();
const ids={admin:'00000000-0000-0000-0000-000000003710',owner:'00000000-0000-0000-0000-000000003711',other:'00000000-0000-0000-0000-000000003712',history:'00000000-0000-0000-0000-000000003713'};
const errors=[],calls=[],contexts=[],encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
async function open(who,section){
 const uid=ids[who],raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600}),token=raw+'.'+createHmac('sha256','solar-local-test-only-signing-secret-347').update(raw).digest('base64url');
 const ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true});contexts.push(ctx);ctx.__ledgerDone=false;ctx.setDefaultTimeout(20000);
 await ctx.addInitScript(({uid,token})=>{localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify({access_token:token,refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}}));window.__documentHtmls=[];const descriptor=Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype,'srcdoc');Object.defineProperty(HTMLIFrameElement.prototype,'srcdoc',{...descriptor,set(html){window.__documentHtmls.push(html);return descriptor.set.call(this,html);}});},{uid,token});
 await ctx.routeWebSocket(/supabase/,socket=>socket.close());
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{const req=route.request(),u=new URL(req.url());if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});if(u.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:uid,email:'fixture@local.test',aud:'authenticated'})});if(!u.pathname.startsWith('/rest/v1/'))return route.abort();
  if(u.pathname.endsWith('/rpc/solar_staff_directory'))await new Promise(r=>setTimeout(r,2000));if(u.pathname.endsWith('/transaction_items'))await new Promise(r=>setTimeout(r,5000));if(u.pathname.endsWith('/profiles')&&u.search.includes('id=eq.'))await new Promise(r=>setTimeout(r,180));const headers={...req.headers(),authorization:'Bearer '+token};delete headers.apikey;delete headers.host;delete headers.origin;
  const r=await ctx.request.fetch(api+u.pathname.replace('/rest/v1','')+u.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined}),body=await r.text();if(u.pathname.endsWith('/transaction_items'))ctx.__ledgerDone=true;if(u.pathname.includes('/rpc/'))calls.push({who,path:u.pathname,payload:req.postData()?JSON.parse(req.postData()):null,status:r.status(),...(u.pathname.endsWith('solar_sales_period')?{result:JSON.parse(body)}:{})});if(r.status()>=400)errors.push({who,path:u.pathname,status:r.status(),body});return route.fulfill({response:r,body});});
 await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const page=await ctx.newPage();page.on('pageerror',e=>errors.push(e.message));await page.goto(base+'/?section='+section);return {page,ctx,token};
}



const metrics={};try{
 for(const section of ['home','salesHistory','cash','installations']){
  const start=Date.now(),session=await open('admin',section),page=session.page;
  if(section==='home')await page.getByRole('heading',{name:'أقسام البرنامج',exact:true}).waitFor();
  if(section==='salesHistory')await page.locator('.saleHistoryCard').first().waitFor();
  if(section==='cash')await page.locator('.cashWorkspace').waitFor();
  if(section==='installations')await page.getByRole('heading',{name:'إدارة التنصيبات',exact:true}).waitFor();
  metrics[section]=Date.now()-start;if(!process.env.SOLAR_PERF_BASELINE)assert.equal(session.ctx.__ledgerDone,false,'section waited for the unrelated full ledger: '+section);if(section==='salesHistory'&&!process.env.SOLAR_PERF_BASELINE){await page.locator('.saleHistoryCard').first().getByRole('button',{name:'تعديل الفاتورة',exact:true}).click();await page.locator('.invoiceWorkspace').waitFor();assert.equal(session.ctx.__ledgerDone,true,'editor opened before complete master data');await page.locator('.deskTable tbody tr').first().waitFor();}
 }
 await writeFile(dir+'/'+(process.env.SOLAR_PERF_BASELINE?'baseline':'candidate')+'-timings.json',JSON.stringify({metrics,delays:{staff:2000,fullLedger:5000},errors,calls},null,2));console.log(JSON.stringify({metrics,errors}));
}catch(e){await writeFile(dir+'/startup-failure.json',JSON.stringify({error:e.message,metrics,errors,calls},null,2));throw e;}finally{await Promise.allSettled(contexts.map(async c=>{await c.unrouteAll({behavior:'ignoreErrors'});await c.close();}));await browser.close();}
