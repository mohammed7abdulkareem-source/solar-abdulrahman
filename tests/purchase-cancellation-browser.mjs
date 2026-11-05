// Full purchase approval flow against isolated PostgreSQL/PostgREST only.
process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const db=process.env.SOLAR_FIXTURE_DB||'solar_v399_browser',base=process.env.SOLAR_APP_URL||'http://127.0.0.1:3110',api=process.env.SOLAR_FIXTURE_API||'http://127.0.0.1:3111';
assert.match(db,/^solar_[a-z0-9_]+_browser$/);for(const url of[base,api])assert.equal(new URL(url).hostname,'127.0.0.1');
const dir='/workspace/solar-review/v399/browser';await mkdir(dir,{recursive:true});
const sql=q=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:q,encoding:'utf8'}).trim();
const ids={admin:'00000000-0000-0000-0000-000000039901',owner:'00000000-0000-0000-0000-000000039902'};
const financialHash=()=>sql("select md5(jsonb_build_array((select jsonb_agg(to_jsonb(t)order by id)from transactions t),(select jsonb_agg(to_jsonb(t)order by id)from transaction_items t),(select jsonb_agg(to_jsonb(t)order by id)from products t),(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),(select jsonb_agg(to_jsonb(t)order by id)from solar_private.supplier_fx_entries t),(select jsonb_agg(to_jsonb(t)order by id)from solar_private.wallet_fx_entries t))::text)");
const historicalHash=()=>sql("select md5(jsonb_agg(jsonb_build_array(to_jsonb(t),(select jsonb_agg(to_jsonb(i)order by id)from transaction_items i where transaction_id=t.id))order by t.id)::text)from transactions t where notes in('browser-v399-later','browser-v399-sale','browser-v399-cash-sale','browser-v399-short-sale')");
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),contexts=[],calls=[],errors=[],checks={};let currentPage;
const encode=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
async function open(who,section){
 const uid=ids[who],raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600}),token=raw+'.'+createHmac('sha256','solar-local-test-only-signing-secret-347').update(raw).digest('base64url');
 const session={access_token:token,refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}};
 const ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true});contexts.push(ctx);ctx.setDefaultTimeout(25000);
 await ctx.addInitScript(s=>localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify(s)),session);
 await ctx.routeWebSocket(/supabase/,socket=>socket.close());
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),url=new URL(req.url());if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
  if(url.pathname==='/auth/v1/user')return route.fulfill({json:session.user});
  if(url.pathname==='/functions/v1/solar-admin-users'){const users=JSON.parse(sql('select jsonb_agg(to_jsonb(p)order by id)from(select id,display_name,username,honorific,phone,permissions,is_admin,user_type,active from profiles)p'));return route.fulfill({json:{ok:true,users}});}
  if(!url.pathname.startsWith('/rest/v1/'))return route.abort();
  const call={who,path:url.pathname,method:req.method(),body:req.postData()?JSON.parse(req.postData()):null};calls.push(call);
  const headers={...req.headers(),authorization:'Bearer '+token};delete headers.apikey;delete headers.host;delete headers.origin;
  const response=await ctx.request.fetch(api+url.pathname.replace('/rest/v1','')+url.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});call.status=response.status();
  if(response.status()>=400)errors.push({who,path:url.pathname,status:response.status(),body:await response.text()});return route.fulfill({response});
 });
 await ctx.route('**/*',route=>{const url=new URL(route.request().url());if(url.hostname==='127.0.0.1'||url.protocol==='data:')return route.continue();if(url.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const page=await ctx.newPage();currentPage=page;page.on('pageerror',e=>errors.push(String(e)));page.on('dialog',d=>d.accept());await page.goto(base+'/?section='+section);await page.locator('.smoothFrame').waitFor();return {page,ctx,token};
}
async function noOverflow(page,width){await page.setViewportSize({width,height:920});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'horizontal overflow at '+width);}
const receipt=note=>JSON.parse(sql("select row_to_json(t)from transactions t where notes='"+note+"'"));
async function request(page,invoice){
 await page.goto(base+'/?section=purchase');await page.locator('.deskHistory > summary').click();
 await page.getByLabel('بحث الفواتير السابقة').fill(String(invoice.receipt_no));
 const card=page.locator('.historyItem').filter({has:page.locator('summary').filter({hasText:'فاتورة شراء رقم '+invoice.receipt_no})});
 await card.getByRole('button',{name:'حذف',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('.saveInProgress'));
 const id=await (async()=>{for(let i=0;i<40;i++){const value=sql('select id from solar_private.receipt_delete_requests where invoice_id='+invoice.id+" and status='pending'");if(value)return value;await page.waitForTimeout(100);}throw Error('Purchase deletion request did not persist');})();return id;
}
async function review(page,invoice){
 await page.goto(base+'/?section=deletionRequests');const row=page.locator('.deletionRequestRow').filter({hasText:'شراء #'+invoice.receipt_no});await row.click();await page.locator('.deletionReview .deletionAmount').waitFor();return page.locator('.deletionReview');
}
try{
 const first=receipt('browser-v399-first'),cash=receipt('browser-v399-cash'),short=receipt('browser-v399-short'),history=historicalHash(),initial=financialHash();
 const owner=await open('owner','purchase'),o=owner.page;
 const requestId=await request(o,first);assert.equal(financialHash(),initial);checks.requestIsReadOnly=true;
 const admin=await open('admin','deletionRequests'),a=admin.page;currentPage=a;
 const panel=await review(a,first);await panel.getByLabel('أثر إلغاء الشراء').waitFor();assert.match(await panel.innerText(),/يبقى في المخزن 11/);
 await noOverflow(a,360);await a.screenshot({path:dir+'/approval-mobile.png'});await noOverflow(a,1366);await a.screenshot({path:dir+'/approval-desktop.png'});await noOverflow(a,390);
 const approve=panel.getByRole('button',{name:'موافقة وحذف الوصل',exact:true});await approve.evaluate(button=>{button.click();button.click();});
 await a.locator('.workflowSuccess').filter({hasText:'تم الحذف بموافقة الإدارة'}).waitFor();
 assert.equal(sql('select count(*)from transactions where id='+first.id),'0');assert.equal(sql('select qty from products where id=-399101'),'11');assert.equal(sql("select sum(delta)from solar_private.supplier_fx_entries where supplier_id=-399101"),'11000.00');assert.equal(historicalHash(),history);
 assert.equal(calls.filter(c=>c.body?.action==='approve'&&c.body?.request_id===requestId).length,1);checks.approvalSingleSubmission=true;
 const after=financialHash();
 const duplicate=await admin.ctx.request.post(api+'/rpc/solar_receipt_delete_requests',{headers:{authorization:'Bearer '+admin.token},data:{action:'approve',request_id:requestId,payload:{}}});assert.equal(duplicate.status(),200);assert.equal((await duplicate.json()).status,'approved');assert.equal(financialHash(),after);checks.serverReplayIsReadOnly=true;
 const cashBefore=Number(sql("select solar_private.cash_balance('"+ids.owner+"')"));await request(o,cash);const cashPanel=await review(a,cash);assert.match(await cashPanel.getByLabel('أثر إلغاء الشراء').innerText(),/1,000/);await cashPanel.getByRole('button',{name:'موافقة وحذف الوصل',exact:true}).click();await a.locator('.workflowSuccess').filter({hasText:'تم الحذف بموافقة الإدارة'}).waitFor();
 assert.equal(Number(sql("select solar_private.cash_balance('"+ids.owner+"')")),cashBefore+1000);assert.equal(sql('select qty from products where id=-399102'),'9');assert.equal(historicalHash(),history);checks.cashRefundExactlyOnce=true;
 const beforeShort=financialHash();await request(o,short);const shortPanel=await review(a,short);await shortPanel.locator('.workflowError').filter({hasText:'المتاح غير المحجوز'}).waitFor();assert.equal(await shortPanel.getByRole('button',{name:'موافقة وحذف الوصل',exact:true}).isDisabled(),true);assert.equal(financialHash(),beforeShort);assert.equal(sql('select count(*)from transactions where id='+short.id),'1');checks.shortagePreservesReceipt=true;
 await a.screenshot({path:dir+'/stock-shortage.png'});assert.deepEqual(errors,[]);
 await writeFile(dir+'/results.json',JSON.stringify({pass:true,checks,calls,errors},null,2));console.log('PASS purchase request → admin current-stock preview → single approval → preserved later history / supplier correction / cash refund; insufficient stock blocked without writes');
}catch(error){await currentPage?.screenshot({path:dir+'/failure.png',fullPage:true,timeout:5000}).catch(()=>{});await writeFile(dir+'/failure.json',JSON.stringify({error:String(error),stack:error.stack,calls,errors,checks},null,2));throw error;}finally{for(const ctx of contexts)await ctx.unrouteAll({behavior:'ignoreErrors'}).catch(()=>{});await browser.close();}
