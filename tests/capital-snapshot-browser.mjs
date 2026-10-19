process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
// All application REST calls go to real local PostgREST, never production data.
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {mkdir} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base=process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3061',api=process.env.SOLAR_RPC_TEST_URL||'http://127.0.0.1:3062';
for(const url of [base,api])assert.match(url,/^http:\/\/(127\.0\.0\.1|localhost):\d+$/);
const ids={admin:'00000000-0000-0000-0000-000000003530',seller:'00000000-0000-0000-0000-000000003531'},secret='solar-local-test-only-signing-secret-347';
const encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
function session(uid){const raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600});return {access_token:raw+'.'+createHmac('sha256',secret).update(raw).digest('base64url'),refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}};}
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),contexts=[],failures=[],saved=[];
const dir='/workspace/solar-review/v353/browser';await mkdir(dir,{recursive:true});
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

try{
 const admin=await open('admin');await section(admin.page,'capital');
 await admin.page.locator('.capitalSnapshotHero').waitFor();
 assert.match(await admin.page.locator('.capitalSnapshotHero').innerText(),/-23,631,806.66/);
 assert.doesNotMatch(await admin.page.locator('.capitalWorkspace').innerText(),/مصدر الفرق|من أين جاء|عجز|المطلوبات المسجّلة أعلى|الأرصدة القديمة/);
 assert.match(await admin.page.getByRole('button',{name:'تفاصيل ديون الموردين علينا',exact:true}).innerText(),/1,232,243,006.66/);
 await noOverflow(admin.page);await admin.page.screenshot({path:dir+'/capital-mobile.png',fullPage:true});
 const broken=await admin.page.locator('.capitalAmount bdi').evaluateAll(nodes=>nodes.filter(n=>n.scrollWidth>n.parentElement.clientWidth+1).map(n=>n.textContent));
 assert.deepEqual(broken,[],'monetary figure clipped on mobile');
 const deposit=await admin.ctx.request.post(api+'/rpc/solar_cash_save',{headers:admin.headers,data:{request_id:crypto.randomUUID(),payload:{ownerId:ids.admin,mode:'capital_deposit',currency:'IQD',amount:40000000,note:'تمويل تجريبي محلي'}}});
 assert.equal(deposit.status(),200,await deposit.text());
 await admin.page.getByRole('button',{name:'تحديث الحساب',exact:true}).click();
 await admin.page.waitForFunction(()=>document.querySelector('.capitalSnapshotHero')?.textContent.includes('16,368,193.34'));
 assert.equal(await admin.page.locator('.capitalSnapshotHero.negative').count(),0);
 assert.doesNotMatch(await admin.page.locator('.capitalWorkspace').innerText(),/عجز|الفرق|الأرصدة القديمة/);
 await admin.page.screenshot({path:dir+'/positive-capital-mobile.png',fullPage:true});
 const popupPromise=admin.page.waitForEvent('popup');
 await admin.page.getByRole('button',{name:'تفاصيل ديون الموردين علينا',exact:true}).click();
 const popup=await popupPromise;await popup.locator('.pdfPage img').first().waitFor();
 assert.match(await popup.title(),/كشف ديون الموردين/);
 await popup.screenshot({path:dir+'/supplier-pdf.png',fullPage:true});await popup.close();
 await admin.page.getByRole('button',{name:'حفظ PDF',exact:true}).waitFor({state:'visible'});
 await admin.page.waitForFunction(()=>!document.querySelector('.reportButton.download')?.disabled);
 const downloadPromise=admin.page.waitForEvent('download');await admin.page.getByRole('button',{name:'حفظ PDF',exact:true}).click();
 const dl=await downloadPromise;await dl.saveAs(dir+'/capital.pdf');
 await admin.page.setViewportSize({width:1366,height:1000});await noOverflow(admin.page);await admin.page.screenshot({path:dir+'/capital-desktop.png',fullPage:true});
 const seller=await open('seller');await section(seller.page,'capital');await seller.page.locator('.capitalScopeNote').waitFor();
 assert.doesNotMatch(await seller.page.locator('.capitalWorkspace').innerText(),/ABDULRAHMAN|188,194,000|269,868,000/);
 await noOverflow(seller.page);await seller.page.screenshot({path:dir+'/own-capital-mobile.png',fullPage:true});
 await admin.page.route('**/rest/v1/rpc/solar_capital_snapshot',route=>route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({code:'TEST_ONLY',message:'تعذر تحميل الحساب للاختبار'})}));
 await admin.page.getByRole('button',{name:'تحديث الحساب',exact:true}).click();
 await admin.page.getByRole('alert').filter({hasText:'تعذر تحميل الحساب للاختبار'}).waitFor();
 assert.equal(await admin.page.locator('.capitalSnapshotHero').count(),0,'failed snapshot showed misleading old/zero balance');
 assert.equal(failures.length,0,JSON.stringify(failures));
 console.log(JSON.stringify({status:'PASS',checks:['known signed capital','mobile/desktop no clipped figures','positive capital uses current balances without deficit commentary','real PDF preview and download','own-only financial scope','error never shows zero capital'],productionWrites:0}));
}finally{for(const ctx of contexts)await ctx.close();await browser.close();}
