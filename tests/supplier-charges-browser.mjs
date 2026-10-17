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

const browser=await chromium.launch({executablePath:process.env.SOLAR_CHROMIUM||'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
const errors=[];const rpcCalls=[];const contexts=[];let dropOnce=true;
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
    if(name==='solar_supplier_account')body=await jsonSql(`select public.solar_supplier_account(${Number(data.supplier_id)},${data.payment_id??'null'})`,uid);
    else if(name==='solar_supplier_movement_save'){body=await jsonSql(`select public.solar_supplier_movement_save(${sqlLiteral(data.request_id)}::uuid,${Number(data.payment_id)},${Number(data.supplier_id)},${Number(data.amount)},${sqlLiteral(data.movement_mode)},${sqlLiteral(data.note)},${data.expected_token?sqlLiteral(data.expected_token):'null'})`,uid);if(dropOnce&&data.movement_mode.startsWith('charge_')){dropOnce=false;return route.abort('failed');}}
    else if(name==='solar_supplier_payment_get')body=await jsonSql(`select public.solar_supplier_payment_get(${Number(data.payment_id)})`,uid);
    else if(name==='solar_party_balances')body=await jsonSql(`select public.solar_party_balances(${sqlLiteral(data.report_kind)},${sqlLiteral(data.as_of)}::date)`,uid);
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
const payer='00000000-0000-0000-0000-000000003341',supplierId=-334001;
await sql(`insert into public.profiles(id,display_name,is_admin,permissions,user_type) values('${payer}','موظف المورد',false,'{"supplierPayment":true,"supplierStatement":true,"supplierBalances":true}','admin_staff');
 insert into public.suppliers(id,name,phone) values(${supplierId},'شركة المورد التجريبية','07705556677');
 insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,created_by,cashbox_user_id) values(-334001,'purchase','supplier',${supplierId},'شركة المورد التجريبية',100000,false,'${payer}','${payer}');`);
async function pick(page){await page.locator('.partySearch input').fill('المورد');await page.getByRole('option').filter({hasText:'شركة المورد التجريبية'}).click();}
try{
 const page=await session(payer,1366);await section(page,'تسديد مورد');await pick(page);await page.getByRole('button',{name:/^إضافة على حساب المورد/}).click();await page.getByLabel('مبلغ حركة المورد').fill('20000');await page.getByLabel('سبب إضافة حساب المورد').selectOption('charge_old_balance');await page.getByLabel('ملاحظات حركة المورد').fill('رصيد قديم مستحق للمورد');await page.getByTestId('supplier-projected').filter({hasText:'120,000'}).waitFor();assert.equal(await page.getByLabel('مبلغ حركة المورد').inputValue(),'20,000');await ready(page);
 const before=await jsonSql(`select count(*) from public.transactions where party_id=${supplierId}`);
 const popupPromise=page.waitForEvent('popup');await page.getByRole('button',{name:'معاينة',exact:true}).click();const popup=await popupPromise;await popup.locator('#pdfDownload:not([disabled])').waitFor();await popup.close();assert.equal(await jsonSql(`select count(*) from public.transactions where party_id=${supplierId}`),before,'Preview must not submit the form');
 await page.getByRole('button',{name:'مشاركة',exact:true}).click();await page.waitForFunction(()=>window.__shareEvidence);assert.equal(await page.evaluate(()=>window.__shareEvidence.active),true);
 for(const width of [390,360]){await page.setViewportSize({width,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true,'supplier overflow '+width);}
 await page.screenshot({path:artifacts+'/supplier-charge-mobile.png',fullPage:true});await page.setViewportSize({width:1366,height:900});await page.evaluate(()=>window.scrollTo(0,0));await page.screenshot({path:artifacts+'/supplier-charge-desktop.png',fullPage:true});
 await page.getByRole('button',{name:'إضافة المبلغ إلى حساب المورد',exact:true}).click();await page.getByRole('alert').filter({hasText:'لم يتأكد رد الحفظ'}).waitFor();assert.equal(await page.getByLabel('مبلغ حركة المورد').isDisabled(),true);await page.getByRole('button',{name:'إعادة تأكيد الحفظ',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ الإضافة'}).waitFor();
 let account=await jsonSql(`select public.solar_supplier_account(${supplierId})`,payer);assert.equal(account.balance,120000);assert.equal(account.cashBalance,0);
 assert.equal(await jsonSql(`select count(*) from public.transactions where party_id=${supplierId} and kind='supplier_payment'`),1);
 const calls=rpcCalls.filter(r=>r.name==='solar_supplier_movement_save');assert.equal(calls.length,2);assert.equal(calls[0].data.request_id,calls[1].data.request_id);await ready(page);await download(page,'حفظ PDF','supplier-charge-saved.pdf');
 await sql(`insert into public.solar_cash_entries(owner_id,delta,entry_type,actor_id) values('${payer}',50000,'test_funding','${payer}')`);
 await home(page);await section(page,'تسديد مورد');await pick(page);await page.getByLabel('مبلغ حركة المورد').fill('10000');await page.getByRole('button',{name:'حفظ التسديد وخصمه من القاصة',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ التسديد'}).waitFor();account=await jsonSql(`select public.solar_supplier_account(${supplierId})`,payer);assert.equal(account.balance,110000);assert.equal(account.cashBalance,40000);
 await home(page);await section(page,'كشف حساب مورد');await pick(page);await page.getByText('إضافة على حساب المورد — حساب قديم',{exact:true}).waitFor();const row=page.locator('.supplierMovement').filter({hasText:'إضافة على حساب المورد — حساب قديم'});await row.getByRole('button',{name:'تعديل الحركة',exact:true}).click();await page.getByRole('heading',{name:'تعديل حركة المورد',exact:true}).waitFor();assert.equal(await page.getByLabel('مبلغ حركة المورد').inputValue(),'20,000');await page.getByLabel('مبلغ حركة المورد').fill('30000');await page.getByRole('button',{name:'حفظ تعديل الوصل',exact:true}).click();await page.getByRole('status').filter({hasText:'تم تعديل الإضافة'}).waitFor();account=await jsonSql(`select public.solar_supplier_account(${supplierId})`,payer);assert.equal(account.balance,120000);assert.equal(account.cashBalance,40000);
 assert.deepEqual(errors,[]);console.log('PASS supplier browser → API → isolated PostgreSQL: zero-cash addition, form preview/share without saving, grouped money, lost-response exact retry, saved PDF, cash payment, statement label, editing a charge, cash preservation and mobile.');
}finally{await browser.close();}
