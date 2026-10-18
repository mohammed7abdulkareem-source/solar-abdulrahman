process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
// Isolated browser → Supabase-shaped API → local PostgreSQL → UI verification.
// Requires playwright-core, Chromium, and the currency fixture database.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const database=process.env.SOLAR_TEST_DATABASE||'solar_premium_browser';
const visualOnly=process.argv.includes('--visual');
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
const errors=[];const rpcCalls=[];const contexts=[];let dropOnce=false,dropReceiptEditOnce=false,dropReconcileOnce=false,dropSupplierEditOnce=false;
async function session(uid,width=1366){
 const context=await browser.newContext({viewport:{width,height:900}});context.setDefaultTimeout(15000);contexts.push(context);
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
 await context.addInitScript(({uid})=>{
  window.__sounds=0;
  const start=OscillatorNode.prototype.start;
  OscillatorNode.prototype.start=function(...args){window.__sounds++;return start.apply(this,args)};
  Object.defineProperty(Notification,'permission',{configurable:true,get:()=> 'granted'});
  Notification.requestPermission=async()=> 'granted';
  const sub={endpoint:'https://fcm.googleapis.com/local-'+uid,toJSON(){return {endpoint:this.endpoint,keys:{p256dh:'fixture',auth:'fixture'}}},unsubscribe:async()=>true};
  PushManager.prototype.getSubscription=async()=> window.__registered?sub:null;
  PushManager.prototype.subscribe=async()=>{window.__registered=true;return sub};
 },{uid});
 await context.routeWebSocket(/supabase/,ws=>ws.close());
 await context.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),url=new URL(req.url());let body;const headers={'access-control-allow-origin':'*','content-type':'application/json'};
  try{
   if(req.method()==='OPTIONS')return route.fulfill({status:204,headers});
   if(url.pathname==='/auth/v1/user')body={id:uid,email:'fixture@local.test',aud:'authenticated'};
   else if(url.pathname.includes('/functions/v1/solar-admin-users')){assert.equal(req.postDataJSON().action,'list');body={users:await jsonSql('select jsonb_agg(to_jsonb(p)) from public.profiles p')};}
   else if(url.pathname.includes('/functions/v1/solar-login'))body={access_token:token};
   else if(url.pathname.includes('/rpc/')){
    const name=url.pathname.split('/').at(-1),data=req.postDataJSON()||{};
    rpcCalls.push({name,data});
    if(name==='solar_staff_directory')body=await jsonSql("select jsonb_agg(to_jsonb(p)) from public.profiles p");
    else if(name.includes('notification'))body=[];
    else if(name==='solar_push_public_key')body=Buffer.alloc(65,4).toString('base64url');
    else if(name==='solar_push_register'){await sql(`insert into solar_push_subscriptions(endpoint,user_id,p256dh,auth_key) values(${sqlLiteral(data.subscription.endpoint)},${sqlLiteral(uid)},'fixture','fixture') on conflict(endpoint) do update set user_id=excluded.user_id`);body=true;}
    else if(['solar_stock_movements'].includes(name))body=[];
    else if(name==='solar_stock_quantities')body=await jsonSql("select jsonb_agg(to_jsonb(p)) from public.products p");
    else {
     assert.match(name,/^solar_[a-z_]+$/);const args=Object.entries(data).map(([key,value])=>{assert.match(key,/^[a-z_]+$/);return key+'=>'+(name==='solar_warehouse_statuses'&&key==='invoice_ids'?'array['+value.map(n=>{assert.ok(Number.isSafeInteger(n));return n}).join(',')+']::bigint[]':value===null?'null':typeof value==='object'?sqlLiteral(JSON.stringify(value))+'::jsonb':typeof value==='number'?String(value):sqlLiteral(value));}).join(',');
     if(['solar_cash_transfer_decide','solar_warehouse_action','solar_installation_action'].includes(name)){await sql('select public.'+name+'('+args+')',uid);body=null;}else body=await jsonSql('select to_jsonb(public.'+name+'('+args+'))',uid);
     if(name==='solar_invoice_save'&&dropOnce){dropOnce=false;return route.abort('failed');}
     if(name==='solar_supplier_payment_manage'&&data.action==='update'&&dropSupplierEditOnce){dropSupplierEditOnce=false;return route.abort('failed');}
     if(name==='solar_cash_reconcile'&&data.action==='apply'&&dropReconcileOnce){dropReconcileOnce=false;return route.abort('failed');}
     if(name==='solar_customer_payment_manage'&&data.action==='update'&&dropReceiptEditOnce){dropReceiptEditOnce=false;return route.abort('failed');}
    }
   }else{
    const table=url.pathname.split('/').at(-1);
    assert.ok(['profiles','brands','products','customers','suppliers','transactions','transaction_items','solar_cash_entries','solar_notifications','solar_push_subscriptions','solar_quotes','solar_price_estimates','solar_estimate_specs'].includes(table));
    if(table==='solar_notifications'){
     if(req.method()==='PATCH'){const id=url.searchParams.get('id').replace('eq.','');await sql(`update solar_notifications set read_at=now() where id=${sqlLiteral(id)} and user_id=${sqlLiteral(uid)}`);body=[];}
     else body=await jsonSql(`select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at desc),'[]') from (select * from solar_notifications where user_id=${sqlLiteral(uid)} order by created_at desc limit 30)n`);
    }else if(table==='solar_push_subscriptions')body=await jsonSql(`select to_jsonb(p) from solar_push_subscriptions p where user_id=${sqlLiteral(uid)} limit 1`);
    else if(['solar_quotes','solar_price_estimates','solar_estimate_specs'].includes(table))body=[];
    else if(table==='profiles')body=await jsonSql(`select to_jsonb(p) from public.profiles p where id=${sqlLiteral(uid)}::uuid`);
    else body=await jsonSql(`select coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) from public.${table} p`);
   }
   await route.fulfill({status:200,headers,body:JSON.stringify(body)});
  }catch(e){errors.push(e.message);await route.fulfill({status:400,headers,body:JSON.stringify({code:'P0001',message:e.message})});}
 });
 // No unmocked request may reach production during verification.
 await context.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());
 await page.goto(process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3013');await page.locator('.premiumDashboard').waitFor();await page.evaluate(()=>document.fonts.ready);return page;
}

const owner='00000000-0000-0000-0000-000000003500',staff='00000000-0000-0000-0000-000000003501';
const artifacts='/workspace/solar-review/warehouse-v345';await mkdir(artifacts,{recursive:true});
await sql(`insert into profiles(id,display_name,username,is_admin,permissions,user_type) values('${owner}','مدير التجهيز','warehouse_admin',true,'{}','admin_staff'),('${staff}','مسؤول التجهيز','warehouse_staff',false,'{}','warehouse'),('00000000-0000-0000-0000-000000003503','مهندس الاختبار','warehouse_installer',false,'{}','installer');
insert into customers(id,name,customer_type,owner_id) values(-345501,'زبون تجهيز الجملة','wholesale','${owner}'),(-345502,'زبون تجهيز المنظومة','system','${owner}');insert into products(id,code,name,qty,cost) values(-345501,'W-UI-1','لوح تجهيز اختباري',10,100),(-345502,'W-UI-0','مادة بدون رصيد',0,10);`);
await sql(`select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"${owner}","mode":"capital_deposit","currency":"IQD","amount":1000,"note":"test office cash"}')`,owner);
async function navigate(page,id){await page.locator('.premiumMobileBrand').click();await page.locator('.sectionDirectory a[href="/?section='+id+'"]').click();}
async function focus(page){await page.evaluate(()=>window.dispatchEvent(new Event('focus')));}
async function noOverflow(page){assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'horizontal overflow');}
async function until(fn,label){let last;for(let i=0;i<60;i++){try{if(await fn())return;}catch(e){last=e;}await new Promise(r=>setTimeout(r,200));}throw new Error(label+': '+(last?.message||''));}
const warehouse=await session(staff,390);await navigate(warehouse,'stock');
await warehouse.getByRole('checkbox',{name:'المتوفر فقط',exact:true}).waitFor();assert.ok(await warehouse.getByRole('checkbox',{name:'المتوفر فقط'}).isChecked());assert.equal(await warehouse.getByText('مادة بدون رصيد',{exact:true}).count(),0);await warehouse.getByRole('checkbox',{name:'المتوفر فقط'}).uncheck();await warehouse.getByText('مادة بدون رصيد',{exact:true}).waitFor();
await navigate(warehouse,'warehouse');await warehouse.getByRole('button',{name:'تفعيل الإشعارات والصوت',exact:true}).click();await warehouse.getByText('تم تفعيل تنبيهات التجهيز والصوت على هذا الجهاز.',{exact:true}).waitFor();assert.equal(await jsonSql(`select count(*) from solar_push_subscriptions where user_id='${staff}'`),1);assert.ok(await warehouse.evaluate(()=>window.__sounds>=3));
const page=await session(owner,390);await page.getByRole('button',{name:'فتح الإشعارات',exact:true}).click();await page.getByRole('button',{name:'تشغيل صوت التنبيهات',exact:true}).click();await page.getByRole('button',{name:'إغلاق',exact:true}).click();
async function sale(){await navigate(page,'sale');await page.locator('.partySearch input').fill('زبون تجهيز الجملة');await page.locator('.partySearchResults button').filter({hasText:'زبون تجهيز الجملة'}).click();await page.getByLabel('البحث عن مادة',{exact:true}).fill('لوح تجهيز');await page.getByRole('button',{name:'إضافة لوح تجهيز اختباري',exact:true}).click();await page.getByLabel('الكمية — لوح تجهيز اختباري').fill('1');await page.getByLabel('سعر البيع — لوح تجهيز اختباري').fill('200');await page.getByRole('button',{name:'حفظ الوصل',exact:true}).click();await page.locator('.warrantySaved').filter({hasText:'تم حفظ فاتورة'}).waitFor();}
await sale();await sale();await focus(warehouse);await until(async()=>await warehouse.locator('.warehouseOrder').count()===2,'two pending invoices');await noOverflow(warehouse);await warehouse.screenshot({path:artifacts+'/warehouse-pending-mobile.png',fullPage:true});
const sound=await warehouse.evaluate(()=>window.__sounds);assert.ok(sound>=6);await focus(warehouse);await new Promise(r=>setTimeout(r,500));assert.equal(await warehouse.evaluate(()=>window.__sounds),sound,'old notices must not replay sound');
await warehouse.getByRole('button',{name:'فتح الإشعارات',exact:true}).click();await warehouse.locator('.notificationList button').first().click();await until(async()=>await warehouse.locator('.warehouseOrder').count()===1,'single notification invoice');await navigate(warehouse,'warehouse');await until(async()=>await warehouse.locator('.warehouseOrder').count()===2,'department navigation clears pinned search');
await warehouse.locator('.warehouseOrder').first().getByRole('button',{name:'تم التجهيز ✓',exact:true}).click();await until(async()=>await warehouse.locator('.warehouseOrder').count()===1,'one remaining invoice');assert.match(await warehouse.locator('.warehouseQueueTabs').innerText(),/تم التجهيز\s*1/);assert.equal(await jsonSql('select qty from products where id=-345501'),8);
await navigate(page,'salesHistory');await until(async()=>await page.locator('.invoiceWarehouseBadge.ready').count()===1,'green prepared invoice badge');await noOverflow(page);await page.screenshot({path:artifacts+'/sales-prepared-mobile.png',fullPage:true});
await navigate(page,'system');await page.locator('.partySearch input').fill('زبون تجهيز المنظومة');await page.locator('.partySearchResults button').filter({hasText:'زبون تجهيز المنظومة'}).click();await page.getByLabel('مهندس التنصيب',{exact:true}).selectOption('00000000-0000-0000-0000-000000003503');await page.getByLabel('عنوان التنصيب',{exact:true}).fill('عنوان التنصيب الاختباري');await page.getByLabel('البحث عن مادة',{exact:true}).fill('لوح تجهيز');await page.getByRole('button',{name:'إضافة لوح تجهيز اختباري',exact:true}).click();await page.getByLabel('الكمية — لوح تجهيز اختباري').fill('2');await page.getByLabel('سعر بيع المنظومة',{exact:true}).fill('1000');assert.equal(await page.getByText('المصاريف الإضافية',{exact:true}).count(),0);await noOverflow(page);await page.screenshot({path:artifacts+'/system-no-initial-expenses-mobile.png',fullPage:true});await page.getByRole('button',{name:'حفظ المنظومة وإسناد التنصيب',exact:true}).click();await page.locator('.warrantySaved').filter({hasText:'تم حفظ منظومة'}).waitFor();
await navigate(page,'installations');await page.getByText('بانتظار تجهيز المخزن. يظهر اعتماد المصاريف والغلق بعد التجهيز.',{exact:true}).waitFor();assert.equal(await page.getByRole('button',{name:'اعتماد المصاريف وإغلاق الملف',exact:true}).count(),0);
await focus(warehouse);await until(async()=>await warehouse.locator('.warehouseOrder').count()===2,'new system in pending');const system=warehouse.locator('.warehouseOrder').filter({hasText:'زبون تجهيز المنظومة'});await system.getByRole('button',{name:'تم التجهيز ✓',exact:true}).click();await until(async()=>await warehouse.locator('.warehouseOrder').count()===1,'system prepared');await focus(page);await page.getByRole('button',{name:'اعتماد المصاريف وإغلاق الملف',exact:true}).waitFor();await page.getByRole('button',{name:'فتح الإشعارات',exact:true}).click();await page.locator('.notificationList button').filter({hasText:'المنظومة جاهزة لاعتماد المصاريف والغلق'}).first().click();await page.getByLabel('المصاريف النهائية للمنظومة',{exact:true}).fill('150');await noOverflow(page);await page.screenshot({path:artifacts+'/office-final-expense-mobile.png',fullPage:true});await page.getByRole('button',{name:'اعتماد المصاريف وإغلاق الملف',exact:true}).click();await page.getByText('تم إغلاق الملف واعتماد المصاريف والربح.',{exact:true}).waitFor();
const result=await jsonSql(`select jsonb_build_object('status',installation_status,'initial',expenses,'final',installation_expenses,'profit',profit,'report',installation_report) from transactions where kind='system'`);assert.deepEqual(result,{status:'closed',initial:0,final:150,profit:650,report:{}});assert.equal(await jsonSql(`select solar_private.cash_balance('${owner}')`),850);assert.equal(await jsonSql('select qty from products where id=-345501'),6);assert.equal(await page.getByRole('button',{name:'اعتماد المصاريف وإغلاق الملف',exact:true}).count(),0);await page.setViewportSize({width:1366,height:900});await noOverflow(page);await page.screenshot({path:artifacts+'/office-closed-desktop.png',fullPage:true});
await warehouse.getByRole('button',{name:/كل الفواتير/}).click();await until(async()=>await warehouse.locator('.warehouseOrder').count()===3,'all invoices retained');await warehouse.getByRole('button',{name:/تم التجهيز 2/}).click();await until(async()=>await warehouse.locator('.warehouseOrder').count()===2,'prepared history');
assert.deepEqual(errors,[]);console.log('PASS browser → local RPC/Postgres: default available stock, explicit device push/sound activation, two pending invoices, deduplicated sound, notification filter reset, green prepared badge, system without initial expenses, preparation returns to office, direct final approval, one cash expense, correct stock/profit and responsive mobile/desktop');for(const ctx of contexts)await ctx.close();await browser.close();
