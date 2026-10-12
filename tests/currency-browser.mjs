// Isolated browser → Supabase-shaped API → local PostgreSQL → UI verification.
// Requires playwright-core, Chromium, and the currency fixture database.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const database=process.env.SOLAR_TEST_DATABASE||'solar_browser';
if(!/^solar_[a-z_]+$/.test(database))throw new Error('Use a dedicated local solar_* test database');
const container=process.env.SOLAR_TEST_CONTAINER||'solar-fx-postgres';
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
 ('${admin}','FX Admin',true,'{}','admin_staff'),('${buyer}','FX Buyer',false,'{"purchase":true,"sale":true,"system":true,"salesDeleteOwn":true}','admin_staff');
 insert into public.suppliers(id,name) values(-3310,'FX Supplier');
 insert into public.customers(id,name,customer_type,owner_id) values(-3310,'FX Customer','wholesale','${buyer}');
 insert into public.products(id,code,name,qty,cost) values(-3310,'FX-3310','FX Panel',10,100000);`);
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
    else if(name==='solar_staff_directory')body=[];
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
async function home(page){await page.getByRole('button',{name:'← الرئيسية',exact:true}).click();}
async function selectParty(page,name){const input=page.locator('.partySearch input').first();await input.fill(name);await page.getByRole('option').filter({hasText:name}).click();}
async function invoice(page,currency,qty,price){
 await page.getByRole('button',{name:'فاتورة شراء',exact:true}).click();
 await page.getByLabel('عملة الشراء').selectOption(currency);
 await selectParty(page,'FX Supplier');await page.getByRole('button',{name:'إضافة FX Panel',exact:true}).click();
 await page.getByLabel('الكمية — FX Panel').fill(String(qty));await page.getByLabel('سعر الشراء — FX Panel').fill(String(price));
 if(currency==='USD'){assert.equal(await page.getByLabel('صرف فاتورة الشراء').isDisabled(),true);await page.getByText('متوسط الكلفة بعد الشراء: 110,000 د.ع / وحدة',{exact:true}).waitFor();}
 await page.getByRole('button',{name:'حفظ الوصل',exact:true}).click();
 await page.getByText('ابدأ بإضافة المواد',{exact:true}).waitFor();await home(page);
}
try{
 const adminPage=await session(admin);
 await adminPage.getByRole('button',{name:'سعر الصرف',exact:true}).click();await adminPage.getByLabel('سعر الصرف',{exact:true}).fill('1500');await adminPage.getByRole('button',{name:'حفظ سعر الصرف',exact:true}).click();await adminPage.getByRole('status').waitFor();await home(adminPage);
 const buyerPage=await session(buyer);
 await buyerPage.getByRole('button',{name:'سعر الصرف',exact:true}).click();assert.equal(await buyerPage.getByRole('button',{name:'حفظ سعر الصرف',exact:true}).count(),0);await home(buyerPage);
 await invoice(buyerPage,'USD',10,80);
 assert.deepEqual(await jsonSql('select jsonb_build_object(\'qty\',qty,\'cost\',cost) from public.products where id=-3310'),{qty:20,cost:110000});
 await buyerPage.getByRole('button',{name:'بيع جملة',exact:true}).click();
 assert.equal(await buyerPage.getByLabel('عملة الشراء').count(),0);await selectParty(buyerPage,'FX Customer');
 await buyerPage.getByRole('button',{name:'إضافة FX Panel',exact:true}).click();await buyerPage.getByLabel('الكمية — FX Panel').fill('5');await buyerPage.getByLabel('سعر البيع — FX Panel').fill('150000');
 await buyerPage.getByRole('button',{name:'حفظ الوصل',exact:true}).click();await buyerPage.getByText('ابدأ بإضافة المواد',{exact:true}).waitFor();await home(buyerPage);
 await adminPage.getByRole('button',{name:'سعر الصرف',exact:true}).click();await adminPage.getByLabel('سعر الصرف',{exact:true}).fill('1600');await adminPage.getByRole('button',{name:'حفظ سعر الصرف',exact:true}).click();await adminPage.getByRole('status').waitFor();await home(adminPage);
 await invoice(buyerPage,'IQD',5,150000);
 assert.deepEqual(await jsonSql('select jsonb_build_object(\'qty\',qty,\'cost\',cost) from public.products where id=-3310'),{qty:20,cost:120000});
 assert.deepEqual(await jsonSql("select jsonb_build_object('cost',cost,'profit',profit) from public.transactions where kind='sale'"),{cost:550000,profit:200000});
 await buyerPage.setViewportSize({width:390,height:844});await buyerPage.getByRole('button',{name:'فاتورة شراء',exact:true}).click();await buyerPage.getByLabel('عملة الشراء').selectOption('USD');await buyerPage.getByRole('button',{name:'إضافة FX Panel',exact:true}).click();await buyerPage.getByLabel('الكمية — FX Panel').fill('1');await buyerPage.getByLabel('سعر الشراء — FX Panel').fill('100');
 assert.equal(await buyerPage.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true);
 const popupPromise=buyerPage.waitForEvent('popup');await buyerPage.getByRole('button',{name:'معاينة A4',exact:true}).click();const popup=await popupPromise;await popup.locator('#pdfDownload:not([disabled])').waitFor();assert.ok(await popup.locator('.pdfPages img').count()>0);await popup.close();
 await mkdir('/workspace/solar-review/screenshots',{recursive:true});await buyerPage.screenshot({path:'/workspace/solar-review/screenshots/currency-purchase-mobile.png',fullPage:true});
 assert.deepEqual(errors,[]);assert.equal(rpcCalls.filter(x=>x.name==='solar_invoice_save').length,3);
 console.log('PASS: browser → API → isolated PostgreSQL → UI; USD purchase, weighted cost, IQD sale, rate change, later IQD purchase, historic profit, staff permissions and mobile form.');
}finally{await browser.close();}
