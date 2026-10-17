// Isolated browser → Supabase-shaped API → local PostgreSQL → UI verification.
// Requires playwright-core, Chromium, and the currency fixture database.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const database=process.env.SOLAR_TEST_DATABASE||'solar_fx_browser_final';
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
    if(name==='solar_fx')body=await jsonSql(`select public.solar_fx(${sqlLiteral(data.action)},${data.request_id?sqlLiteral(data.request_id)+'::uuid':'null'},${sqlLiteral(JSON.stringify(data.payload||{}))}::jsonb)`,uid);
    else if(name==='solar_supplier_account')body=await jsonSql(`select public.solar_supplier_account(${Number(data.supplier_id)},${data.payment_id??'null'})`,uid);
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
 await page.goto(process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3005');await page.getByRole('button',{name:'سعر الصرف',exact:true}).waitFor();return page;
}

const artifacts='/workspace/solar-review/currency-v334';await mkdir(artifacts,{recursive:true});
const adminFx='00000000-0000-0000-0000-000000003400',staffFx='00000000-0000-0000-0000-000000003401';
await sql(`insert into public.profiles(id,display_name,is_admin,permissions,user_type) values('${adminFx}','مدير العملات',true,'{}','admin_staff'),('${staffFx}','موظف العملات',false,'{"supplierPayment":true,"supplierStatement":true,"purchase":true,"cash":true,"supplierBalances":true}','admin_staff');
insert into public.suppliers(id,name,phone) values(-340001,'شركة المورد الدولاري','07705556677'),(-340002,'شركة المورد الديناري','07805556677');
insert into public.products(id,code,name,qty,cost) values(-340001,'FX-1','بطارية اختبار',0,0);
insert into public.transactions(id,kind,total,cash,created_by,cashbox_user_id) values(-340000,'cash_income',10000000,true,'${adminFx}','${adminFx}');`);
await sql(`select public.solar_exchange_rate_set(1500,0)`,adminFx);
async function home(p){await p.getByRole('button',{name:'← الرئيسية',exact:true}).click();}
async function section(p,name){await p.getByRole('button',{name:'التسديدات والحسابات',exact:true}).click();await p.getByRole('button',{name,exact:true}).click();}
async function pick(p,text){await p.locator('.partySearch input').fill(text);await p.getByRole('option').filter({hasText:text}).first().click();}
async function noOverflow(p){assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Horizontal overflow');}
try{
 const page=await session(adminFx,390);await noOverflow(page);await page.screenshot({path:artifacts+'/home-mobile.png',fullPage:true});for(const width of [360,430,1366]){await page.setViewportSize({width,height:900});await noOverflow(page);}await page.screenshot({path:artifacts+'/home-desktop.png',fullPage:true});await page.setViewportSize({width:390,height:844});
 const grid=await page.locator('.menuGrid').evaluate(e=>getComputedStyle(e).gridTemplateColumns.split(' ').length);assert.equal(grid,3);
 await page.getByRole('button',{name:'إضافة',exact:true}).click();await page.getByRole('button',{name:'إضافة الموردين',exact:true}).click();await pick(page,'شركة المورد الدولاري');
 await page.getByRole('button',{name:'مراجعة تحويل الحساب',exact:true}).waitFor();await page.locator('.fxCurrencyManager input').last().fill('اتفاق الحساب بالدولار');await page.getByRole('button',{name:'مراجعة تحويل الحساب',exact:true}).click();await page.getByRole('button',{name:'اعتماد عملة الحساب والتحويل',exact:true}).click();await page.getByRole('status').filter({hasText:'تم اعتماد عملة الحساب'}).waitFor();
 let a=await jsonSql(`select public.solar_fx('account',null,'{"supplierId":-340001}')`,adminFx);assert.equal(a.currency,'USD');await noOverflow(page);
 await home(page);await page.getByRole('button',{name:'فاتورة شراء',exact:true}).click();await pick(page,'شركة المورد الدولاري');await page.getByLabel('عملة الشراء').selectOption('USD');
 await page.getByRole('button',{name:/بطارية اختبار/}).click();await page.getByLabel('الكمية — بطارية اختبار').fill('1');await page.getByLabel('سعر الشراء — بطارية اختبار').fill('100');await noOverflow(page);

 await page.screenshot({path:artifacts+'/purchase-mobile.png',fullPage:true});await page.getByRole('button',{name:'حفظ الوصل',exact:true}).click();
 await page.getByLabel('الكمية — بطارية اختبار').waitFor({state:'detached'});
 await home(page);
 // Post a known purchase with the same authoritative endpoint for the settlement UI.
 await jsonSql(`select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"شركة المورد الدولاري","mode":"credit","sourceCurrency":"USD","exchangeRate":1500,"marketRate":1500,"accountRevision":1,"items":[{"id":-340001,"qty":9,"price":100}]}')`,adminFx);
 await section(page,'تسديد مورد');await pick(page,'شركة المورد الدولاري');await page.getByLabel('مبلغ حركة المورد').fill('750000');await page.getByTestId('supplier-projected').filter({hasText:'500'}).waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/payment-mobile.png',fullPage:true});
 await page.getByRole('button',{name:'حفظ التسديد وخصمه من القاصة',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ التسديد'}).waitFor();a=await jsonSql(`select public.solar_fx('account',null,'{"supplierId":-340001}')`,adminFx);assert.equal(a.balance,500);assert.equal(a.cashBalance,9250000);
 await page.locator('.reportExportButtons button.download:not([disabled])').waitFor({timeout:60000});const downloadPromise=page.waitForEvent('download');await page.getByRole('button',{name:'حفظ PDF',exact:true}).click();const download=await downloadPromise;await download.saveAs(artifacts+'/supplier-payment.pdf');assert.equal((await readFile(artifacts+'/supplier-payment.pdf')).subarray(0,8).toString(),'%PDF-1.4');
 await page.getByRole('button',{name:'مشاركة',exact:true}).click();await page.waitForFunction(()=>window.__shareEvidence);assert.ok(await page.evaluate(()=>window.__shareEvidence.active));
 await home(page);await section(page,'كشف حساب مورد');await pick(page,'شركة المورد الدولاري');await page.getByTestId('supplier-statement-balance').filter({hasText:'500'}).waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/statement-mobile.png',fullPage:true});
 await home(page);await section(page,'الموردون');await page.locator('.accountTable').getByText('USD',{exact:true}).waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/balances-mobile.png',fullPage:true});
 await home(page);await page.getByRole('button',{name:'الصندوق',exact:true}).click();await page.getByLabel('نوع حركة الدولار').selectOption('deposit');await page.getByLabel('مبلغ قاصة الدولار').fill('1000');await page.locator('.fxWallet input[required]').last().fill('رصيد افتتاحي دولار');await page.getByRole('button',{name:'حفظ حركة الدولار',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ حركة الدولار'}).waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/wallet-mobile.png',fullPage:true});
 await home(page);await section(page,'تسديد مورد');await pick(page,'شركة المورد الدولاري');await page.getByLabel('عملة حركة المورد').selectOption('USD');await page.getByLabel('مبلغ حركة المورد').fill('500');await page.getByTestId('supplier-projected').filter({hasText:'0 $'}).waitFor();await page.getByRole('button',{name:'حفظ التسديد وخصمه من القاصة',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ التسديد'}).waitFor();a=await jsonSql(`select public.solar_fx('account',null,'{"supplierId":-340001}')`,adminFx);assert.equal(a.balance,0);assert.equal(a.usdWallet.amount,500);assert.equal(a.cashBalance,9250000);
 const staffPage=await session(staffFx,360);await section(staffPage,'تسديد مورد');await pick(staffPage,'شركة المورد الدولاري');assert.ok(await staffPage.getByLabel('صرف حركة المورد').isDisabled());await noOverflow(staffPage);
 assert.deepEqual(errors,[]);console.log('PASS mobile layout, currency agreement, both settlement currencies, physical cash, PDF download and native share activation');
}finally{await browser.close();}
