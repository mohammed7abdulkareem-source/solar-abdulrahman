// Isolated browser → Supabase-shaped API → local PostgreSQL → UI verification.
// Requires playwright-core, Chromium, and the currency fixture database.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const database=process.env.SOLAR_TEST_DATABASE||'solar_accounts_test';
if(!/^solar_[a-z_]+$/.test(database))throw new Error('Use a dedicated local solar_* test database');
const container=process.env.SOLAR_TEST_CONTAINER||'solar-customers-postgres';
const admin='00000000-0000-0000-0000-000000003330',buyer='00000000-0000-0000-0000-000000003331';
function sqlLiteral(value){return "'"+String(value).replaceAll("'","''")+"'";}
function sql(query,uid){return new Promise((resolve,reject)=>{
 const env={...process.env};for(const name of ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH'])delete env[name];
 const child=spawn('docker',['--host=unix:///var/run/docker.sock','exec','-i',container,'psql','-U','postgres','-d',database,'-qAt','-v','ON_ERROR_STOP=1'],{env});
 let out='',err='';child.stdout.on('data',x=>out+=x);child.stderr.on('data',x=>err+=x);
 child.on('close',code=>code?reject(new Error(err)):resolve(out.trim()));
 const prefix=uid?`begin;set local role authenticated;do $$begin perform set_config('request.jwt.claim.sub',${sqlLiteral(uid)},true);end$$;`:'';
 child.stdin.end(prefix+query+(uid?';commit;':''));
});}
async function jsonSql(query,uid){const result=await sql(query,uid);return JSON.parse(result||'null');}
if(process.env.SOLAR_TEST_REUSE_FIXTURE!=='1')await sql(await readFile(new URL('./fixtures/accounts-browser-seed.sql',import.meta.url),'utf8'));
const browser=await chromium.launch({executablePath:process.env.SOLAR_CHROMIUM||'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
const errors=[];const rpcCalls=[];const contexts=[];
async function session(uid,width=1366){
 const context=await browser.newContext({viewport:{width,height:900}});contexts.push(context);
 const token=Buffer.from(JSON.stringify({alg:'HS256'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:uid,role:'authenticated',exp:Math.floor(Date.now()/1000)+36000})).toString('base64url')+'.fixture';
 await context.addInitScript(({uid,token})=>{localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify({access_token:token,refresh_token:'fixture',expires_at:Math.floor(Date.now()/1000)+36000,expires_in:36000,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}}));},{uid,token});
 await context.addInitScript(()=>{
  window.__shareAvailable=true;
  Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>window.__shareAvailable});
  Object.defineProperty(navigator,'share',{configurable:true,value:async data=>{
   const file=data.files[0];const evidence={active:navigator.userActivation.isActive,name:file.name,type:file.type,size:file.size};
   const bytes=await file.arrayBuffer();evidence.hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(x=>x.toString(16).padStart(2,'0')).join('');window.__shareEvidence=evidence;
  }});
 });
 await context.routeWebSocket(/supabase/,ws=>ws.close());
 await context.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),url=new URL(req.url());let body;const headers={'access-control-allow-origin':'*','content-type':'application/json'};
  try{
   if(req.method()==='OPTIONS')return route.fulfill({status:204,headers});
   if(url.pathname==='/auth/v1/user')body={id:uid,email:'fixture@local.test',aud:'authenticated'};
   else if(url.pathname.includes('/rpc/')){
    const name=url.pathname.split('/').at(-1),data=req.postDataJSON()||{};
    rpcCalls.push({name,data});
    if(name==='solar_party_balances')body=await jsonSql(`select public.solar_party_balances(${sqlLiteral(data.report_kind)},${sqlLiteral(data.as_of)}::date)`,uid);
    else if(name==='solar_statement_customers')body=await jsonSql('select public.solar_statement_customers()',uid);
    else if(name==='solar_customer_statement')body=await jsonSql(`select public.solar_customer_statement(${Number(data.customer_id)})`,uid);
    else if(name==='solar_exchange_rate_get')body=await jsonSql('select public.solar_exchange_rate_get()',uid);
    else if(name==='solar_exchange_rate_set')body=await jsonSql(`select public.solar_exchange_rate_set(${Number(data.rate)},${Number(data.expected_revision)})`,uid);
    else if(name==='solar_invoice_save')body=await jsonSql(`select public.solar_invoice_save(${sqlLiteral(data.request_id)}::uuid,${sqlLiteral(JSON.stringify(data.payload))}::jsonb)`,uid);
    else if(name==='solar_customer_directory')body=await jsonSql('select public.solar_customer_directory()',uid);
    else if(name==='solar_customer_check')body=await jsonSql(`select public.solar_customer_check(${sqlLiteral(data.customer_name)},${sqlLiteral(data.phone)},${data.exclude_id??'null'})`,uid);
    else if(name==='solar_customer_get')body=await jsonSql(`select public.solar_customer_get(${Number(data.customer_id)})`,uid);
    else if(name==='solar_customer_save')body=await jsonSql(`select public.solar_customer_save(${sqlLiteral(data.action)},${sqlLiteral(data.request_id)}::uuid,${sqlLiteral(JSON.stringify(data.payload))}::jsonb)`,uid);
    else if(name==='solar_staff_directory')body=await jsonSql("select jsonb_agg(to_jsonb(p)) from public.profiles p");
    else if(name.includes('notification'))body=[];
    else throw new Error('Unexpected RPC '+name);
   }else{
    const table=url.pathname.split('/').at(-1);
    assert.ok(['profiles','brands','products','customers','suppliers','transactions','transaction_items','solar_cash_entries','solar_notifications','solar_push_subscriptions'].includes(table));
    if(table==='solar_notifications'||table==='solar_push_subscriptions')body=[];
    else if(table==='profiles')body=await jsonSql(`select to_jsonb(p) from public.profiles p where id=${sqlLiteral(uid)}::uuid`);
    else body=await jsonSql(`select coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) from public.${table} p`);
   }
   await route.fulfill({status:200,headers,body:JSON.stringify(body)});
  }catch(e){errors.push(e.message);await route.fulfill({status:400,headers,body:JSON.stringify({code:'P0001',message:e.message})});}
 });
 // No unmocked request may reach production during verification.
 await context.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());
 await page.goto(process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3001');await page.getByRole('button',{name:'سعر الصرف',exact:true}).waitFor();return page;
}

const artifacts='/workspace/solar-review/accounts-v333';await mkdir(artifacts,{recursive:true});
const format=value=>Number(value).toLocaleString('en-US',{maximumFractionDigits:2});
async function home(page){await page.getByRole('button',{name:'← الرئيسية',exact:true}).click();}
async function section(page,name){await page.getByRole('button',{name:'التسديدات والحسابات',exact:true}).click();await page.getByRole('button',{name,exact:true}).click();}
async function ready(page){await page.locator('.reportExportButtons button.download:not([disabled])').waitFor({timeout:60000});}
async function download(page,label,file){const pending=page.waitForEvent('download');await page.getByRole('button',{name:label,exact:true}).click();const item=await pending;assert.ok(item.suggestedFilename().endsWith('.pdf'));await item.saveAs(artifacts+'/'+file);const bytes=await readFile(artifacts+'/'+file);assert.equal(bytes.subarray(0,8).toString(),'%PDF-1.4');return bytes;}
try{
 const page=await session(admin);await section(page,'مدينون العملاء');await ready(page);
 assert.equal(await page.locator('.debtorTable .accountDataRow').count(),31);assert.match(await page.getByTestId('debt-total').innerText(),/11,226,000/);
 assert.equal(await page.locator('.accountLegacy').count(),1);await page.locator('.accountLegacy summary').click();await page.getByText('افتتاحي لزبون غير موجود',{exact:true}).waitFor();
 await page.getByRole('button',{name:'مشاركة',exact:true}).click();await page.waitForFunction(()=>window.__shareEvidence);const evidence=await page.evaluate(()=>window.__shareEvidence);assert.equal(evidence.active,true);assert.equal(evidence.type,'application/pdf');
 const bytes=await download(page,'حفظ PDF','debtors-all.pdf');assert.equal(createHash('sha256').update(bytes).digest('hex'),evidence.hash);assert.ok(Number(bytes.toString('latin1').match(/\/Count (\d+)/)[1])>1);
 const pending=page.waitForEvent('popup');await page.getByRole('button',{name:'معاينة',exact:true}).click();const popup=await pending;await popup.locator('#pdfDownload:not([disabled])').waitFor();assert.ok(await popup.locator('.pdfPages img').count()>1);const previewBytes=await download(popup,'حفظ PDF','debtors-preview.pdf');assert.equal(createHash('sha256').update(previewBytes).digest('hex'),evidence.hash);await popup.close();
 await page.evaluate(()=>window.__shareAvailable=false);await download(page,'مشاركة','debtors-share-fallback.pdf');await page.getByRole('status').filter({hasText:'المشاركة المباشرة غير متاحة'}).waitFor();await page.evaluate(()=>window.__shareAvailable=true);
 const all=await jsonSql("select public.solar_party_balances('customers',current_date)",admin);
 await page.getByLabel('مستخدم تقرير المدينين').selectOption(buyer);await page.locator('.accountSegments').getByRole('button',{name:'جملة',exact:true}).click();
 const expected=all.rows.filter(r=>r.owner_id===buyer&&r.customer_type==='wholesale'&&r.balance>0);assert.equal(await page.locator('.debtorTable .accountDataRow').count(),expected.length);assert.match(await page.getByTestId('debt-total').innerText(),new RegExp(format(expected.reduce((n,r)=>n+r.balance,0))));await ready(page);
 await page.screenshot({path:artifacts+'/debtors-desktop.png',fullPage:true});
 await page.getByLabel('بحث الأرصدة',{exact:true}).fill('+9647701234567');assert.equal(await page.locator('.debtorTable .accountDataRow').count(),1);await ready(page);await download(page,'حفظ PDF','debtors-filtered.pdf');
 await page.getByLabel('بحث الأرصدة',{exact:true}).fill('');await page.locator('.accountSegments').getByRole('button',{name:'منظومات',exact:true}).click();assert.ok((await page.locator('.debtorTable .accountDataRow').count())>0);assert.equal(await page.locator('.debtorTable .accountTypeBadge.wholesale').count(),0);
 for(const width of [768,390,360]){await page.setViewportSize({width,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true,'debtors overflow '+width);}
 await ready(page);await page.screenshot({path:artifacts+'/debtors-mobile.png',fullPage:true});
 await home(page);await section(page,'كشف حساب عميل');
 const picker=page.getByRole('combobox',{name:'بحث عميل الكشف'});await picker.fill('احمدعلي');await page.getByRole('option').filter({hasText:'أحمد علي'}).click();await page.getByRole('heading',{name:'أحمد علي',exact:true}).waitFor();assert.match(await page.getByTestId('statement-balance').innerText(),/2,020,000/);await ready(page);
 const statement=await download(page,'حفظ PDF','customer-statement-all.pdf');assert.ok(Number(statement.toString('latin1').match(/\/Count (\d+)/)[1])>1);
 await page.getByRole('button',{name:'مشاركة',exact:true}).click();await page.waitForFunction(()=>window.__shareEvidence?.name.startsWith('كشف-حساب'));assert.equal(await page.evaluate(()=>window.__shareEvidence.active),true);
 await page.setViewportSize({width:1366,height:900});await page.screenshot({path:artifacts+'/statement-desktop.png',fullPage:true});
 await page.getByLabel('من تاريخ',{exact:true}).fill('2026-10-02');await page.getByLabel('إلى تاريخ',{exact:true}).fill('2026-10-03');assert.match(await page.getByTestId('statement-balance').innerText(),/2,000,000/);assert.equal(await page.locator('.statementTable .accountDataRow').count(),2);
 await page.getByRole('button',{name:/^التسديدات والحركات/}).click();assert.equal(await page.locator('.statementTable .accountDataRow').count(),1);assert.match(await page.getByTestId('statement-balance').innerText(),/2,000,000/);await ready(page);
 await picker.fill('٠٧٨٠١٢٣٤٥٦٧');await page.getByRole('option').filter({hasText:'سيف حسن'}).waitFor();assert.equal(await page.getByRole('heading',{name:'أحمد علي',exact:true}).count(),0);await page.keyboard.press('Enter');await page.getByRole('heading',{name:'سيف حسن',exact:true}).waitFor();await page.getByRole('button',{name:'كل الفترات',exact:true}).click();await page.getByRole('button',{name:/^الكشف الكامل/}).click();assert.match(await page.getByTestId('statement-balance').innerText(),/2,000,000/);await ready(page);
 for(const width of [768,390,360]){await page.setViewportSize({width,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true,'statement overflow '+width);}
 await page.screenshot({path:artifacts+'/statement-mobile.png',fullPage:true});
 const staffPage=await session(buyer,390);await section(staffPage,'مدينون العملاء');await ready(staffPage);assert.equal(await staffPage.getByLabel('مستخدم تقرير المدينين').count(),0);assert.equal(await staffPage.locator('.debtorTable').getByText('محمد كريم',{exact:true}).count(),0);await home(staffPage);await section(staffPage,'كشف حساب عميل');await staffPage.getByRole('combobox',{name:'بحث عميل الكشف'}).fill('محمد كريم');await staffPage.getByText('لا يوجد عميل مطابق للاسم أو الهاتف.',{exact:true}).waitFor();
 assert.deepEqual(errors,[]);console.log('PASS browser → API → isolated PostgreSQL → debtor owner/category filters and statement search; legacy appendix, multi-page PDF, identical preview/download, native file sharing with user activation, fallback downloads, permissions and mobile.');
}finally{await browser.close();}
