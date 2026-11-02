// Browser and API verification against disposable local PostgreSQL only.
import assert from 'node:assert/strict';
import {createHash,createHmac} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const db=process.env.SOLAR_FIXTURE_DB||'solar_v398_browser',base=process.env.SOLAR_APP_URL||'http://127.0.0.1:3107',api=process.env.SOLAR_FIXTURE_API||'http://127.0.0.1:3106';
assert.match(db,/^solar_[a-z0-9_]+_browser$/);for(const url of [base,api])assert.equal(new URL(url).hostname,'127.0.0.1');
const dir='/workspace/solar-review/v398/browser';await mkdir(dir,{recursive:true});
const sql=q=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:q,encoding:'utf8'}).trim();
const hash=()=>sql("select md5(jsonb_build_object('transactions',(select jsonb_agg(to_jsonb(t) order by id) from transactions t),'items',(select jsonb_agg(to_jsonb(t) order by id) from transaction_items t),'supplier',(select jsonb_agg(to_jsonb(t) order by id) from solar_private.supplier_fx_entries t),'cash',(select jsonb_agg(to_jsonb(t) order by id) from solar_cash_entries t))::text)");
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),contexts=[],calls=[],errors=[],checks={};let page;
const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
async function open(uid,path){
 const raw=enc({alg:'HS256',typ:'JWT'})+'.'+enc({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600}),token=raw+'.'+createHmac('sha256','solar-local-test-only-signing-secret-347').update(raw).digest('base64url');
 const session={access_token:token,refresh_token:'local-test',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}};
 const ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true,acceptDownloads:true});contexts.push(ctx);ctx.setDefaultTimeout(20000);
 await ctx.addInitScript(s=>{localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify(s));window.print=()=>{window.__printCalls=(window.__printCalls||0)+1};Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>true});Object.defineProperty(navigator,'share',{configurable:true,value:async data=>{const f=data.files[0],bytes=await f.arrayBuffer(),digest=await crypto.subtle.digest('SHA-256',bytes);window.__shared={active:navigator.userActivation.isActive,size:f.size,type:f.type,hash:Array.from(new Uint8Array(digest)).map(b=>b.toString(16).padStart(2,'0')).join('')}}});},session);
 await ctx.routeWebSocket(/supabase/,socket=>socket.close());
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),u=new URL(req.url());if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
  if(u.pathname==='/auth/v1/user')return route.fulfill({json:session.user});
  if(u.pathname==='/functions/v1/solar-admin-users'){const users=JSON.parse(sql('select jsonb_agg(to_jsonb(p) order by id) from(select id,display_name,username,honorific,phone,permissions,is_admin,user_type,active from profiles)p'));return route.fulfill({json:{ok:true,users}});}
  if(!u.pathname.startsWith('/rest/v1/'))return route.abort();
  const call={path:u.pathname,method:req.method(),body:req.postData()?JSON.parse(req.postData()):null};calls.push(call);
  const headers={...req.headers(),authorization:'Bearer '+token};delete headers.apikey;delete headers.host;delete headers.origin;
  const response=await ctx.request.fetch(api+u.pathname.replace('/rest/v1','')+u.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});call.status=response.status();return route.fulfill({response});
 });
 await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const p=await ctx.newPage();page=p;p.on('pageerror',e=>errors.push(String(e)));p.on('dialog',d=>d.dismiss());await p.goto(base+path);await p.locator('.smoothFrame').waitFor();return {p,ctx,token};
}
async function noOverflow(p,width){await p.setViewportSize({width,height:920});assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'horizontal overflow at '+width);}
async function ready(p){await p.locator('.partyReportActions .reportButton.download:not([disabled])').waitFor({timeout:120000});}
async function documentActions(p,ctx,label){
 await ready(p);const section=p.locator('.partyReportActions');
 const [preview]=await Promise.all([ctx.waitForEvent('page'),section.getByRole('button',{name:'معاينة',exact:true}).click()]);await preview.locator('.pdfPage img').first().waitFor({timeout:30000});
 assert.ok(await preview.locator('.pdfPage').count()>=1);await preview.screenshot({path:dir+'/'+label+'-preview.png'});await preview.close();
 const [printView]=await Promise.all([ctx.waitForEvent('page'),section.getByRole('button',{name:'طباعة',exact:true}).click()]);await printView.locator('#pdfPrint:not([disabled])').waitFor({timeout:30000});assert.equal(await printView.evaluate(()=>window.__printCalls),1);await printView.close();
 const downloadPromise=p.waitForEvent('download');await section.getByRole('button',{name:'حفظ PDF',exact:true}).click();const download=await downloadPromise,path=dir+'/'+label+'.pdf';await download.saveAs(path);const bytes=await readFile(path);assert.equal(bytes.subarray(0,4).toString(),'%PDF');
 await section.getByRole('button',{name:'مشاركة',exact:true}).click();await p.waitForFunction(()=>window.__shared?.size>0);const shared=await p.evaluate(()=>window.__shared);assert.equal(shared.type,'application/pdf');assert.equal(shared.active,true);assert.equal(shared.hash,createHash('sha256').update(bytes).digest('hex'));
 await p.evaluate(()=>window.__shared=null);
}
try{
 const before=hash(),admin=await open('00000000-0000-0000-0000-000000003920','/?section=customers'),p=admin.p;
 await p.getByLabel('بحث الزبائن المسجلين').fill('07700039801');await p.getByRole('button',{name:'حساب عميل الجملة التجريبي',exact:true}).click();await p.getByTestId('statement-balance').waitFor();
 const balance=await p.getByTestId('statement-balance').innerText();await p.getByRole('button',{name:'مبيعات',exact:true}).click();
 await p.locator('.partyInvoiceCard').first().waitFor();await p.locator('.partyInvoiceCard .partyInvoiceItem').last().waitFor({timeout:30000});assert.equal(await p.locator('.partyInvoiceCard').count(),111);assert.equal(await p.locator('.partyInvoiceCard .partyInvoiceItem').count(),111);
 const batches=calls.filter(c=>c.path.endsWith('/rpc/solar_customer_invoice_report_batch'));assert.equal(batches.length,2);assert.deepEqual(batches.map(c=>c.body.invoice_ids.length),[100,11]);assert.ok(batches.every(c=>c.status===200));checks.completeInvoiceBatches=true;
 await ready(p);const bulkStatus=await p.locator('.partyReportActions .reportExportStatus').innerText();const bulkPages=Number(bulkStatus.match(/(\d+) صفحة/)?.[1]);assert.ok(bulkPages>5,'All invoices must span multiple complete pages: '+bulkStatus);const bulkDownloadPromise=p.waitForEvent('download');await p.locator('.partyReportActions .reportButton.download').click();const bulkDownload=await bulkDownloadPromise;await bulkDownload.saveAs(dir+'/all-customer-invoices.pdf');const bulkPdf=await readFile(dir+'/all-customer-invoices.pdf');assert.match(bulkPdf.toString('latin1'),new RegExp('/Count '+bulkPages+'\\b'));checks.allInvoicePdfPages=bulkPages;console.log('PASS bulk invoice PDF pages',bulkPages);
 await noOverflow(p,360);await noOverflow(p,1366);await noOverflow(p,390);
 await p.getByLabel('بحث حركات الحساب').fill('5001');await p.locator('.partyInvoiceCard .partyInvoiceItem').first().waitFor();assert.equal(await p.locator('.partyInvoiceCard').count(),1);assert.match(await p.locator('.partyInvoiceCard').innerText(),/مادة الجملة 1/);await p.screenshot({path:dir+'/customer-invoices-mobile.png',animations:'disabled'});await documentActions(p,admin.ctx,'customer-invoice');
 await p.getByLabel('بحث حركات الحساب').fill('');await p.getByRole('button',{name:'التسديدات',exact:true}).click();await p.locator('.miniMovementRow').filter({hasText:'تسديد'}).waitFor();await documentActions(p,admin.ctx,'customer-payments');
 await p.getByRole('button',{name:'رجوع للحساب',exact:true}).click();assert.equal(await p.getByTestId('statement-balance').innerText(),balance);await p.getByRole('button',{name:'كشف حساب',exact:true}).click();await p.locator('.miniStatementTable').waitFor();assert.equal(await p.locator('.miniStatementTable tbody tr').count(),112);assert.match(await p.locator('.miniStatementTable').innerText(),/مبلغ الوصل/);await noOverflow(p,360);await noOverflow(p,1366);await noOverflow(p,390);await documentActions(p,admin.ctx,'customer-statement');checks.customerDocuments=true;
 await p.goto(base+'/?section=suppliers');await p.getByLabel('بحث الموردين').fill('07700039803');await p.getByRole('button',{name:'حساب مورد الكشوف التجريبي',exact:true}).click();await p.getByTestId('supplier-statement-balance').waitFor();assert.match(await p.getByTestId('supplier-statement-balance').innerText(),/25/);
 await p.getByRole('button',{name:'مشتريات',exact:true}).click();assert.equal(await p.locator('.partyInvoiceCard').count(),2);const text=await p.locator('.partyInvoiceCard').allInnerTexts();assert.ok(text.some(t=>t.includes('لوح دولاري')&&t.includes('10 $')));assert.ok(text.some(t=>t.includes('بطارية دينار')&&t.includes('15,000 د.ع')));await noOverflow(p,360);await noOverflow(p,1366);await noOverflow(p,390);await p.screenshot({path:dir+'/supplier-invoices-mobile.png',animations:'disabled'});await documentActions(p,admin.ctx,'supplier-invoices');
 await p.getByRole('button',{name:'التسديدات',exact:true}).click();await documentActions(p,admin.ctx,'supplier-payments');await p.getByRole('button',{name:'رجوع للحساب',exact:true}).click();await p.getByRole('button',{name:'كشف حساب',exact:true}).click();await documentActions(p,admin.ctx,'supplier-statement');checks.supplierDocumentsAndCurrencies=true;
 const own=await open('00000000-0000-0000-0000-000000003981','/?section=customers'),q=own.p;await q.getByLabel('بحث الزبائن المسجلين').fill('07700039801');await q.getByRole('button',{name:'حساب عميل الجملة التجريبي',exact:true}).click();await q.getByRole('button',{name:'مبيعات',exact:true}).click();await q.locator('.partyInvoiceCard').filter({hasText:'تفاصيل المواد غير متاحة ضمن صلاحيات الحساب'}).waitFor({timeout:30000});assert.equal(await q.getByText('مادة خاصة بموظف آخر',{exact:true}).count(),0);checks.creatorAccessPreserved=true;
 assert.equal(hash(),before,'Financial fixture changed while viewing reports');assert.deepEqual(errors,[]);checks.noFinancialWrites=true;
 await writeFile(dir+'/results.json',JSON.stringify({pass:true,checks,calls,errors},null,2));console.log('PASS',JSON.stringify(checks));
}catch(error){await page?.screenshot({path:dir+'/failure.png',fullPage:true,timeout:5000}).catch(()=>{});await writeFile(dir+'/failure.json',JSON.stringify({error:String(error),stack:error.stack,calls,errors,checks},null,2));throw error;}finally{for(const ctx of contexts)await ctx.unrouteAll({behavior:'ignoreErrors'}).catch(()=>{});await browser.close();}
