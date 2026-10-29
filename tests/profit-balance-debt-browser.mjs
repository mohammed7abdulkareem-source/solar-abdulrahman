// Compiled application → local PostgREST → isolated PostgreSQL. No production writes.
process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
import assert from 'node:assert/strict';
import {createHmac,createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const db=process.env.SOLAR_FIXTURE_DB||'solar_v389_browser';
if(!/^solar_[a-z0-9_]+_browser$/.test(db))throw Error('Use an isolated local browser database');
const dir=process.env.SOLAR_ARTIFACT_DIR||'/workspace/solar-review/v389/browser';await mkdir(dir,{recursive:true});
const sql=q=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:q,encoding:'utf8'}).trim();
const ids={admin:'00000000-0000-0000-0000-000000003910',owner:'00000000-0000-0000-0000-000000003911',other:'00000000-0000-0000-0000-000000003912',list:'00000000-0000-0000-0000-000000003915',statement:'00000000-0000-0000-0000-000000003916'};
const errors=[],calls=[],contexts=[],encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');let failBalance=false;
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
async function open(who,section){
 const uid=ids[who],raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600}),token=raw+'.'+createHmac('sha256','solar-local-test-only-signing-secret-347').update(raw).digest('base64url');
 const ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true});contexts.push(ctx);ctx.setDefaultTimeout(20000);
 await ctx.addInitScript(({uid,token})=>{localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify({access_token:token,refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}}));window.__documentHtmls=[];window.__sharedPdfs=[];Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>true});Object.defineProperty(navigator,'share',{configurable:true,value:async data=>{const f=data.files[0];window.__sharedPdfs.push({name:f.name,active:navigator.userActivation.isActive,hash:Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await f.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join('')});}});const descriptor=Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype,'srcdoc');Object.defineProperty(HTMLIFrameElement.prototype,'srcdoc',{...descriptor,set(html){window.__documentHtmls.push(html);return descriptor.set.call(this,html);}});},{uid,token});
 await ctx.routeWebSocket(/supabase/,socket=>socket.close());
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),u=new URL(req.url());
  if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
  if(u.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:uid,email:'fixture@local.test',aud:'authenticated'})});
  if(!u.pathname.startsWith('/rest/v1/'))return route.abort();
  const payload=req.postData()?JSON.parse(req.postData()):null;
  if(failBalance&&u.pathname.endsWith('/solar_profit_workspace')&&payload?.action==='balance'){failBalance=false;return route.fulfill({status:503,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify({code:'TEST503',message:'تعذر تأكيد الرصيد التجريبي'})});}
  const headers={...req.headers(),authorization:'Bearer '+token};delete headers.apikey;delete headers.host;delete headers.origin;
  const r=await ctx.request.fetch('http://127.0.0.1:3079'+u.pathname.replace('/rest/v1','')+u.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});
  if(u.pathname.includes('/rpc/'))calls.push({who,path:u.pathname,payload,status:r.status()});
  if(r.status()>=400)errors.push({who,path:u.pathname,status:r.status(),body:await r.text()});
  return route.fulfill({response:r});
 });
 await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const page=await ctx.newPage();page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:3073/?section='+section);return {page,ctx,token};
}
const fingerprint=()=>sql("select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from transactions t),'cash',(select jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text)from cash_ledger t),'supplier',(select jsonb_agg(to_jsonb(t)order by id)from solar_private.supplier_fx_entries t),'settlements',(select jsonb_agg(to_jsonb(t)order by id)from solar_private.profit_settlements t),'requests',(select jsonb_agg(to_jsonb(t)order by request_id)from solar_private.finance_requests t),'checkpoints',(select jsonb_agg(to_jsonb(t)order by owner_id,source_key)from solar_private.profit_checkpoints t))::text)");
let page;
try{
 const before=fingerprint(),{page:p,ctx}=await open('admin','profit');page=p;
 await p.getByTestId('profit-current-balance').filter({hasText:'1,000,000'}).waitFor();
 await p.getByLabel('مستخدم تقرير الأرباح',{exact:true}).selectOption(ids.owner);
 await p.getByTestId('profit-current-balance').filter({hasText:/^0/}).waitFor();
 assert.ok((await p.locator('.profitResultSummary').innerText()).includes('7,535,136.32'));
 await p.screenshot({path:dir+'/settled-profit-zero-mobile.png',fullPage:true});
 const oldDate=sql("select ((now()at time zone'Asia/Baghdad')::date-1)::text");
 await p.getByLabel('نهاية فترة الأرباح',{exact:true}).fill(oldDate);
 await p.getByTestId('profit-current-balance').filter({hasText:/^0/}).waitFor();
 await p.locator('.profitTransactions>summary').click();
 const movement=p.locator('.profitCompanyRow .profitMovement').first();
 await movement.locator('summary strong').filter({hasText:/^0/}).waitFor();
 await movement.locator('summary').click();
 await movement.locator('.profitMovementBalance').filter({hasText:'7,535,136.32'}).waitFor();
 const report=p.locator('.profitWorkspace>.uiPanel').filter({has:p.getByRole('heading',{name:'تقرير الأرباح',exact:true})}).locator('>.reportExport');
 await report.getByRole('button',{name:'حفظ PDF',exact:true}).waitFor();
 await p.waitForFunction(()=>Array.from(document.querySelectorAll('.profitWorkspace>.uiPanel')).find(x=>x.querySelector('h2')?.textContent==='تقرير الأرباح')?.querySelector('.reportButton.download')?.disabled===false);
 const [download]=await Promise.all([p.waitForEvent('download'),report.getByRole('button',{name:'حفظ PDF',exact:true}).click()]);await download.saveAs(dir+'/current-profit.pdf');
 const bytes=await readFile(dir+'/current-profit.pdf');assert.equal(bytes.subarray(0,5).toString(),'%PDF-');
 const pdfHtmls=await p.evaluate(()=>window.__documentHtmls);
 assert.ok(pdfHtmls.some(x=>x.includes('الأرباح المتبقية بعد التسوية: 0 د.ع')&&x.includes('ربح الفترة قبل التسويات: 7,535,136.32')));
 await report.getByRole('button',{name:'مشاركة',exact:true}).click();await report.getByText('تمت مشاركة ملف PDF.',{exact:true}).waitFor();
 const shares=await p.evaluate(()=>window.__sharedPdfs);assert.ok(shares[0].active);assert.equal(shares[0].hash,createHash('sha256').update(bytes).digest('hex'));
 const [preview]=await Promise.all([ctx.waitForEvent('page'),report.getByRole('button',{name:'معاينة',exact:true}).click()]);await preview.waitForLoadState();await preview.getByRole('button',{name:'طباعة',exact:true}).waitFor();await preview.screenshot({path:dir+'/profit-pdf-preview.png'});await preview.close();
 failBalance=true;await p.getByLabel('مستخدم تقرير الأرباح',{exact:true}).selectOption(ids.other);
 await p.getByRole('alert').filter({hasText:'تعذر تأكيد الرصيد التجريبي'}).waitFor();
 assert.ok((await p.getByTestId('profit-current-balance').innerText()).includes('…'));
 assert.ok(await report.getByRole('button',{name:'معاينة',exact:true}).isDisabled());
 await p.getByRole('button',{name:'إعادة تحميل الأرباح',exact:true}).click();await p.getByTestId('profit-current-balance').filter({hasText:'1,000,000'}).waitFor();
 await p.getByLabel('مستخدم تقرير الأرباح',{exact:true}).selectOption(ids.owner);
 await p.getByTestId('profit-current-balance').filter({hasText:/^0/}).waitFor();
 for(const width of[360,768,1440]){await p.setViewportSize({width,height:920});assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await p.screenshot({path:dir+'/profit-'+width+'.png'});}
 const own=await open('owner','profit');page=own.page;
 await own.page.getByTestId('staff-profit-current-balance').filter({hasText:/^0$/}).waitFor();
 await own.page.screenshot({path:dir+'/own-settled-profit-zero.png'});
 const debt=await open('owner','customerDebts');page=debt.page;
 await page.getByLabel('بحث الأرصدة',{exact:true}).fill('شركة');
 await page.getByRole('button',{name:'فتح كشف حساب شركة ديون الاختبار',exact:true}).waitFor();
 // Clicking the amount opens the same account as the named keyboard button.
 await page.locator('.accountDataRow').filter({hasText:'شركة ديون الاختبار'}).locator('.accountAmountCell').click();
 await page.getByRole('heading',{name:'كشف حساب عميل',exact:true}).waitFor();
 await page.getByTestId('statement-balance').filter({hasText:'16,667,000'}).waitFor();
 assert.equal(await page.locator('.miniIdentity h2').innerText(),'شركة ديون الاختبار');
 await page.screenshot({path:dir+'/debtor-account-mobile.png'});
 await page.getByRole('button',{name:'كشف حساب',exact:true}).click();await page.getByRole('heading',{name:'كشف حساب مفصل',exact:true}).waitFor();
 assert.ok((await page.locator('.miniStatementTable').innerText()).includes('16,667,000'));
 await page.getByRole('button',{name:'رجوع للحساب',exact:true}).click();await page.getByRole('button',{name:'رجوع إلى مدينون العملاء',exact:true}).click();
 assert.equal(await page.getByLabel('بحث الأرصدة',{exact:true}).inputValue(),'شركة');
 await page.getByRole('button',{name:'فتح كشف حساب شركة ديون الاختبار',exact:true}).focus();await page.keyboard.press('Enter');
 await page.getByRole('heading',{name:'كشف حساب عميل',exact:true}).waitFor();
 const statement=await open('statement','customerDebts');page=statement.page;
 await page.getByRole('button',{name:'فتح كشف حساب زبون كشف حساب فقط',exact:true}).click();
 await page.getByTestId('statement-balance').filter({hasText:'400,000'}).waitFor();
 assert.ok(calls.some(x=>x.who==='statement'&&x.path.endsWith('solar_customer_statement')&&x.status===200));
 const list=await open('list','customerDebts');page=list.page;
 await page.getByRole('cell',{name:'زبون قائمة فقط',exact:true}).waitFor();
 assert.equal(await page.getByRole('button',{name:/فتح كشف حساب/}).count(),0);
 // Server checks still deny other owners and existing read permissions.
 for(const[session,path,body]of[[own,'solar_profit_workspace',{action:'balance',payload:{ownerId:ids.other}}],[statement,'solar_customer_statement',{customer_id:-391011}],[list,'solar_customer_statement',{customer_id:-391015}]]){
  const response=await session.ctx.request.post('http://127.0.0.1:3079/rpc/'+path,{headers:{authorization:'Bearer '+session.token},data:body});assert.equal(response.status(),403);
 }
 assert.equal(fingerprint(),before);
 // A genuinely new earning after the approved snapshot is the new balance.
 sql("insert into transactions(id,kind,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id)values(-391003,'sale',500000,500000,500000,true,false,'credit','"+ids.owner+"','"+ids.owner+"')");
 page=p;await p.reload();await p.getByLabel('مستخدم تقرير الأرباح',{exact:true}).selectOption(ids.owner);await p.getByTestId('profit-current-balance').filter({hasText:'500,000'}).waitFor();
 await own.page.reload();await own.page.getByTestId('staff-profit-current-balance').filter({hasText:'500,000'}).waitFor();
 assert.deepEqual(errors,[]);
 await writeFile(dir+'/results.json',JSON.stringify({pass:true,settledProfitZero:true,currentIndependentOfDateAndType:true,companyAndUserAgree:true,newEarningsOnly:true,readOnlyFinancialHashUnchanged:true,pdfPreviewDownloadShare:true,failedLoadHidesOldBalance:true,debtorClickOpensExactAccount:true,debtorBackPreservesFilters:true,keyboardNavigation:true,existingPermissionsAtAPI:true,noOverflow:[360,768,1440],calls,errors},null,2));
 console.log('PASS authoritative post-settlement balances and PDF, period/owner filters, stale-load handling, new earnings, debtor → exact account → return, API permissions, unchanged read-only financial state');
}catch(error){if(page)await page.screenshot({path:dir+'/failure.png',fullPage:true}).catch(()=>{});await writeFile(dir+'/failure.json',JSON.stringify({error:String(error),stack:error.stack,calls,errors},null,2));throw error;}finally{for(const ctx of contexts)await ctx.close();await browser.close();}
