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
     if(['solar_system_payment_save','solar_customer_payment_save','solar_invoice_save'].includes(name)){confirmedAt=Date.now();if(delayCloud)holdCloudUntil=Date.now()+5000;if(dropNextPayment){dropNextPayment=false;return route.abort('failed');}}
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
   if(Date.now()<holdCloudUntil&&['brands','products','customers','suppliers','transactions','transaction_items','solar_cash_entries'].includes(url.pathname.split('/').at(-1))){slowReads.push(req.url());await new Promise(r=>setTimeout(r,5000));}
   await route.fulfill({status:200,headers,body:JSON.stringify(body)});
  }catch(e){errors.push(e.message);await route.fulfill({status:400,headers,body:JSON.stringify({code:'P0001',message:e.message})});}
 });
 // No unmocked request may reach production during verification.
 await context.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());
 await page.goto(process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3013');await page.locator('.premiumDashboard').waitFor();await page.evaluate(()=>document.fonts.ready);return page;
}

const owner='00000000-0000-0000-0000-000000003500',staff='00000000-0000-0000-0000-000000003501';
let delayCloud=false,dropNextPayment=false,confirmedAt=0;let holdCloudUntil=0;const slowReads=[];
const artifacts='/workspace/solar-review/fast-payments-v346';await mkdir(artifacts,{recursive:true});
await sql(`insert into profiles(id,display_name,username,is_admin,permissions,user_type) values('${owner}','مدير السرعة','fast_admin',true,'{}','admin_staff'),('${staff}','قاصة الموظف','fast_staff',false,'{"cash":true}','admin_staff'),('00000000-0000-0000-0000-000000003503','مهندس الاختبار','fast_installer',false,'{}','installer');
insert into customers(id,name,customer_type,owner_id) values(-346501,'زبون الرصيد الكامل','system','${owner}'),(-346502,'زبون الجملة السريع','wholesale','${owner}'),(-346503,'زبون المنظومات المحددة','system','${owner}');
insert into suppliers(id,name,account_currency)values(-346501,'مورد الدولار السريع','USD');insert into products(id,code,name,qty,cost)values(-346501,'FAST-01','لوح السرعة',20,100);
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id)values(-346501,'system_payment',-346501,'زبون الرصيد الكامل',-3707000,false,'opening_balance','${owner}','${owner}'),(-346502,'customer_payment',-346502,'زبون الجملة السريع',-200000,false,'opening_balance','${owner}','${owner}'),(-346503,'system',-346503,'زبون المنظومات المحددة',1000000,false,'credit','${owner}','${owner}'),(-346504,'system',-346503,'زبون المنظومات المحددة',250000,false,'credit','${owner}','${owner}');`);
await sql(`select public.solar_exchange_rate_set(1660,(public.solar_exchange_rate_get()->>'revision')::bigint);select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"${owner}","mode":"capital_deposit","currency":"IQD","amount":50000000,"note":"fixture admin"}');select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"${owner}","mode":"capital_deposit","currency":"USD","amount":1000.25,"rate":1660,"note":"fixture USD"}');select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"${staff}","mode":"capital_deposit","currency":"IQD","amount":500250,"note":"fixture staff"}');select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"${staff}","mode":"capital_deposit","currency":"USD","amount":100.5,"rate":1660,"note":"fixture staff USD"}');select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد الدولار السريع","partyId":-346501,"mode":"credit","sourceCurrency":"USD","exchangeRate":1660,"marketRate":1660,"accountRevision":0,"cashCurrency":"IQD","items":[{"id":-346501,"qty":1,"price":100.25}]}');`,owner);
async function navigate(page,id){await page.locator('.premiumMobileBrand').click();await page.locator('.sectionDirectory a[href="/?section='+id+'"]').click();}
async function pick(page,name){await page.getByRole('combobox',{name:'بحث عميل الكشف',exact:true}).fill(name);await page.getByRole('option').filter({hasText:name}).first().click();}
async function noOverflow(page){assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'horizontal overflow');}
async function checkFast(page,text){await page.getByRole('status').filter({hasText:text}).waitFor();const elapsed=Date.now()-confirmedAt;assert.ok(elapsed<2000,'confirmation waited for background: '+elapsed+'ms');return elapsed;}
const timings=[];const page=await session(owner,390);
for(let columns=1;columns<=7;columns++){
 await page.getByRole('button',{name:'ترتيب الأقسام وعدد الأعمدة',exact:true}).click();await page.getByLabel('أعمدة الموبايل',{exact:true}).selectOption(String(columns));await page.getByLabel('أعمدة اللاب توب',{exact:true}).selectOption(String(8-columns));
 if(columns===1){await page.getByRole('button',{name:'اختيار مكان الصندوق',exact:true}).click();await page.getByRole('button',{name:'اختيار مكان بيع جملة',exact:true}).click();}
 await page.getByRole('button',{name:'حفظ ترتيب الأقسام',exact:true}).click();await page.getByText('تم حفظ ترتيب أقسامك.',{exact:true}).waitFor();assert.match(await page.locator('.sectionDirectory a').first().innerText(),/الصندوق/);const grid=await page.locator('.sectionTileGrid').first().evaluate(e=>getComputedStyle(e).gridTemplateColumns.split(' ').length);assert.equal(grid,columns);await noOverflow(page);
}
await page.screenshot({path:artifacts+'/seven-columns-mobile.png',fullPage:true});await page.getByRole('button',{name:'ترتيب الأقسام وعدد الأعمدة',exact:true}).click();await page.getByLabel('أعمدة الموبايل',{exact:true}).selectOption('3');await page.getByLabel('أعمدة اللاب توب',{exact:true}).selectOption('7');await page.getByRole('button',{name:'حفظ ترتيب الأقسام',exact:true}).click();await page.getByText('تم حفظ ترتيب أقسامك.',{exact:true}).waitFor();await page.reload();await page.locator('.sectionDirectory a').first().filter({hasText:'الصندوق'}).waitFor();await page.screenshot({path:artifacts+'/personal-order-mobile.png',fullPage:true});await page.setViewportSize({width:1366,height:900});assert.equal(await page.locator('.sectionTileGrid').first().evaluate(e=>getComputedStyle(e).gridTemplateColumns.split(' ').length),7);await noOverflow(page);await page.screenshot({path:artifacts+'/personal-order-desktop.png',fullPage:true});await page.setViewportSize({width:390,height:900});
await navigate(page,'users');await page.locator('.userPermissionCard').filter({hasText:'قاصة الموظف'}).getByRole('button',{name:'تعديل',exact:true}).click();await page.getByRole('checkbox',{name:'تخصيص ترتيب وحجم أقسامه',exact:true}).waitFor();
await navigate(page,'systemPayment');await pick(page,'زبون الرصيد الكامل');await page.getByTestId('system-account-balance').filter({hasText:'3,707,000'}).waitFor();await page.getByRole('button',{name:'كامل المبلغ',exact:true}).click();assert.equal(await page.getByLabel('مبلغ حركة المنظومات').inputValue(),'3,707,000');await noOverflow(page);await page.screenshot({path:artifacts+'/full-opening-payment-mobile.png',fullPage:true});
const beforeContext=rpcCalls.filter(c=>c.name==='solar_system_payment_context').length;delayCloud=true;await page.getByRole('button',{name:'حفظ التسديد',exact:true}).click();timings.push({flow:'system',milliseconds:await checkFast(page,'تم حفظ تسديد المنظومات')});delayCloud=false;assert.equal(await page.getByTestId('system-saved-balance').textContent(),'0 د.ع');assert.equal(rpcCalls.filter(c=>c.name==='solar_system_payment_context').length,beforeContext,'no second account network read after saving');await page.getByRole('button',{name:'حركة جديدة',exact:true}).click();assert.ok(await page.getByRole('button',{name:'كامل المبلغ',exact:true}).isDisabled());
await navigate(page,'systemPayment');await pick(page,'زبون المنظومات المحددة');await page.getByLabel('تخصيص تسديد المنظومات').selectOption('-346504');await page.getByRole('button',{name:'كامل المبلغ',exact:true}).click();assert.equal(await page.getByLabel('مبلغ حركة المنظومات').inputValue(),'250,000','full selected invoice only');await page.getByRole('button',{name:'حفظ التسديد',exact:true}).click();await checkFast(page,'تم حفظ تسديد المنظومات');
await navigate(page,'customerPayment');await pick(page,'زبون الجملة السريع');await page.getByTestId('system-account-balance').filter({hasText:'200,000'}).waitFor();await page.getByRole('button',{name:'كامل المبلغ',exact:true}).click();assert.equal(await page.getByLabel('مبلغ حركة الجملة').inputValue(),'200,000');await page.getByLabel('مبلغ حركة الجملة').fill('50000');dropNextPayment=true;await page.getByRole('button',{name:'حفظ التسديد',exact:true}).click();await page.getByRole('alert').filter({hasText:'لم يتأكد رد الحفظ'}).waitFor();assert.ok(await page.getByLabel('مبلغ حركة الجملة').isDisabled());await page.getByRole('button',{name:'إعادة تأكيد الحفظ',exact:true}).click();await checkFast(page,'تم حفظ تسديد الجملة');const saves=rpcCalls.filter(c=>c.name==='solar_customer_payment_save');assert.equal(saves[0].data.request_id,saves[1].data.request_id);assert.equal(await jsonSql("select count(*) from transactions where party_id=-346502 and payment_mode='payment'"),1);await page.getByRole('button',{name:'حركة جديدة',exact:true}).click();await page.getByRole('button',{name:'كامل المبلغ',exact:true}).click();assert.equal(await page.getByLabel('مبلغ حركة الجملة').inputValue(),'150,000');await page.getByRole('button',{name:'حفظ التسديد',exact:true}).click();await checkFast(page,'تم حفظ تسديد الجملة');
await navigate(page,'supplierPayment');await page.locator('.partySearch input').fill('مورد الدولار السريع');await page.locator('.partySearchResults button').filter({hasText:'مورد الدولار السريع'}).click();await page.getByLabel('عملة حركة المورد').selectOption('USD');await page.getByRole('button',{name:'كامل المبلغ',exact:true}).click();assert.equal(await page.getByLabel('مبلغ حركة المورد').inputValue(),'100.25');await page.getByLabel('عملة حركة المورد').selectOption('IQD');await page.getByRole('button',{name:'كامل المبلغ',exact:true}).click();assert.equal(await page.getByLabel('مبلغ حركة المورد').inputValue(),'166,415');await page.getByLabel('عملة حركة المورد').selectOption('USD');await page.getByRole('button',{name:'كامل المبلغ',exact:true}).click();await page.screenshot({path:artifacts+'/full-supplier-usd-mobile.png',fullPage:true});await page.getByRole('button',{name:'حفظ التسديد وخصمه من القاصة',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ التسديد بنجاح'}).waitFor();assert.equal(Number(await jsonSql(`select public.solar_fx('account',null,'{"supplierId":-346501}')->>'balance'`,owner)),0);
await navigate(page,'sale');await page.locator('.partySearch input').fill('زبون الجملة السريع');await page.locator('.partySearchResults button').filter({hasText:'زبون الجملة السريع'}).click();await page.getByLabel('البحث عن مادة',{exact:true}).fill('لوح السرعة');await page.getByRole('button',{name:'إضافة لوح السرعة',exact:true}).click();await page.getByLabel('الكمية — لوح السرعة').fill('1');await page.getByLabel('سعر البيع — لوح السرعة').fill('300');delayCloud=true;await page.getByRole('button',{name:'حفظ الوصل',exact:true}).click();await page.locator('.warrantySaved').filter({hasText:'تم حفظ فاتورة'}).waitFor();const invoiceElapsed=Date.now()-confirmedAt;assert.ok(invoiceElapsed<2000,'invoice confirmation waited for global refresh: '+invoiceElapsed);timings.push({flow:'invoice',milliseconds:invoiceElapsed});delayCloud=false;assert.equal(await jsonSql('select qty from products where id=-346501'),20);
await navigate(page,'cash');const overview=page.getByRole('region',{name:'أرصدة قاصات المستخدمين'});await page.locator('.cashOwnerRow').first().waitFor();const staffRow=page.getByRole('button',{name:'فتح قاصة قاصة الموظف',exact:true});await staffRow.waitFor();assert.match(await staffRow.innerText(),/500,250/);assert.match(await staffRow.innerText(),/100.5/);await staffRow.click();await page.getByTestId('cash-iqd').filter({hasText:'500,250'}).waitFor();await page.getByTestId('cash-usd').filter({hasText:'100.5'}).waitFor();await page.getByLabel('بداية فترة الصندوق').fill('2099-01-01');await page.getByText('لا توجد حركات ضمن الاختيارات',{exact:true}).waitFor();assert.match(await staffRow.innerText(),/500,250/);await noOverflow(page);await page.screenshot({path:artifacts+'/user-cash-balances-mobile.png',fullPage:true});await page.setViewportSize({width:1366,height:900});await noOverflow(page);await page.screenshot({path:artifacts+'/user-cash-balances-desktop.png',fullPage:true});
const staffPage=await session(staff,390);assert.equal(await staffPage.getByRole('button',{name:'ترتيب الأقسام وعدد الأعمدة',exact:true}).count(),0);await navigate(staffPage,'cash');await staffPage.getByTestId('cash-iqd').filter({hasText:'500,250'}).waitFor();assert.equal(await staffPage.locator('.cashOwnerOverview').count(),0,'admin-only overview');assert.equal(await staffPage.getByLabel('القاصة المعروضة').locator('option').count(),1);
await new Promise(r=>setTimeout(r,5500));assert.ok(slowReads.length>0,'slow background actually exercised');assert.deepEqual(errors,[]);console.log(JSON.stringify({status:'PASS',timings,slowBackgroundMilliseconds:5000,slowReads:slowReads.length,verified:'opening and selected invoice full amount, committed account without second request, lost reply idempotency, immediate next payment, supplier USD cents and IQD conversion, admin per-user boxes and staff isolation, responsive layouts, persisted personal 1–7 column order, desktop settings, layout permission UI'}));for(const ctx of contexts)await ctx.close();await browser.close();
