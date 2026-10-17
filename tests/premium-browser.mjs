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
const errors=[];const rpcCalls=[];const contexts=[];let dropOnce=true;
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
    else if(['solar_warehouse_orders','solar_sales_history'].includes(name))body={rows:[],count:0};
    else if(name==='solar_cash_transfer_overview')body={canSend:true,canReceive:true,balance:0,rows:[],managers:[]};
    else if(['solar_installation_jobs','solar_stock_movements'].includes(name))body=[];
    else if(name==='solar_stock_quantities')body=await jsonSql("select jsonb_agg(to_jsonb(p)) from public.products p");
    else {
     assert.match(name,/^solar_[a-z_]+$/);const args=Object.entries(data).map(([key,value])=>{assert.match(key,/^[a-z_]+$/);return key+'=>'+(value===null?'null':typeof value==='object'?sqlLiteral(JSON.stringify(value))+'::jsonb':typeof value==='number'?String(value):sqlLiteral(value));}).join(',');
     body=await jsonSql('select public.'+name+'('+args+')',uid);
     if(name==='solar_cash_save'&&dropOnce){dropOnce=false;return route.abort('failed');}
    }
   }else{
    const table=url.pathname.split('/').at(-1);
    assert.ok(['profiles','brands','products','customers','suppliers','transactions','transaction_items','solar_cash_entries','solar_notifications','solar_push_subscriptions','solar_quotes','solar_price_estimates','solar_estimate_specs'].includes(table));
    if(['solar_notifications','solar_push_subscriptions','solar_quotes','solar_price_estimates','solar_estimate_specs'].includes(table))body=[];
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
const artifacts='/workspace/solar-review/premium-v336';await mkdir(artifacts,{recursive:true});
if(!visualOnly){await sql(`insert into public.profiles(id,display_name,username,is_admin,permissions) values('${owner}','مدير المالية','finance_admin',true,'{}'),('${staff}','عبدالرحمن الموظف','finance_staff',false,'{"cash":true,"purchase":true,"customerPayment":true,"systemPayment":true,"supplierPayment":true,"suppliers":true,"supplierStatement":true,"customerStatement":true,"customers":true}');
insert into public.suppliers(id,name,account_currency) values(-350001,'المورد الدولاري','USD'),(-350002,'المورد الديناري','IQD');
insert into public.products(id,code,name,qty,cost) values(-350001,'FIN-1','لوح اختبار الفواصل',10,100000);
insert into public.customers(id,name,phone,customer_type,owner_id) values(-350001,'زبون الجملة','07712345678','wholesale','${staff}'),(-350002,'كوبا كافي','07812345678','system','${staff}');
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id) values(-350001,'customer_payment',-350001,'زبون الجملة',-1000000,false,'opening_balance','${owner}','${owner}'),(-350002,'system_payment',-350002,'كوبا كافي',-18000000,false,'opening_balance','${owner}','${owner}');`);
await sql(`insert into public.customers(id,name,customer_type,owner_id) values(-350010,'عميل مخطط الاختبار','wholesale','${owner}');insert into public.transactions(id,kind,party_id,party_name,subtotal,total,cost,profit,fx_pricing,cash,created_by,cashbox_user_id,created_at) select -350100-n,'sale',-350010,'عميل مخطط الاختبار',1000000+n*80000+(n%3)*50000,1000000+n*80000+(n%3)*50000,700000+n*60000,300000+n*20000+(n%3)*50000,true,false,'${owner}','${owner}',now()-(13-n)*interval '1 day' from generate_series(0,13) n;insert into public.transaction_items(transaction_id,product_name,qty,price,cost) select id,'مواد مخطط الاختبار',1,subtotal,cost from public.transactions where id between -350113 and -350100;`);
await sql(`select public.solar_exchange_rate_set(1500,0);select public.solar_cash_save(gen_random_uuid(),'${JSON.stringify({ownerId:owner,mode:'capital_deposit',currency:'IQD',amount:2000000,note:'رأس مال دينار'})}');select public.solar_cash_save(gen_random_uuid(),'${JSON.stringify({ownerId:owner,mode:'capital_deposit',currency:'USD',amount:1000.5,rate:1500,note:'رأس مال دولار'})}');select public.solar_cash_save(gen_random_uuid(),'${JSON.stringify({ownerId:staff,mode:'deposit',currency:'IQD',amount:500000,note:'قاصة الموظف'})}');select public.solar_cash_save(gen_random_uuid(),'${JSON.stringify({ownerId:staff,mode:'capital_deposit',currency:'USD',amount:25.75,rate:1500,note:'قاصة الموظف دولار'})}');`,owner);
}
async function navigate(page,id){
 console.log('NAV',id,page.viewportSize()?.width);
 const mobile=(page.viewportSize()?.width||1366)<=960;
 if(mobile)await page.getByRole('button',{name:'الأقسام',exact:true}).click();
 const nav=mobile?page.getByRole('dialog',{name:'أقسام البرنامج'}):page.locator('.appSidebar'),target=nav.locator('a[href="'+(id==='home'?'/?':'/?section='+id)+'"]');
 const parent=target.locator('xpath=ancestor::details[1]');if(await parent.count()&&!(await parent.evaluate(el=>el.open)))await parent.locator('summary').first().click();await target.click();await page.evaluate(()=>window.scrollTo(0,0));
}
async function home(page){await navigate(page,'home');}
async function group(page,name){await navigate(page,{'تسديد بيع جملة':'customerPayment','تسديد منظومة':'systemPayment','تسديد مورد':'supplierPayment','كشف حساب عميل':'customerStatement','مدينون العملاء':'customerDebts'}[name]);}
async function pickCustomer(page,name){await page.getByRole('combobox',{name:'بحث عميل الكشف',exact:true}).fill(name);await page.getByRole('option').filter({hasText:name}).first().click();}
async function pickParty(page,name){await page.locator('.partySearch input[role=combobox]').fill(name);await page.getByRole('option').filter({hasText:name}).first().click();}
async function noOverflow(page){const result=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth,offenders:[...document.querySelectorAll('main *')].filter(el=>el.getBoundingClientRect().right>innerWidth+2||el.getBoundingClientRect().left< -2).slice(0,8).map(el=>el.className)}));assert.ok(result.scroll<=result.width,JSON.stringify(result));}
async function readyPDF(page,scope=page){console.log('PDF prepare');await scope.locator('.reportExportButtons button.download:not([disabled])').waitFor({timeout:60000});}
try{
 if(visualOnly){
  const page=await session(owner,1366);page.setDefaultTimeout(15000);
  for(const id of ['home','sale','system','purchase','cash','profit','products','stock','stockMovement','warehouse','installations','cashTransfers','exchangeRate','users','customerPayment','systemPayment','customerStatement','customerDebts','supplierPayment','supplierStatement','supplierBalances','suppliers','customers','brands','tahseel','capital']){
   await navigate(page,id);await page.locator('main').waitFor();await page.waitForTimeout(150);await noOverflow(page);await page.evaluate(()=>window.scrollTo(0,0));
   if(id==='products'){const style=await page.getByRole('button',{name:'حفظ المادة',exact:true}).evaluate(el=>({radius:getComputedStyle(el).borderRadius,bg:getComputedStyle(el).backgroundColor}));assert.ok(parseFloat(style.radius)>=7);assert.equal(style.bg,'rgb(7, 138, 120)');}
   if(id==='stockMovement')assert.equal(await page.locator('.movementWorkspace').evaluate(el=>getComputedStyle(el).getPropertyValue('--mv-action').trim()),'#078a78');
   await page.screenshot({path:artifacts+'/'+id+'-desktop.png',fullPage:true});await page.setViewportSize({width:360,height:844});await noOverflow(page);await page.screenshot({path:artifacts+'/'+id+'-mobile.png',fullPage:true});await page.setViewportSize({width:1366,height:900});
  }
  assert.deepEqual(errors,[]);console.log('PASS final visual review: all sections, desktop and mobile, consistent controls, no overflow or UI errors');
 }else{
 const page=await session(owner,390);page.setDefaultTimeout(15000);await page.getByRole('button',{name:'كل الأقسام',exact:false}).click();await page.getByRole('dialog',{name:'أقسام البرنامج'}).waitFor();await page.keyboard.press('Escape');await page.getByRole('button',{name:'فتح التسديدات والحسابات',exact:true}).click();await page.getByRole('dialog',{name:'التسديدات والحسابات'}).waitFor();await page.keyboard.press('Escape');await noOverflow(page);await page.screenshot({path:artifacts+'/home-mobile.png',fullPage:true});await page.setViewportSize({width:1440,height:900});await page.getByRole('button',{name:'كل الأقسام',exact:false}).click();await page.getByRole('dialog',{name:'أقسام البرنامج'}).waitFor();await page.keyboard.press('Escape');await page.screenshot({path:artifacts+'/home-desktop.png',fullPage:true});await page.setViewportSize({width:390,height:900});
 await navigate(page,'cash');await page.getByTestId('cash-usd').filter({hasText:'1,000.50'}).waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/cash-mobile.png',fullPage:true});
 await page.getByRole('button',{name:'+ حركة جديدة',exact:true}).click();await page.getByLabel('نوع حركة الصندوق').selectOption('expense');await page.getByLabel('عملة حركة الصندوق').selectOption('USD');
 await page.getByLabel('مبلغ حركة الصندوق').pressSequentially('0.50');await page.getByLabel('بيان حركة الصندوق').fill('مصروف بالكسور');assert.equal(await page.getByLabel('مبلغ حركة الصندوق').inputValue(),'0.50');await noOverflow(page);
 await page.getByRole('button',{name:'حفظ الحركة',exact:true}).click();await page.getByRole('alert').filter({hasText:'لم يتأكد رد الحفظ'}).waitFor();console.log('PASS lost response');assert.ok(await page.getByLabel('مبلغ حركة الصندوق').isDisabled());await page.getByRole('button',{name:'إعادة تأكيد الحفظ',exact:true}).click();await page.locator('.cashReceipt').waitFor();
 await page.getByTestId('cash-usd').filter({hasText:/^1,000\s*\$/}).waitFor();assert.match(await page.getByTestId('cash-usd').textContent(),/1,000\s*\$/);assert.ok(!(await page.getByTestId('cash-usd').textContent()).includes('.00'));
 const calls=rpcCalls.filter(x=>x.name==='solar_cash_save');assert.equal(calls.length,2);assert.equal(calls[0].data.request_id,calls[1].data.request_id);
 assert.equal(await jsonSql("select count(*) from public.transactions where notes='مصروف بالكسور'"),1);
 console.log('PASS cash retry');const receipt=page.locator('.cashReceipt');await readyPDF(page,receipt);const style=await receipt.locator('button.download').evaluate(el=>({radius:getComputedStyle(el).borderRadius,bg:getComputedStyle(el).backgroundColor,font:getComputedStyle(el).fontFamily}));assert.ok(parseFloat(style.radius)>=7);assert.equal(style.bg,'rgb(7, 138, 120)');assert.ok(style.font.includes('Solar Arabic')); console.log('PASS PDF button style',style);const popupP=page.waitForEvent('popup');await receipt.getByRole('button',{name:'معاينة',exact:true}).click();const popup=await popupP;await popup.locator('#pdfDownload:not([disabled])').waitFor();console.log('PASS PDF popup rendered');await popup.getByLabel('التكبير').selectOption('1.25');await popup.getByLabel('التكبير').selectOption('1');await popup.close();
 const downloadP=page.waitForEvent('download');await receipt.getByRole('button',{name:'حفظ PDF',exact:true}).click();const download=await downloadP;await download.saveAs(artifacts+'/cash-receipt.pdf');const file=await readFile(artifacts+'/cash-receipt.pdf');assert.equal(file.subarray(0,8).toString(),'%PDF-1.4');
 console.log('PASS PDF preview/download');await receipt.getByRole('button',{name:'مشاركة',exact:true}).click();await page.waitForFunction(()=>window.__shareEvidence);assert.ok(await page.evaluate(()=>window.__shareEvidence.active));assert.equal(await page.evaluate(()=>window.__shareEvidence.hash),createHash('sha256').update(file).digest('hex'));
 await page.getByRole('button',{name:'إغلاق وصل الصندوق',exact:true}).click();await page.getByRole('button',{name:'+ حركة جديدة',exact:true}).click();await page.getByLabel('نوع حركة الصندوق').selectOption('buy_usd');await page.getByLabel('مبلغ حركة الصندوق').pressSequentially('10.25');await page.getByLabel('بيان حركة الصندوق').fill('شراء دولار يومي');await page.getByRole('button',{name:'حفظ الحركة',exact:true}).click();await page.getByTestId('cash-usd').filter({hasText:'1,010.25'}).waitFor();await page.getByRole('button',{name:'إغلاق وصل الصندوق',exact:true}).click();
 await page.getByLabel('بحث حركات الصندوق').fill('شراء دولار يومي');await page.locator('.cashTable tbody tr').nth(1).waitFor();await page.getByRole('button',{name:'معاينة وتصدير',exact:true}).click();await page.getByRole('heading',{name:'كشف الصندوق جاهز للتصدير'}).waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/cash-filter-mobile.png',fullPage:true});
 await page.getByLabel('القاصة المعروضة').selectOption(staff);await page.getByTestId('cash-iqd').filter({hasText:'500,000'}).waitFor();await page.getByTestId('cash-usd').filter({hasText:'25.75'}).waitFor();await noOverflow(page);
 await home(page);await navigate(page,'purchase');await pickParty(page,'المورد الدولاري');assert.equal(await page.getByLabel('عملة الشراء').inputValue(),'USD');await page.getByLabel('البحث عن مادة').focus();await page.getByRole('button',{name:'إضافة لوح اختبار الفواصل',exact:true}).click();await page.getByLabel('الكمية — لوح اختبار الفواصل').fill('2');
 const price=page.getByLabel('سعر الشراء — لوح اختبار الفواصل');await price.pressSequentially('125.50');assert.equal(await price.inputValue(),'125.50');await page.getByLabel('ملاحظات الفاتورة').fill('شراء بفواصل صحيحة');assert.equal(await price.inputValue(),'125.50');assert.match(await page.locator('.deskGrand strong').textContent(),/251\s*\$/);await noOverflow(page);await page.screenshot({path:artifacts+'/purchase-decimal-mobile.png',fullPage:true});await page.setViewportSize({width:1440,height:900});await page.evaluate(()=>window.scrollTo(0,0));await readyPDF(page);const checkout=await page.locator('.deskCheckout').boundingBox(),main=await page.locator('.deskMain').boundingBox();assert.ok(checkout.x<main.x,'Laptop checkout is to the left of invoice fields');await page.screenshot({path:artifacts+'/purchase-desktop.png',fullPage:true});await page.setViewportSize({width:390,height:900});
 await readyPDF(page);await page.getByRole('button',{name:'حفظ الوصل',exact:true}).click();await page.locator('.deskHistory>summary').click();await page.locator('.historyItem').filter({hasText:'المورد الدولاري'}).waitFor();const saved=await jsonSql("select jsonb_build_object('amount',t.source_subtotal,'currency',t.source_currency,'price',i.source_price,'account',t.account_amount) from public.transactions t join public.transaction_items i on i.transaction_id=t.id where t.notes='شراء بفواصل صحيحة'");assert.deepEqual(saved,{amount:251,currency:'USD',price:125.5,account:251});
 assert.match(await page.locator('.deskSavedSummary strong').textContent(),/^251\s*\$/);await page.locator('.historyItem').getByRole('button',{name:'تعديل',exact:true}).click();assert.equal(await price.inputValue(),'125.50');await page.getByRole('button',{name:'إلغاء التعديل',exact:true}).click();
 await home(page);await navigate(page,'suppliers');await page.getByRole('heading',{name:'الموردون',exact:true}).waitFor();const card=page.locator('.supplierAccountCard').filter({hasText:'المورد الدولاري'});await card.getByText('251 $',{exact:false}).waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/suppliers-mobile.png',fullPage:true});
 await page.getByRole('button',{name:'+ مورد جديد',exact:true}).click();await page.getByLabel('اسم المورد',{exact:true}).fill('مورد ديناري جديد');await page.getByLabel('عملة حساب المورد',{exact:true}).selectOption('IQD');await page.getByRole('button',{name:'حفظ المورد',exact:true}).click();await page.getByRole('heading',{name:'مورد ديناري جديد',exact:true}).waitFor();assert.equal(await jsonSql("select to_jsonb(account_currency) from public.suppliers where name='مورد ديناري جديد'"),'IQD');
 await card.getByRole('button',{name:'كشف الحساب',exact:true}).click();await page.getByTestId('supplier-statement-balance').filter({hasText:'251'}).waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/supplier-statement-mobile.png',fullPage:true});
 await home(page);await group(page,'تسديد مورد');await pickParty(page,'المورد الدولاري');await page.getByLabel('عملة حركة المورد').selectOption('USD');await page.getByLabel('مبلغ حركة المورد').pressSequentially('125.50');await page.getByLabel('ملاحظات حركة المورد').fill('تسديد دولار صحيح');assert.equal(await page.getByLabel('مبلغ حركة المورد').inputValue(),'125.50');await page.getByTestId('supplier-projected').filter({hasText:'125.50'}).waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/supplier-payment-mobile.png',fullPage:true});await page.getByRole('button',{name:'حفظ التسديد وخصمه من القاصة',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ التسديد بنجاح'}).waitFor();
 await page.getByRole('button',{name:'حركة جديدة',exact:true}).click();await page.getByRole('button',{name:/إضافة على حساب المورد/}).click();await page.getByLabel('مبلغ حركة المورد').fill('0.5');await page.getByLabel('سبب إضافة حساب المورد').selectOption('charge_old_balance');await page.getByLabel('ملاحظات حركة المورد').fill('تسديد عكسي غير نقدي');await page.getByRole('button',{name:'إضافة المبلغ إلى حساب المورد',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ الإضافة على حساب المورد'}).waitFor();assert.equal((await jsonSql("select public.solar_fx('account',null,'{\"supplierId\":-350001}')",owner)).balance,126);
 // Opening amounts remain editable after ordinary movements, with duplicate checks.
 await home(page);await navigate(page,'customers');await page.getByLabel('اسم الزبون',{exact:true}).fill('أحمد علي');await page.getByLabel('رصيد افتتاحي إن وجد').check();await page.getByLabel('مبلغ الرصيد الافتتاحي',{exact:true}).fill('2000000');assert.equal(await page.getByLabel('مبلغ الرصيد الافتتاحي',{exact:true}).inputValue(),'2,000,000');await page.getByRole('button',{name:'إضافة الزبون',exact:true}).click();await page.getByRole('status').filter({hasText:'تم تسجيل'}).waitFor();
 const customer=page.locator('.customerCard').filter({hasText:'أحمد علي'});await customer.getByRole('button',{name:'تعديل',exact:true}).click();await page.getByLabel('مبلغ الرصيد الافتتاحي',{exact:true}).fill('3000000');await page.getByRole('button',{name:'حفظ التعديل والرصيد',exact:true}).click();await customer.locator('.customerCardBalance b').filter({hasText:'3,000,000'}).waitFor();await page.getByLabel('اسم الزبون',{exact:true}).fill('احمدعلي');await page.getByText('هذا الزبون مسجّل مسبقاً',{exact:true}).waitFor();assert.ok(await page.getByRole('button',{name:'إضافة الزبون',exact:true}).isDisabled());await noOverflow(page);await page.screenshot({path:artifacts+'/customers-opening-mobile.png',fullPage:true});
 // Both customer settlement screens share the same reliable full-account flow.
 await home(page);await group(page,'تسديد بيع جملة');await pickCustomer(page,'زبون الجملة');await page.getByLabel('مبلغ حركة الجملة').fill('250000');await page.getByRole('button',{name:'حفظ التسديد',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ تسديد الجملة'}).waitFor();assert.equal(await page.getByTestId('system-saved-balance').textContent(),'750,000 د.ع');
 await home(page);await group(page,'تسديد منظومة');await pickCustomer(page,'كوبا كافي');await page.getByLabel('مبلغ حركة المنظومات').fill('1500000');await page.getByRole('button',{name:'حفظ التسديد',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ تسديد المنظومات'}).waitFor();assert.equal(await page.getByTestId('system-saved-balance').textContent(),'16,500,000 د.ع');await noOverflow(page);
 await home(page);await group(page,'كشف حساب عميل');await pickCustomer(page,'07812345678');await page.getByTestId('statement-balance').filter({hasText:'16,500,000'}).waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/customer-statement-mobile.png',fullPage:true});
 await home(page);await group(page,'مدينون العملاء');await page.getByLabel('مستخدم تقرير المدينين').selectOption(staff);await page.getByRole('button',{name:'جملة',exact:true}).click();assert.match(await page.getByTestId('debt-total').textContent(),/750,000/);await page.getByRole('button',{name:'منظومات',exact:true}).click();assert.match(await page.getByTestId('debt-total').textContent(),/16,500,000/);await noOverflow(page);
 // Navigation and both layouts, with real financial endpoints and empty operation queues.
 for(const width of [360,430,1366,1440]){
  await page.setViewportSize({width,height:900});await noOverflow(page);await home(page);await navigate(page,'cash');await page.waitForFunction(()=>document.querySelector('.workspaceHeadActions .primary')?.disabled===false);await page.evaluate(()=>window.scrollTo(0,0));await noOverflow(page);if(width===1366)await page.screenshot({path:artifacts+'/cash-desktop.png',fullPage:true});
 }
 await page.setViewportSize({width:390,height:900});await page.getByRole('button',{name:'الأقسام',exact:true}).click();await page.getByRole('dialog',{name:'أقسام البرنامج'}).getByRole('link',{name:'المخزون',exact:true}).click();await page.getByLabel('بحث المخزون').waitFor();await noOverflow(page);
 await page.setViewportSize({width:1366,height:900});await navigate(page,'profit');await page.getByLabel('مستخدم تقرير الأرباح').selectOption(owner);await page.getByLabel('مبلغ توزيع الأرباح').waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/profit-desktop.png',fullPage:true});
 for(const [id,title] of [['users','المستخدمون'],['updates','تحديثات البرنامج'],['products','المواد'],['brands','البراندات'],['system','بيع منظومة'],['sale','بيع جملة'],['warehouse','تجهيز المخزن'],['stockMovement','حركة المواد'],['salesHistory','المبيعات السابقة'],['installations','التنصيبات'],['cashTransfers','تسليم القاصة'],['tahseel','التحصيل'],['capital','رأس المال'],['exchangeRate','سعر الصرف'],['supplierBalances','أرصدة الموردين']]){
  await navigate(page,id);await page.locator('main').waitFor();await page.waitForTimeout(250);if(id==='updates'){await page.getByPlaceholder('باسورد حسابك').fill('fixture-only');await page.getByRole('button',{name:'فتح تحديثات البرنامج',exact:true}).click();await page.getByText('النسخة المرجعية الحالية محفوظة في GitHub ويتم نشرها عبر Vercel.',{exact:true}).waitFor();}await noOverflow(page);await page.evaluate(()=>window.scrollTo(0,0));await page.screenshot({path:artifacts+'/'+id+'-desktop.png',fullPage:true});await page.setViewportSize({width:360,height:844});await noOverflow(page);await page.screenshot({path:artifacts+'/'+id+'-mobile.png',fullPage:true});await page.setViewportSize({width:1366,height:900});
 }
 const user=await session(staff,390);await navigate(user,'cash');await user.getByTestId('cash-iqd').filter({hasText:'500,000'}).waitFor();assert.equal(await user.getByLabel('القاصة المعروضة').locator('option').count(),1);await noOverflow(user);
 await page.keyboard.press('Control+k');await page.getByLabel('بحث سريع في أقسام البرنامج').fill('سعر الصرف');await page.getByLabel('بحث سريع في أقسام البرنامج').press('Enter');await page.locator('.exchangeRatePage').waitFor();assert.deepEqual(errors,[]);console.log('PASS premium design and navigation; keyboard decimals, source purchase currency, cash retry/receipt/PDF/share, exchange, owner scope, supplier creation/statement, opening settlements, client search, debt filters and responsive navigation');
}
}catch(error){console.error('FAIL',error.message);for(const [i,context] of contexts.entries())for(const [j,page] of context.pages().entries())await page.screenshot({path:artifacts+`/failure-${i}-${j}.png`,fullPage:true,timeout:5000}).catch(()=>{});console.error('API/UI errors:',errors);throw error;}
finally{await browser.close();}
