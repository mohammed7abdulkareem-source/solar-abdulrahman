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
const errors=[];const rpcCalls=[];const contexts=[];let dropOnce=true,dropReceiptEditOnce=true,dropReconcileOnce=true,dropSupplierEditOnce=true;
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
    else if(['solar_installation_jobs','solar_stock_movements'].includes(name))body=[];
    else if(name==='solar_stock_quantities')body=await jsonSql("select jsonb_agg(to_jsonb(p)) from public.products p");
    else {
     assert.match(name,/^solar_[a-z_]+$/);const args=Object.entries(data).map(([key,value])=>{assert.match(key,/^[a-z_]+$/);return key+'=>'+(value===null?'null':typeof value==='object'?sqlLiteral(JSON.stringify(value))+'::jsonb':typeof value==='number'?String(value):sqlLiteral(value));}).join(',');
     if(name==='solar_cash_transfer_decide'){await sql('select public.'+name+'('+args+')',uid);body=null;}else body=await jsonSql('select to_jsonb(public.'+name+'('+args+'))',uid);
     if(name==='solar_cash_save'&&dropOnce){dropOnce=false;return route.abort('failed');}
     if(name==='solar_supplier_payment_manage'&&data.action==='update'&&dropSupplierEditOnce){dropSupplierEditOnce=false;return route.abort('failed');}
     if(name==='solar_cash_reconcile'&&data.action==='apply'&&dropReconcileOnce){dropReconcileOnce=false;return route.abort('failed');}
     if(name==='solar_customer_payment_manage'&&data.action==='update'&&dropReceiptEditOnce){dropReceiptEditOnce=false;return route.abort('failed');}
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
const artifacts='/workspace/solar-review/compact-parties-v342';await mkdir(artifacts,{recursive:true});
if(!visualOnly){await sql(await readFile(new URL('./fixtures/cash-transfers-bootstrap.sql',import.meta.url),'utf8'));await sql(`insert into public.profiles(id,display_name,username,is_admin,permissions) values('${owner}','مدير المالية','finance_admin',true,'{}'),('${staff}','عبدالرحمن الموظف','finance_staff',false,'{"cash":true,"purchase":true,"customerPayment":true,"systemPayment":true,"supplierPayment":true,"suppliers":true,"supplierStatement":true,"customerStatement":true,"customers":true}');
insert into public.suppliers(id,name,account_currency) values(-350001,'المورد الدولاري','USD'),(-350002,'المورد الديناري','IQD');
insert into public.products(id,code,name,qty,cost) values(-350001,'FIN-1','لوح اختبار الفواصل',10,100000);
insert into public.customers(id,name,phone,customer_type,owner_id) values(-350001,'زبون الجملة','07712345678','wholesale','${staff}'),(-350002,'كوبا كافي','07812345678','system','${staff}');
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id) values(-350001,'customer_payment',-350001,'زبون الجملة',-1000000,false,'opening_balance','${owner}','${owner}'),(-350002,'system_payment',-350002,'كوبا كافي',-18000000,false,'opening_balance','${owner}','${owner}');`);
await sql(`insert into public.customers(id,name,customer_type,owner_id) values(-350010,'عميل مخطط الاختبار','wholesale','${owner}');insert into public.transactions(id,kind,party_id,party_name,subtotal,total,cost,profit,fx_pricing,cash,created_by,cashbox_user_id,created_at) select -350100-n,'sale',-350010,'عميل مخطط الاختبار',1000000+n*80000+(n%3)*50000,1000000+n*80000+(n%3)*50000,700000+n*60000,300000+n*20000+(n%3)*50000,true,false,'${owner}','${owner}',now()-(13-n)*interval '1 day' from generate_series(0,13) n;insert into public.transaction_items(transaction_id,product_name,qty,price,cost) select id,'مواد مخطط الاختبار',1,subtotal,cost from public.transactions where id between -350113 and -350100;`);
await sql(`select public.solar_exchange_rate_set(1500,0);select public.solar_cash_save(gen_random_uuid(),'${JSON.stringify({ownerId:owner,mode:'capital_deposit',currency:'IQD',amount:2000000,note:'رأس مال دينار'})}');select public.solar_cash_save(gen_random_uuid(),'${JSON.stringify({ownerId:owner,mode:'capital_deposit',currency:'USD',amount:1000.5,rate:1500,note:'رأس مال دولار'})}');select public.solar_cash_save(gen_random_uuid(),'${JSON.stringify({ownerId:staff,mode:'deposit',currency:'IQD',amount:500000,note:'قاصة الموظف'})}');select public.solar_cash_save(gen_random_uuid(),'${JSON.stringify({ownerId:staff,mode:'capital_deposit',currency:'USD',amount:25.75,rate:1500,note:'قاصة الموظف دولار'})}');`,owner);
}
async function navigate(page,id){
 console.log('NAV',id,page.viewportSize()?.width);
 await page.locator('.premiumMobileBrand').click();
 await page.locator('.sectionDirectory').waitFor();
 if(id!=='home')await page.locator('.sectionDirectory a[href="/?section='+id+'"]').click();
 await page.evaluate(()=>window.scrollTo(0,0));
}
async function home(page){await navigate(page,'home');}
async function group(page,name){await navigate(page,{'تسديد بيع جملة':'customerPayment','تسديد منظومة':'systemPayment','تسديد مورد':'supplierPayment','كشف حساب عميل':'customerStatement','مدينون العملاء':'customerDebts'}[name]);}
async function pickCustomer(page,name){await page.getByRole('combobox',{name:'بحث عميل الكشف',exact:true}).fill(name);await page.getByRole('option').filter({hasText:name}).first().click();}
async function pickParty(page,name){await page.locator('.partySearch input[role=combobox]').fill(name);await page.getByRole('option').filter({hasText:name}).first().click();}
async function noOverflow(page){const result=await page.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth,offenders:[...document.querySelectorAll('main *')].filter(el=>el.getBoundingClientRect().right>innerWidth+2||el.getBoundingClientRect().left< -2).slice(0,8).map(el=>el.className)}));assert.ok(result.scroll<=result.width,JSON.stringify(result));}
async function readyPDF(page,scope=page){console.log('PDF prepare');await scope.locator('.reportExportButtons button.download:not([disabled])').waitFor({timeout:60000});}

if(!visualOnly)await sql(await readFile(new URL('./fixtures/party-ui-bootstrap.sql',import.meta.url),'utf8'));
try{
 const page=await session(owner,390);
 await navigate(page,'customers');assert.equal(await page.locator('.customerHero,.customerStats').count(),0);assert.equal(await page.getByLabel('اسم الزبون',{exact:true}).count(),0);await page.locator('.miniPartyRow').first().waitFor();await noOverflow(page);await page.screenshot({path:artifacts+'/customers-list-mobile.png',fullPage:true});
 await page.getByRole('button',{name:'زبون جديد',exact:true}).click();await page.getByLabel('اسم الزبون',{exact:true}).fill('عميل الواجهة المختصرة');await page.getByLabel('رقم هاتف الزبون').fill('07703420001');await page.getByLabel('نوع الزبون',{exact:true}).selectOption('wholesale');await page.getByLabel('رصيد افتتاحي إن وجد').check();await page.getByLabel('مبلغ الرصيد الافتتاحي',{exact:true}).fill('2000000');await noOverflow(page);await page.screenshot({path:artifacts+'/customer-add-mobile.png',fullPage:true});await page.getByRole('button',{name:'إضافة الزبون',exact:true}).click();await page.getByRole('button',{name:'حساب عميل الواجهة المختصرة',exact:true}).waitFor();
 const customer=await jsonSql("select to_jsonb(c) from customers c where name='عميل الواجهة المختصرة'");assert.equal(customer.owner_id,owner);
 await page.getByRole('button',{name:'حساب عميل الواجهة المختصرة',exact:true}).click();await page.getByTestId('statement-balance').filter({hasText:'2,000,000'}).waitFor();await page.getByRole('button',{name:'تعديل البيانات',exact:true}).click();assert.equal(await page.getByLabel('مبلغ الرصيد الافتتاحي',{exact:true}).inputValue(),'2,000,000');await page.getByLabel('مبلغ الرصيد الافتتاحي',{exact:true}).fill('3000000');await page.getByRole('button',{name:'حفظ التعديل والرصيد',exact:true}).click();await page.getByRole('button',{name:'حساب عميل الواجهة المختصرة',exact:true}).click();await page.getByTestId('statement-balance').filter({hasText:'3,000,000'}).waitFor();
 await page.getByRole('button',{name:'تسديد جديد',exact:true}).click();await page.getByTestId('system-account-balance').filter({hasText:'3,000,000'}).waitFor();await page.getByLabel('مبلغ حركة الجملة').fill('250000');await page.getByLabel('ملاحظات حركة الجملة').fill('تسديد العميل من الواجهة المختصرة');await page.screenshot({path:artifacts+'/customer-payment-mobile.png',fullPage:true});await page.getByRole('button',{name:'حفظ التسديد',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ تسديد الجملة'}).waitFor();await page.getByRole('button',{name:'الرجوع إلى الحساب',exact:true}).click();await page.getByTestId('statement-balance').filter({hasText:'2,750,000'}).waitFor();
 async function openCustomer(){await navigate(page,'customers');await page.getByLabel('بحث الزبائن المسجلين').fill('07703420001');await page.getByRole('button',{name:'حساب عميل الواجهة المختصرة',exact:true}).click();await page.getByTestId('statement-balance').waitFor();}
 await openCustomer();await page.getByTestId('statement-balance').filter({hasText:'2,750,000'}).waitFor();for(const width of [360,430,1366]){await page.setViewportSize({width,height:900});await noOverflow(page);await page.screenshot({path:artifacts+'/customer-account-'+width+'.png',fullPage:true});}
 await page.locator('.miniMovementRow').filter({hasText:'تسديد'}).first().click();await page.locator('.miniDetail').waitFor();await readyPDF(page);await page.getByRole('button',{name:'تعديل الحركة',exact:true}).click();await page.getByLabel('مبلغ تعديل تسديد الجملة').fill('200000');await page.getByRole('button',{name:'حفظ تعديل التسديد',exact:true}).click();await page.getByRole('alert').filter({hasText:'لم يتأكد الرد'}).waitFor();await page.getByRole('button',{name:'إعادة تأكيد العملية',exact:true}).click();await page.getByRole('status').filter({hasText:'تم تعديل التسديد'}).waitFor();await page.getByRole('button',{name:'رجوع لحساب العميل',exact:true}).click();await page.getByTestId('statement-balance').filter({hasText:'2,800,000'}).waitFor();await page.locator('.miniMovementRow').filter({hasText:'تسديد'}).first().click();await page.getByRole('button',{name:'حذف التسديد',exact:true}).click();await page.getByRole('button',{name:'تأكيد حذف التسديد',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حذف التسديد'}).waitFor();await page.getByRole('button',{name:'رجوع لحساب العميل',exact:true}).click();await page.getByTestId('statement-balance').filter({hasText:'3,000,000'}).waitFor();
 await page.getByRole('button',{name:'مطابقة حساب',exact:true}).click();await page.getByLabel('الرصيد المتفق عليه',{exact:true}).fill('2900000');await page.getByLabel('ملاحظة المطابقة').fill('مطابقة من شاشة العميل المختصرة');await page.getByRole('button',{name:'حفظ مطابقة الحساب',exact:true}).click();await page.getByTestId('statement-balance').filter({hasText:'2,900,000'}).waitFor();
 await page.getByRole('button',{name:'كشف حساب',exact:true}).click();await page.locator('.miniStatementTable').waitFor();await page.getByRole('button',{name:'معاينة / PDF / مشاركة',exact:true}).click();await readyPDF(page);const csvEvent=page.waitForEvent('download');await page.getByRole('button',{name:'Excel',exact:true}).click();const csv=await csvEvent;await csv.saveAs(artifacts+'/customer-statement.csv');assert.match((await readFile(artifacts+'/customer-statement.csv')).toString(),/الرصيد/);await noOverflow(page);await page.screenshot({path:artifacts+'/customer-report-desktop.png',fullPage:true});
 await navigate(page,'customerStatement');await pickCustomer(page,'07703420001');await page.getByTestId('statement-balance').filter({hasText:'2,900,000'}).waitFor();await page.getByRole('button',{name:'بيع جديد',exact:true}).click();await page.locator('.partySearch input').filter({visible:true}).waitFor();assert.equal(await page.locator('.partySearch input').inputValue(),'عميل الواجهة المختصرة');assert.equal(await page.getByLabel('طريقة الدفع').inputValue(),'credit');
 console.log('PASS customer compact list, add/edit opening, seeded sale/payment, receipt edit/delete/retry, fresh reconciliation token, CSV/PDF and responsive account');
 await navigate(page,'suppliers');assert.equal(await page.locator('.supplierAccountCard').count(),0);assert.equal(await page.getByLabel('اسم المورد',{exact:true}).count(),0);await page.getByRole('button',{name:'مورد جديد',exact:true}).click();await page.getByLabel('اسم المورد',{exact:true}).fill('مورد الواجهة المختصرة');await page.getByLabel('هاتف المورد').fill('07703420002');await page.getByLabel('عملة حساب المورد',{exact:true}).selectOption('USD');await page.getByRole('button',{name:'حفظ المورد',exact:true}).click();await page.getByRole('button',{name:'حساب مورد الواجهة المختصرة',exact:true}).waitFor();await page.screenshot({path:artifacts+'/supplier-list-desktop.png',fullPage:true});await page.setViewportSize({width:390,height:900});await page.screenshot({path:artifacts+'/supplier-list-mobile.png',fullPage:true});await page.getByRole('button',{name:'حساب مورد الواجهة المختصرة',exact:true}).click();await page.getByTestId('supplier-statement-balance').filter({hasText:'0'}).waitFor();await page.getByRole('button',{name:'شراء جديد',exact:true}).click();assert.equal(await page.getByLabel('عملة الشراء',{exact:true}).inputValue(),'USD');assert.equal(await page.locator('.partySearch input').inputValue(),'مورد الواجهة المختصرة');await page.getByLabel('البحث عن مادة').focus();await page.getByRole('button',{name:'إضافة لوح اختبار الفواصل',exact:true}).click();await page.getByLabel('الكمية — لوح اختبار الفواصل').fill('1');await page.getByLabel('سعر الشراء — لوح اختبار الفواصل').pressSequentially('12.50');await page.getByRole('button',{name:'حفظ الوصل',exact:true}).click();await page.getByLabel('الكمية — لوح اختبار الفواصل').waitFor({state:'hidden'});
 async function openSupplier(){await navigate(page,'suppliers');await page.getByLabel('بحث الموردين').fill('07703420002');await page.getByRole('button',{name:'حساب مورد الواجهة المختصرة',exact:true}).click();await page.getByTestId('supplier-statement-balance').waitFor();}
 await openSupplier();await page.getByTestId('supplier-statement-balance').filter({hasText:'12.50'}).waitFor();await page.getByRole('button',{name:'تسديد جديد',exact:true}).click();await page.getByLabel('عملة حركة المورد').selectOption('USD');await page.getByLabel('مبلغ حركة المورد').pressSequentially('2.50');await page.getByLabel('ملاحظات حركة المورد').fill('دفع من شاشة المورد');await page.getByRole('button',{name:'حفظ التسديد وخصمه من القاصة',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حفظ التسديد بنجاح'}).waitFor();await page.getByRole('button',{name:'الرجوع إلى الحساب',exact:true}).click();await page.getByTestId('supplier-statement-balance').filter({hasText:/^10\s/}).waitFor();await openSupplier();await page.getByTestId('supplier-statement-balance').filter({hasText:/^10\s/}).waitFor();
 for(const width of [360,430,1366]){await page.setViewportSize({width,height:900});await noOverflow(page);await page.screenshot({path:artifacts+'/supplier-account-'+width+'.png',fullPage:true});}
 await page.locator('.miniMovementRow').filter({hasText:'تسديد مورد'}).first().click();await page.locator('.miniDetail').waitFor();await readyPDF(page);await page.screenshot({path:artifacts+'/supplier-movement-desktop.png',fullPage:true});await page.getByRole('button',{name:'تعديل الحركة',exact:true}).click();await page.getByLabel('مبلغ تعديل تسديد المورد').focus();await page.getByLabel('مبلغ تعديل تسديد المورد').fill('2.25');await page.getByRole('button',{name:'حفظ تعديل تسديد المورد',exact:true}).click();await page.getByRole('alert').filter({hasText:'لم يتأكد الرد'}).waitFor();await page.getByRole('button',{name:'إعادة تأكيد العملية',exact:true}).click();await page.getByRole('status').filter({hasText:'تم تعديل تسديد المورد'}).waitFor();await page.getByRole('button',{name:'تسديد جديد / رجوع',exact:true}).click();await page.getByTestId('supplier-statement-balance').filter({hasText:'10.25'}).waitFor();await page.locator('.miniMovementRow').filter({hasText:'تسديد مورد'}).filter({hasNotText:'ملغى'}).first().click();await page.getByRole('button',{name:'حذف التسديد',exact:true}).click();await page.getByRole('button',{name:'تأكيد حذف تسديد المورد',exact:true}).click();await page.getByRole('status').filter({hasText:'تم حذف أثر تسديد المورد'}).waitFor();await page.getByRole('button',{name:'تسديد جديد / رجوع',exact:true}).click();await page.getByTestId('supplier-statement-balance').filter({hasText:'12.50'}).waitFor();
 await page.getByRole('button',{name:'كل الحركات',exact:true}).click();assert.ok(await page.locator('.miniMovementRow').filter({hasText:'ملغى'}).count()>=2);await page.setViewportSize({width:390,height:900});await noOverflow(page);await page.screenshot({path:artifacts+'/supplier-movements-mobile.png',fullPage:true});await page.getByRole('button',{name:'رجوع للحساب',exact:true}).click();await page.getByRole('button',{name:'كشف حساب',exact:true}).click();await page.getByRole('button',{name:'معاينة / PDF / مشاركة',exact:true}).click();await readyPDF(page);await page.screenshot({path:artifacts+'/supplier-report-mobile.png',fullPage:true});
 console.log('PASS supplier compact list, USD seeded purchase, decimal payment, edit/delete/retry, cancellation postings, statement PDF and responsive detail');
 const creatorId='00000000-0000-0000-0000-000000003427';await sql(`insert into profiles(id,display_name,username,permissions) values('${creatorId}','موظف محدود','limited_creator','{"customerCreate":true}');`);const limited=await session(creatorId,390);await navigate(limited,'customers');assert.equal(await limited.locator('.miniPartyRow').count(),0);await limited.getByRole('button',{name:'زبون جديد',exact:true}).click();await limited.getByLabel('اسم الزبون',{exact:true}).fill('زبون المستخدم المحدود');await limited.getByRole('button',{name:'إضافة الزبون',exact:true}).click();await limited.getByRole('button',{name:'حساب زبون المستخدم المحدود',exact:true}).click();await limited.getByTestId('statement-balance').waitFor();assert.equal(await limited.getByRole('button',{name:'تعديل البيانات',exact:true}).count(),0);assert.equal(await limited.getByRole('button',{name:'تسديد جديد',exact:true}).count(),0);await noOverflow(limited);
 assert.deepEqual(errors,[]);console.log('PASS compact party workspaces: empty/search states, own-customer creation scope and no UI/API errors');
}catch(error){console.error('FAIL',error.message);for(const [i,context] of contexts.entries())for(const [j,page] of context.pages().entries())await page.screenshot({path:artifacts+`/failure-${i}-${j}.png`,fullPage:true,timeout:5000}).catch(()=>{});console.error('API/UI errors:',errors);throw error;}finally{await browser.close();}
