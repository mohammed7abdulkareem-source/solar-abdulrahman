process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
// Real local PostgREST 14, production RLS mirror, independently signed staff/admin sessions.
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {mkdir} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base=process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3051',api=process.env.SOLAR_RPC_TEST_URL||'http://127.0.0.1:3052';
for(const value of [base,api])assert.match(value,/^http:\/\/(127\.0\.0\.1|localhost):\d+$/);
const ids={admin:'00000000-0000-0000-0000-000000003590',a:'00000000-0000-0000-0000-000000003591',b:'00000000-0000-0000-0000-000000003592'},key='sb-afxxaafsuscwyjzrnagc-auth-token',secret='solar-local-test-only-signing-secret-347';
const encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
function session(uid){const value=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600});return {access_token:value+'.'+createHmac('sha256',secret).update(value).digest('base64url'),refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}};}
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});const contexts=[],errors=[];let delayProfile='';
const dir='/workspace/solar-review/isolation-v349';await mkdir(dir,{recursive:true});
async function open(name,width){
 const auth=session(ids[name]),ctx=await browser.newContext({viewport:{width,height:900}});contexts.push(ctx);ctx.setDefaultTimeout(15000);
 await ctx.addInitScript(({key,auth})=>localStorage.setItem(key,JSON.stringify(auth)),{key,auth});await ctx.routeWebSocket(/supabase/,socket=>socket.close());
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),url=new URL(req.url()),authorization=req.headers().authorization||'',token=authorization.replace(/^Bearer /i,'');let uid;
  try{uid=JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString()).sub;}catch{}
  if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
  if(url.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:uid,email:'fixture@local.test',aud:'authenticated'})});
  if(url.pathname==='/functions/v1/solar-admin-users'){
   assert.equal(uid,ids.admin);assert.equal(req.postDataJSON().action,'list');const response=await ctx.request.get(api+'/profiles',{headers:{authorization}});return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({users:await response.json()})});
  }
  if(url.pathname.startsWith('/rest/v1/')){
   if(delayProfile===uid&&url.pathname.endsWith('/profiles'))await new Promise(resolve=>setTimeout(resolve,900));
   const headers={...req.headers()};delete headers.host;delete headers.apikey;delete headers.origin;
   const response=await ctx.request.fetch(api+url.pathname.replace('/rest/v1','')+url.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});
   if(response.status()>=400&&!url.pathname.endsWith('/solar_staff_directory'))errors.push({path:url.pathname,status:response.status(),body:await response.json()});return route.fulfill({response});
  }
  return route.abort();
 });
 await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const page=await ctx.newPage();page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());return {ctx,page,auth};
}
async function section(page,name){await page.goto(base+'/?section='+name);}
async function archive(page,count,forbidden){await section(page,'salesHistory');await page.locator('.archiveInvoice').first().waitFor();assert.equal(await page.locator('.archiveInvoice').count(),count);if(forbidden)assert.ok(!(await page.locator('body').innerText()).includes(forbidden));}
try{
 const a=await open('a',390);await archive(a.page,2,'PRIVATE_B');await a.page.screenshot({path:dir+'/staff-a-archive-mobile.png',fullPage:true});
 await section(a.page,'warehouse');await a.page.locator('.warehouseOrder').first().waitFor();await a.page.locator('.warehouseQueueTabs button').last().click();await a.page.waitForFunction(()=>document.querySelectorAll('.warehouseOrder').length===2);assert.ok(!(await a.page.locator('body').innerText()).includes('PRIVATE_B'));await a.page.screenshot({path:dir+'/staff-a-warehouse-mobile.png',fullPage:true});
 await section(a.page,'stockMovement');await a.page.getByRole('tab',{name:'جميع الحركات',exact:true}).click();await a.page.locator('.movementEntry').first().waitFor();assert.equal(await a.page.locator('.movementEntry').count(),3);assert.ok(!(await a.page.locator('body').innerText()).includes('PRIVATE_B'));
 await a.page.getByRole('button',{name:'فتح الإشعارات',exact:true}).click();await a.page.locator('.notificationPanel').waitFor();assert.ok(!(await a.page.locator('.notificationPanel').innerText()).includes('PRIVATE_B'));assert.equal(await a.page.getByText('OLD_CROSS_NOTICE',{exact:true}).count(),0);
 const authHeaders={authorization:'Bearer '+a.auth.access_token};const raw=await a.ctx.request.get(api+'/transactions?id=eq.-359021',{headers:authHeaders});assert.deepEqual(await raw.json(),[]);
 for(const [name,data] of [['solar_warehouse_action',{invoice_id:-359021,expected_token:'forged',action:'ready'}],['solar_sale_delete_preview',{invoice_id:-359021}],['solar_warranty_manage',{action:'get',payload:{id:-359021}}]]){
  const response=await a.ctx.request.post(api+'/rpc/'+name,{headers:authHeaders,data});assert.equal(response.status(),403,name);assert.equal((await response.json()).code,'42501');
 }
 const b=await open('b',1366);await archive(b.page,3,'PRIVATE_A');await b.page.screenshot({path:dir+'/staff-b-archive-desktop.png',fullPage:true});
 const admin=await open('admin',1366);await archive(admin.page,5);assert.ok((await admin.page.locator('body').innerText()).includes('PRIVATE_A'));assert.ok((await admin.page.locator('body').innerText()).includes('PRIVATE_B'));
 await section(admin.page,'users');await admin.page.locator('.userPermissionCard').first().waitFor();await admin.page.locator('.userPermissionCard').filter({hasText:'Seller A'}).getByRole('button',{name:'تعديل',exact:true}).click();
 assert.equal(await admin.page.locator('.scopeBox input:checked:disabled').count(),4);for(const select of await admin.page.locator('.closingScope select').all())assert.equal(await select.locator('option[value="all"]').count(),0);
 await archive(admin.page,5);delayProfile=ids.a;
 await admin.page.evaluate(({key,auth})=>{localStorage.setItem(key,JSON.stringify(auth));const channel=new BroadcastChannel(key);channel.postMessage({event:'SIGNED_IN',session:auth});setTimeout(()=>channel.close(),200);},{key,auth:session(ids.a)});
 await admin.page.locator('.loginPage').waitFor();assert.ok(!(await admin.page.locator('body').innerText()).includes('PRIVATE_B'));assert.equal(await admin.page.locator('.archiveInvoice').count(),0);
 await admin.page.waitForFunction(()=>document.querySelectorAll('.archiveInvoice').length===2);delayProfile='';assert.ok(!(await admin.page.locator('body').innerText()).includes('PRIVATE_B'));await admin.page.screenshot({path:dir+'/switched-admin-to-staff.png',fullPage:true});
 assert.deepEqual(errors,[]);console.log('PASS actual browser → PostgREST 14: two-way staff isolation in archive, warehouse, movement, notifications and direct IDOR; admin all-record oversight; fixed permission scopes; delayed admin-to-staff switch clears all previous account data.');
}finally{for(const ctx of contexts)await ctx.close();await browser.close();}
