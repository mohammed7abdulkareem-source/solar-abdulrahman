// Isolated browser → Supabase-shaped API → local PostgreSQL → UI verification.
// Requires playwright-core, Chromium, and the currency fixture database.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const database=process.env.SOLAR_TEST_DATABASE||'solar_system_payment_browser';
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
    if(name==='solar_system_payment_context')body=await jsonSql(`select public.solar_system_payment_context(${data.customer_id??'null'})`,uid);
    else if(name==='solar_system_payment_save'){body=await jsonSql(`select public.solar_system_payment_save(${sqlLiteral(data.request_id)}::uuid,${sqlLiteral(JSON.stringify(data.payload))}::jsonb)`,uid);if(dropOnce){dropOnce=false;return route.abort('failed');}}
    else if(name==='solar_fx')body=await jsonSql(`select public.solar_fx(${sqlLiteral(data.action)},${data.request_id?sqlLiteral(data.request_id)+'::uuid':'null'},${sqlLiteral(JSON.stringify(data.payload||{}))}::jsonb)`,uid);
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
 await page.goto(process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3007');await page.getByRole('button',{name:'سعر الصرف',exact:true}).waitFor();return page;
}

const artifacts='/workspace/solar-review/system-payment-v3341';await mkdir(artifacts,{recursive:true});
const receiver='00000000-0000-0000-0000-000000003411',manager='00000000-0000-0000-0000-000000003410';
await sql(`insert into public.profiles(id,display_name,is_admin,permissions) values('${receiver}','مستلم المنظومات',false,'{"systemPayment":true,"customerStatement":true,"cash":true}'),('${manager}','مدير الاختبار',true,'{}');
insert into public.customers(id,name,phone,customer_type,owner_id) values(-341001,'كوبا كافي الاختبار','07701112223','system','${receiver}'),(-341002,'زبون منظومتين','07801112223','system','${receiver}');
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id) values(-341001,'system_payment',-341001,'كوبا كافي الاختبار',-18000000,false,'opening_balance','${manager}','${manager}'),(-341002,'system',-341002,'اسم قديم للزبون',3000000,false,'credit','${manager}','${manager}'),(-341003,'system',-341002,'زبون منظومتين',2000000,false,'credit','${receiver}','${receiver}');`);
async function home(page){await page.getByRole('button',{name:'← الرئيسية',exact:true}).click();}
async function section(page,name){await page.getByRole('button',{name:'التسديدات والحسابات',exact:true}).click();await page.getByRole('button',{name,exact:true}).click();}
async function pick(page,name){await page.getByRole('combobox',{name:'بحث عميل الكشف',exact:true}).fill(name);await page.getByRole('option').filter({hasText:name}).first().click();}
async function ready(page){await page.locator('.reportExportButtons button.download:not([disabled])').waitFor({timeout:60000});}
async function noOverflow(page){assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));}
try{
 const page=await session(receiver,390);page.setDefaultTimeout(10000);await section(page,'تسديد منظومة');await pick(page,'كوبا كافي الاختبار');await page.getByTestId('system-account-balance').filter({hasText:'18,000,000'}).waitFor();
 assert.equal(await page.getByLabel('تخصيص تسديد المنظومات').inputValue(),'');assert.equal(await page.getByLabel('تخصيص تسديد المنظومات').locator('option').count(),1);
 await page.getByLabel('مبلغ حركة المنظومات').fill('1500000');await page.getByLabel('ملاحظات حركة المنظومات').fill('بيد المستلم');await page.getByTestId('system-projected-balance').filter({hasText:'16,500,000'}).waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/opening-payment-mobile.png',fullPage:true});
 await ready(page);const popupPromise=page.waitForEvent('popup');await page.getByRole('button',{name:'معاينة',exact:true}).click();const popup=await popupPromise;await popup.locator('#pdfDownload:not([disabled])').waitFor();await popup.close();
 assert.equal(await jsonSql(`select public.solar_system_payment_context(-341001)->>'cashBalance'`,receiver),0,'Preview must not save');
 await page.getByRole('button',{name:'حفظ التسديد',exact:true}).click();await page.getByRole('alert').filter({hasText:'لم يتأكد رد الحفظ'}).waitFor();assert.ok(await page.getByLabel('مبلغ حركة المنظومات').isDisabled());await page.getByRole('button',{name:'إعادة تأكيد الحفظ',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ تسديد المنظومات'}).waitFor();
 assert.equal(await page.getByTestId('system-saved-balance').textContent(),'16,500,000 د.ع');let account=await jsonSql(`select public.solar_system_payment_context(-341001)`,receiver);assert.equal(account.balance,16500000);assert.equal(account.cashBalance,1500000);
 const saveCalls=rpcCalls.filter(c=>c.name==='solar_system_payment_save');assert.equal(saveCalls.length,2);assert.equal(saveCalls[0].data.request_id,saveCalls[1].data.request_id);
 assert.equal(await jsonSql(`select count(*) from public.transactions where party_id=-341001 and payment_mode='payment'`),1);
 await ready(page);const downloadPromise=page.waitForEvent('download');await page.getByRole('button',{name:'حفظ PDF',exact:true}).click();const download=await downloadPromise;await download.saveAs(artifacts+'/opening-system-payment.pdf');assert.equal((await readFile(artifacts+'/opening-system-payment.pdf')).subarray(0,8).toString(),'%PDF-1.4');
 await page.getByRole('button',{name:'مشاركة',exact:true}).click();await page.waitForFunction(()=>window.__shareEvidence);assert.ok(await page.evaluate(()=>window.__shareEvidence.active));await page.screenshot({path:artifacts+'/saved-mobile.png',fullPage:true});
 await home(page);await section(page,'كشف حساب عميل');await pick(page,'كوبا كافي الاختبار');await page.getByTestId('statement-balance').filter({hasText:'16,500,000'}).waitFor();
 await home(page);await section(page,'تسديد منظومة');await pick(page,'زبون منظومتين');await page.getByLabel('تخصيص تسديد المنظومات').locator('option').nth(2).waitFor({state:'attached'});await page.getByLabel('تخصيص تسديد المنظومات').selectOption('-341002');await page.getByLabel('مبلغ حركة المنظومات').fill('1000000');await page.getByRole('button',{name:'حفظ التسديد',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ تسديد المنظومات'}).waitFor();
 await page.reload();await section(page,'تسديد منظومة');await pick(page,'زبون منظومتين');await page.getByLabel('تخصيص تسديد المنظومات').selectOption('-341002');await page.getByText('رصيدها الحالي: 2,000,000 د.ع',{exact:false}).waitFor();
 account=await jsonSql(`select public.solar_system_payment_context(-341002)`,receiver);assert.equal(account.systems.find(i=>i.id===-341002).remaining,2000000);assert.equal(account.balance,4000000);
 await page.getByLabel('مبلغ حركة المنظومات').fill('2500000');assert.ok(await page.getByRole('button',{name:'حفظ التسديد',exact:true}).isDisabled());await page.getByRole('button',{name:/إضافة على حسابه/}).click();await page.getByLabel('مبلغ حركة المنظومات').fill('250000');await page.getByLabel('سبب إضافة المنظومات').selectOption('charge_old_balance');await page.getByLabel('ملاحظات حركة المنظومات').fill('حساب قديم مثبت');await page.getByRole('button',{name:'إضافة المبلغ على الحساب',exact:true}).click();await page.getByRole('status').filter({hasText:'تمت الإضافة إلى حساب الزبون'}).waitFor();
 account=await jsonSql(`select public.solar_system_payment_context(-341002)`,receiver);assert.equal(account.balance,4250000);assert.equal(account.cashBalance,2500000);assert.equal(account.systems.find(i=>i.id===-341002).remaining,2250000);
 for(const width of [360,430,1366]){await page.setViewportSize({width,height:900});await noOverflow(page);}assert.deepEqual(errors,[]);
 console.log('PASS opening-only settlement, persistent invoice allocation, statement/cash, charge, failed-response retry, PDF/share and mobile layout');
}finally{await browser.close();}
