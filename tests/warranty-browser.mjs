import {PNG} from 'pngjs';
import jsQR from 'jsqr';
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
    else if(['solar_warehouse_orders'].includes(name))body={rows:[],count:0};
    else if(['solar_installation_jobs','solar_stock_movements'].includes(name))body=[];
    else if(name==='solar_stock_quantities')body=await jsonSql("select jsonb_agg(to_jsonb(p)) from public.products p");
    else {
     assert.match(name,/^solar_[a-z_]+$/);const args=Object.entries(data).map(([key,value])=>{assert.match(key,/^[a-z_]+$/);return key+'=>'+(value===null?'null':typeof value==='object'?sqlLiteral(JSON.stringify(value))+'::jsonb':typeof value==='number'?String(value):sqlLiteral(value));}).join(',');
     if(name==='solar_cash_transfer_decide'){await sql('select public.'+name+'('+args+')',uid);body=null;}else body=await jsonSql('select to_jsonb(public.'+name+'('+args+'))',uid);
     if(name==='solar_invoice_save'&&dropOnce){dropOnce=false;return route.abort('failed');}
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
const artifacts='/workspace/solar-review/warranty-v344';await mkdir(artifacts,{recursive:true});
await sql(`insert into profiles(id,display_name,username,is_admin,permissions,user_type) values('${owner}','مدير الضمان','warranty_admin',true,'{}','admin_staff'),('${staff}','موظف الضمان','warranty_staff',false,'{"sale":true,"system":true,"salesHistory":true}','admin_staff'),('00000000-0000-0000-0000-000000003503','مهندس الضمان','warranty_installer',false,'{}','installer');
insert into customers(id,name,customer_type,owner_id) values(-344501,'زبون ضمان الجملة','wholesale','${owner}'),(-344502,'زبون ضمان المنظومة','system','${owner}');insert into products(id,code,name,qty,cost) values(-344501,'W-UI-1','لوح ضمان اختباري',10,100000);`);
async function navigate(page,id){await page.locator('.premiumMobileBrand').click();await page.locator('.sectionDirectory a[href="/?section='+id+'"]').click();}
async function noOverflow(page){assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'horizontal overflow');}
const page=await session(owner,390);await navigate(page,'sale');
await page.locator('.partySearch input').fill('زبون ضمان الجملة');await page.locator('.partySearchResults button').filter({hasText:'زبون ضمان الجملة'}).click();
await page.getByLabel('البحث عن مادة',{exact:true}).fill('لوح ضمان');await page.getByRole('button',{name:'إضافة لوح ضمان اختباري',exact:true}).click();await page.getByLabel('الكمية — لوح ضمان اختباري').fill('1');await page.getByLabel('سعر البيع — لوح ضمان اختباري').fill('150000');
assert.equal(await page.getByLabel('مدة ضمان لوح ضمان اختباري').count(),0);
await page.getByRole('checkbox',{name:/إضافة ضمان للفاتورة/}).check();await page.getByLabel('مدة ضمان لوح ضمان اختباري').fill('5');await page.getByLabel('وحدة ضمان لوح ضمان اختباري').selectOption('years');await page.getByLabel('مدة ضمان الصيانة').fill('6');await page.getByLabel('شروط الضمان').fill('يشمل عيوب الصناعة');await noOverflow(page);await page.screenshot({path:artifacts+'/wholesale-warranty-mobile.png',fullPage:true});
await page.getByRole('button',{name:'حفظ الوصل',exact:true}).click();await page.getByRole('alert').waitFor();
await page.getByRole('button',{name:'حفظ الوصل',exact:true}).click();await page.locator('.warrantySaved').filter({hasText:'تم حفظ فاتورة'}).waitFor();
assert.equal(await jsonSql('select count(*) from solar_private.warranty_certificates'),1);assert.equal(await jsonSql('select qty from products where id=-344501'),9);
const receipt=page.locator('.warrantySaved').filter({hasText:'تم حفظ فاتورة'});await receipt.getByText(/المستند جاهز/).waitFor();
const popupPromise=page.waitForEvent('popup');await receipt.getByRole('button',{name:'معاينة',exact:true}).click();const popup=await popupPromise;await popup.locator('.pdfPage img').first().waitFor();
const qrPNG=Buffer.from(await popup.locator('.pdfPage img').first().evaluate(async img=>{await img.decode();const canvas=document.createElement('canvas');canvas.width=img.naturalWidth;canvas.height=img.naturalHeight;canvas.getContext('2d').drawImage(img,0,0);return canvas.toDataURL('image/png').split(',')[1];}),'base64');await import('node:fs/promises').then(fs=>fs.writeFile(artifacts+'/printed-invoice.png',qrPNG));const png=PNG.sync.read(qrPNG),decoded=jsQR(new Uint8ClampedArray(png.data),png.width,png.height);assert.ok(decoded,'QR must scan from the actual rasterized customer invoice');const link=decoded.data;await popup.close();
const certificate=await jsonSql("select jsonb_build_object('token',token,'document',document) from solar_private.warranty_certificates limit 1");assert.equal(link,'https://solar-abdulrahman.vercel.app/warranty/'+certificate.token);
async function publicContext(){const ctx=await browser.newContext({viewport:{width:390,height:900}});contexts.push(ctx);ctx.setDefaultTimeout(15000);await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{const req=route.request();const headers={'access-control-allow-origin':'*','content-type':'application/json'};if(req.method()==='OPTIONS')return route.fulfill({status:204,headers});assert.ok(req.url().endsWith('/rpc/solar_warranty_verify'));const input=req.postDataJSON();const data=await jsonSql('select public.solar_warranty_verify('+sqlLiteral(input.certificate_token)+'::uuid)');await route.fulfill({status:200,headers,body:JSON.stringify(data)});});await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});return ctx;}
const customer=await publicContext(),scan=await customer.newPage();await scan.goto((process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3038')+'/warranty');await scan.locator('input[type=file]').setInputFiles({name:'invoice.png',mimeType:'image/png',buffer:qrPNG});await scan.getByRole('heading',{name:'شهادة ضمان الفاتورة'}).waitFor();await scan.getByText('زبون ضمان الجملة',{exact:true}).waitFor();assert.equal(await scan.getByText('ضمن الضمان',{exact:true}).count(),2);await noOverflow(scan);await scan.screenshot({path:artifacts+'/public-certificate-mobile.png',fullPage:true});
await navigate(page,'salesHistory');await page.locator('.archiveInvoice').first().getByRole('button',{name:'ضمان الفاتورة',exact:true}).click();await page.getByLabel('مدة ضمان لوح ضمان اختباري').fill('3');await page.getByRole('button',{name:'حفظ ضمان الفاتورة',exact:true}).click();await page.getByText('تم حفظ الضمان. رمز الوصل نفسه يعرض آخر تحديث.',{exact:true}).waitFor();assert.equal(await jsonSql('select count(*) from solar_private.warranty_certificates'),1);assert.equal(await jsonSql('select qty from products where id=-344501'),9);
await navigate(page,'system');await page.locator('.partySearch input').fill('زبون ضمان المنظومة');await page.locator('.partySearchResults button').filter({hasText:'زبون ضمان المنظومة'}).click();await page.getByLabel('مهندس التنصيب',{exact:true}).selectOption('00000000-0000-0000-0000-000000003503');await page.getByLabel('عنوان التنصيب',{exact:true}).fill('عنوان ضمان المنظومة');await page.getByLabel('البحث عن مادة',{exact:true}).fill('لوح ضمان');await page.getByRole('button',{name:'إضافة لوح ضمان اختباري',exact:true}).click();await page.getByLabel('الكمية — لوح ضمان اختباري').fill('1');await page.getByLabel('سعر بيع المنظومة',{exact:true}).fill('300000');await page.getByRole('checkbox',{name:/إضافة ضمان للفاتورة/}).check();await page.getByLabel('مدة ضمان لوح ضمان اختباري').fill('10');await page.getByLabel('وحدة ضمان لوح ضمان اختباري').selectOption('years');await page.getByLabel('مدة ضمان الصيانة').fill('12');await page.setViewportSize({width:1366,height:900});await noOverflow(page);await page.screenshot({path:artifacts+'/system-warranty-desktop.png',fullPage:true});await page.getByRole('button',{name:'حفظ المنظومة وإسناد التنصيب',exact:true}).click();await page.locator('.warrantySaved').filter({hasText:'تم حفظ منظومة'}).waitFor();assert.equal(await jsonSql('select count(*) from solar_private.warranty_certificates'),2);
const systemCert=await jsonSql("select jsonb_build_object('token',token) from solar_private.warranty_certificates where document->>'kind'='system'");await scan.goto((process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3039')+'/warranty/'+systemCert.token);await scan.getByText('زبون ضمان المنظومة',{exact:true}).waitFor();await scan.getByText('عنوان ضمان المنظومة',{exact:true}).waitFor();await scan.getByText('مهندس الضمان',{exact:true}).waitFor();
// Disabling warranty must invalidate the same QR immediately.
await sql(`select public.solar_warranty_manage('save',gen_random_uuid(),jsonb_build_object('id',${certificate.document.invoiceId},'expectedToken',public.solar_warranty_manage('get',null,'{"id":${certificate.document.invoiceId}}')->>'expectedToken','warranty','{"enabled":false}'::jsonb))`,owner);await scan.goto((process.env.SOLAR_TEST_BASE_URL||'http://127.0.0.1:3039')+'/warranty/'+certificate.token);await scan.getByText('لا يوجد ضمان فعّال لهذه الفاتورة.',{exact:true}).waitFor();assert.equal(await scan.getByText('ضمن الضمان',{exact:true}).count(),0);
assert.deepEqual(errors,[]);console.log('PASS mobile wholesale/system optional warranty, atomic invoice retry, actual PDF QR decode, anonymous image scan, current certificate, saved warranty edit without stock/cash changes, revocation and responsive layouts');for(const ctx of contexts)await ctx.close();await browser.close();
