// Isolated browser → Supabase-shaped API → local PostgreSQL → UI verification.
// Requires playwright-core, Chromium, and the currency fixture database.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const database=process.env.SOLAR_TEST_DATABASE||'solar_customer_browser';
if(!/^solar_[a-z_]+$/.test(database))throw new Error('Use a dedicated local solar_* test database');
const container=process.env.SOLAR_TEST_CONTAINER||'solar-customers-postgres';
const admin='00000000-0000-0000-0000-000000003310',buyer='00000000-0000-0000-0000-000000003311';
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
await sql(`insert into public.profiles(id,display_name,is_admin,permissions,user_type) values
 ('${admin}','المدير التجريبي',true,'{}','admin_staff'),('${buyer}','موظف المبيعات',false,'{"customers":true}','admin_staff');
 insert into public.customers(id,name,customer_type,owner_id) select -4000-n,'زبون تجريبي '||n,'system','${admin}' from generate_series(1,15) n;`);
const browser=await chromium.launch({executablePath:process.env.SOLAR_CHROMIUM||'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
const errors=[];const rpcCalls=[];const contexts=[];
async function session(uid,width=1366){
 const context=await browser.newContext({viewport:{width,height:900}});contexts.push(context);
 const token=Buffer.from(JSON.stringify({alg:'HS256'})).toString('base64url')+'.'+Buffer.from(JSON.stringify({sub:uid,role:'authenticated',exp:Math.floor(Date.now()/1000)+36000})).toString('base64url')+'.fixture';
 await context.addInitScript(({uid,token})=>{localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify({access_token:token,refresh_token:'fixture',expires_at:Math.floor(Date.now()/1000)+36000,expires_in:36000,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}}));},{uid,token});
 await context.routeWebSocket(/supabase/,ws=>ws.close());
 await context.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),url=new URL(req.url());let body;const headers={'access-control-allow-origin':'*','content-type':'application/json'};
  try{
   if(req.method()==='OPTIONS')return route.fulfill({status:204,headers});
   if(url.pathname==='/auth/v1/user')body={id:uid,email:'fixture@local.test',aud:'authenticated'};
   else if(url.pathname.includes('/rpc/')){
    const name=url.pathname.split('/').at(-1),data=req.postDataJSON()||{};
    rpcCalls.push({name,data});
    if(name==='solar_exchange_rate_get')body=await jsonSql('select public.solar_exchange_rate_get()',uid);
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
 await page.goto('http://127.0.0.1:3000');await page.getByRole('button',{name:'سعر الصرف',exact:true}).waitFor();return page;
}

try{
 const page=await session(admin);
 await mkdir('/workspace/solar-review/screenshots',{recursive:true});
 await page.screenshot({path:'/workspace/solar-review/screenshots/home-v332.png',fullPage:true});
 await page.getByLabel('بحث أقسام البرنامج').fill('الزبائن');await page.getByRole('button',{name:'إضافة الزبائن',exact:true}).waitFor();await page.getByLabel('بحث أقسام البرنامج').fill('');
 await page.getByRole('button',{name:'إضافة',exact:true}).click();await page.getByRole('button',{name:'إضافة الزبائن',exact:true}).click();
 await page.getByRole('heading',{name:'إضافة زبون',exact:true}).waitFor();
 const name=page.getByLabel('اسم الزبون',{exact:true}),opening=page.getByLabel('مبلغ الرصيد الافتتاحي',{exact:true});
 await name.fill('أحمد علي');await page.getByLabel('رقم هاتف الزبون').fill('07701234567');await page.getByLabel('رصيد افتتاحي إن وجد').check();await opening.fill('2000000');
 assert.equal(await opening.inputValue(),'2,000,000');
 await page.getByRole('button',{name:'إضافة الزبون',exact:true}).click();await page.getByRole('status').filter({hasText:'تم تسجيل'}).waitFor();
 const card=page.locator('.customerCard').filter({hasText:'أحمد علي'});await card.waitFor();await card.getByRole('button',{name:'تعديل',exact:true}).click();
 await page.getByRole('heading',{name:'تعديل الزبون',exact:true}).waitFor();assert.equal(await opening.inputValue(),'2,000,000');await opening.fill('3000000');
 await page.getByRole('button',{name:'حفظ التعديل والرصيد',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ'}).waitFor();await card.locator('.customerCardBalance b').filter({hasText:'3,000,000'}).waitFor();
 await name.fill('احمدعلي');await page.getByText('هذا الزبون مسجّل مسبقاً',{exact:true}).waitFor();assert.equal(await page.getByRole('button',{name:'إضافة الزبون',exact:true}).isDisabled(),true);
 await page.getByRole('button',{name:'فتح الزبون المسجّل: أحمد علي',exact:true}).click();await page.getByRole('heading',{name:'تعديل الزبون',exact:true}).waitFor();
 await page.evaluate(()=>window.scrollTo(0,0));await page.screenshot({path:'/workspace/solar-review/screenshots/customers-v332-desktop.png',fullPage:true});
 await card.getByRole('button',{name:'الحساب والفواتير',exact:true}).click();await page.getByRole('dialog').waitFor();await page.keyboard.press('Escape');assert.equal(await page.getByRole('dialog').count(),0);
 await page.getByLabel('رصيد افتتاحي إن وجد').uncheck();await page.getByRole('button',{name:'حفظ التعديل والرصيد',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ'}).waitFor();
 const saved=await jsonSql("select public.solar_customer_get(id) from public.customers where name='أحمد علي'",admin);assert.equal(saved.openingBalance,0);assert.equal(saved.rows.length,1);
 await page.getByLabel('بحث الزبائن المسجلين').fill('07701234567');assert.equal(await page.locator('.customerCard').count(),1);
 await name.fill('زبون آخر');await page.getByLabel('رقم هاتف الزبون').fill('+9647701234567');await page.getByText('هذا الزبون مسجّل مسبقاً',{exact:true}).waitFor();
 await page.getByRole('button',{name:'＋ زبون جديد',exact:true}).click();await page.getByLabel('بحث الزبائن المسجلين').fill('');
 for(const width of [768,390,360]){await page.setViewportSize({width,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true,'Horizontal overflow '+width);}
 await page.screenshot({path:'/workspace/solar-review/screenshots/customers-v332-mobile.png',fullPage:true});
 const staffPage=await session(buyer,390);await staffPage.getByRole('button',{name:'إضافة',exact:true}).click();await staffPage.getByRole('button',{name:'إضافة الزبائن',exact:true}).click();await staffPage.getByRole('heading',{name:'أضف زبونك الأول',exact:true}).waitFor();await staffPage.getByLabel('اسم الزبون',{exact:true}).fill('احمد علي');await staffPage.getByText('الحساب لدى مستخدم آخر؛ راجع الإدارة.',{exact:true}).waitFor();assert.equal(await staffPage.getByRole('button',{name:/فتح الزبون المسجّل:/}).count(),0);
 assert.deepEqual(errors,[]);
 console.log('PASS: customer create, grouped input, opening edit/remove, duplicate Arabic name/phone, search, account modal, desktop and mobile through local PostgreSQL.');
}finally{await browser.close();}
