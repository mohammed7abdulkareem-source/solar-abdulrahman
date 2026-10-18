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
     if(name==='solar_profit_workspace'&&data.action==='approve'&&dropOnce){dropOnce=false;return route.abort('failed');}
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
const artifacts='/workspace/solar-review/profit-v343';await mkdir(artifacts,{recursive:true});
await sql(`insert into profiles(id,display_name,username,is_admin,permissions) values('${owner}','إدارة الأرباح','profit_admin_ui',true,'{}'),('${staff}','أشرف الأرباح','profit_staff_ui',false,'{"profit":true,"profitSettlement":true}');
insert into transactions(id,kind,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id,created_at) values(-343501,'sale',500000,500000,100000,true,false,'credit','${staff}','${staff}',now()-interval '1 day');`);
await sql(`select public.solar_cash_save(gen_random_uuid(),'${JSON.stringify({ownerId:owner,mode:'capital_deposit',currency:'IQD',amount:500000,note:'رصيد اختبار الصرف'})}');`,owner);
async function navigate(page,id){await page.locator('.premiumMobileBrand').click();await page.locator('.sectionDirectory a[href="/?section='+id+'"]').click();}
async function noOverflow(page){assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'horizontal overflow');}
const employee=await session(staff,390);await navigate(employee,'profit');
await employee.getByRole('heading',{name:'أرباحي',exact:true}).waitFor();await employee.locator('.staffProfitMetrics .available b').waitFor();
assert.match(await employee.locator('.staffProfitMetrics .available').innerText(),/100,000/);
assert.equal(await employee.getByRole('button',{name:'أرباح الشركة',exact:true}).count(),0);
await noOverflow(employee);await employee.screenshot({path:artifacts+'/my-profits-mobile.png',fullPage:true});
await employee.getByLabel('ملاحظة طلب التسوية').fill('حصة هذا الأسبوع');
await employee.getByRole('button',{name:'طلب تسوية أرباح الفترة',exact:true}).click();await employee.getByText('تم إرسال الطلب للإدارة.',{exact:true}).waitFor();
assert.equal(await jsonSql("select count(*) from solar_private.profit_settlements where status='pending'"),1);
const manager=await session(owner,1366);await navigate(manager,'profit');await manager.getByRole('button',{name:/تسويات المستخدمين/}).click();
await manager.locator('.profitRequest.pending').click();await manager.getByLabel('نسبة حصة المستخدم').fill('25');
assert.equal(await manager.getByLabel('حصة المستخدم بالدينار').inputValue(),'25,000');
await manager.getByLabel('قاصة صرف حصة الأرباح').selectOption(owner);
assert.equal(await manager.getByRole('button',{name:'موافقة وصرف الحصة'}).isDisabled(),true);
await manager.getByText('راجعت التحصيل وأؤكد صرف الحصة وإغلاق ربح الفترة',{exact:true}).click();
await manager.getByLabel('ملاحظة قرار التسوية').fill('تم اعتماد حصة أشرف عن الفترة');
await noOverflow(manager);await manager.screenshot({path:artifacts+'/approval-desktop.png',fullPage:true});
await manager.getByRole('button',{name:'موافقة وصرف الحصة',exact:true}).click();await manager.waitForFunction(()=>Array.from(document.querySelectorAll('button')).some(b=>b.textContent==='إعادة تأكيد العملية'&&!b.disabled));
assert.equal(await jsonSql('select count(*) from transactions where profit_settlement_id is not null'),1);
await manager.getByRole('button',{name:'إعادة تأكيد العملية',exact:true}).click();await manager.getByText('تم صرف الحصة وتسجيلها مصروف عمل وإغلاق أرباح الفترة.',{exact:true}).waitFor();
assert.equal(await jsonSql('select count(*) from transactions where profit_settlement_id is not null'),1);
assert.equal(await jsonSql("select solar_private.cash_balance('"+owner+"')"),475000);
await manager.getByRole('button',{name:'أرباح الشركة',exact:true}).click();await manager.locator('.profitWorkspace').waitFor();
assert.match(await manager.locator('.profitResultSummary').innerText(),/25,000/);assert.match(await manager.locator('.profitResultSummary').innerText(),/75,000/);
await employee.getByRole('button',{name:'تحديث',exact:true}).last().click();
await employee.locator('.profitRequest.approved').waitFor();assert.match(await employee.locator('.staffProfitMetrics .available').innerText(),/0/);
await employee.locator('.profitRequest.approved').click();await employee.locator('.profitApproval').waitFor();
assert.match(await employee.locator('.profitApproval').innerText(),/25,000/);await noOverflow(employee);await employee.screenshot({path:artifacts+'/paid-history-mobile.png',fullPage:true});
const pdf=employee.locator('.profitApproval .reportExport').last();await pdf.getByText(/المستند جاهز/).waitFor();
const download=employee.waitForEvent('download');await pdf.getByRole('button',{name:'حفظ PDF',exact:true}).click();const saved=await download;assert.match(saved.suggestedFilename(),/pdf$/);
await pdf.getByRole('button',{name:'مشاركة',exact:true}).click();await pdf.getByText('تمت مشاركة ملف PDF.',{exact:true}).waitFor();
await manager.getByRole('button',{name:/تسويات المستخدمين/}).click();await manager.setViewportSize({width:390,height:900});await noOverflow(manager);await manager.screenshot({path:artifacts+'/admin-settlements-mobile.png',fullPage:true});
// No browser exception and no unexpected server error was accepted.
assert.deepEqual(errors,[]);console.log('PASS mobile own-only credit profit → request → admin percentage/box/review → lost-response retry → one company expense and cash deduction → closed user balance with saved history');
for(const ctx of contexts)await ctx.close();await browser.close();
