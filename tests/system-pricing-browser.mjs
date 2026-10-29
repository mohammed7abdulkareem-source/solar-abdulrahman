// Compiled application → local PostgREST → isolated PostgreSQL. No production writes.
process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
import assert from 'node:assert/strict';
import {createHmac,createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const db=process.env.SOLAR_FIXTURE_DB||'solar_v390_browser';
if(!/^solar_[a-z0-9_]+_browser$/.test(db))throw Error('Use an isolated local browser database');
const dir=process.env.SOLAR_ARTIFACT_DIR||'/workspace/solar-review/v390/browser';await mkdir(dir,{recursive:true});
const sql=q=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:q,encoding:'utf8'}).trim();
const ids={admin:'00000000-0000-0000-0000-000000003970',owner:'00000000-0000-0000-0000-000000003971',warehouse:'00000000-0000-0000-0000-000000003972',engineer:'00000000-0000-0000-0000-000000003973'};
const errors=[],calls=[],contexts=[],encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');let failBalance=false,dropPolicy=false;
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
async function open(who,section){
 const uid=ids[who],raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600}),token=raw+'.'+createHmac('sha256','solar-local-test-only-signing-secret-347').update(raw).digest('base64url');
 const ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true});contexts.push(ctx);ctx.setDefaultTimeout(20000);
 await ctx.addInitScript(({uid,token})=>{localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify({access_token:token,refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}}));window.__documentHtmls=[];window.__sharedPdfs=[];Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>true});Object.defineProperty(navigator,'share',{configurable:true,value:async data=>{const f=data.files[0];window.__sharedPdfs.push({name:f.name,active:navigator.userActivation.isActive,hash:Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await f.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join('')});}});const descriptor=Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype,'srcdoc');Object.defineProperty(HTMLIFrameElement.prototype,'srcdoc',{...descriptor,set(html){window.__documentHtmls.push(html);return descriptor.set.call(this,html);}});},{uid,token});
 await ctx.routeWebSocket(/supabase/,socket=>socket.close());
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),u=new URL(req.url());
  if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
  if(u.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:uid,email:'fixture@local.test',aud:'authenticated'})});
  if(!u.pathname.startsWith('/rest/v1/'))return route.abort();
  const payload=req.postData()?JSON.parse(req.postData()):null;
  if(failBalance&&u.pathname.endsWith('/solar_profit_workspace')&&payload?.action==='balance'){failBalance=false;return route.fulfill({status:503,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify({code:'TEST503',message:'تعذر تأكيد الرصيد التجريبي'})});}
  const headers={...req.headers(),authorization:'Bearer '+token};delete headers.apikey;delete headers.host;delete headers.origin;
  const r=await ctx.request.fetch('http://127.0.0.1:3079'+u.pathname.replace('/rest/v1','')+u.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});
  if(u.pathname.includes('/rpc/'))calls.push({who,path:u.pathname,payload,status:r.status()});
  if(r.status()>=400)errors.push({who,path:u.pathname,status:r.status(),body:await r.text()});
  if(dropPolicy&&u.pathname.endsWith('/solar_operation_control')&&payload?.payload?.kind==='system_pricing'&&r.status()===200){dropPolicy=false;return route.abort('failed');}
  return route.fulfill({response:r});
 });
 await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const page=await ctx.newPage();page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:3073/?section='+section);return {page,ctx,token};
}
const count=q=>Number(sql(q));
const financialHash=()=>sql("select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from transactions t),'items',(select jsonb_agg(to_jsonb(t)order by id)from transaction_items t),'stock',(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),'cash',(select jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text)from cash_ledger t),'entries',(select jsonb_agg(to_jsonb(t)order by id)from solar_cash_entries t))::text)");
async function product(p,name,qty=1){await p.getByRole('textbox',{name:'البحث عن مادة',exact:true}).fill(name);await p.getByRole('button',{name:'إضافة '+name,exact:true}).click();await p.getByLabel('الكمية — '+name,{exact:true}).fill(String(qty));}
async function customer(p){const box=p.getByRole('combobox',{name:'ابحث عن الزبون بالاسم أو الهاتف…',exact:true});await box.fill('زبون حد الربح');await p.getByRole('option',{name:/زبون حد الربح/}).click();await p.getByLabel('مهندس التنصيب',{exact:true}).selectOption(ids.engineer);await p.getByLabel('عنوان التنصيب',{exact:true}).fill('عنوان الاختبار المحلي');}
const refreshPolicy=p=>p.evaluate(()=>window.dispatchEvent(new Event('solar-operation-control')));
let page;
try{
 const admin=await open('admin','operationControl'),owner=await open('owner','system'),a=admin.page,p=owner.page;page=p;p.on('dialog',d=>d.accept());a.on('dialog',d=>d.accept());
 const control=a.getByRole('region',{name:'إعدادات البيع الحر للمنظومات',exact:true});
 await control.getByText('البيع الحر متاح',{exact:true}).waitFor();await p.getByText('البيع الحر للمنظومات متاح',{exact:true}).waitFor();
 await customer(p);await product(p,'مادة حد الربح');await p.getByLabel('سعر بيع المنظومة',{exact:true}).fill('1000000');
 const before=financialHash();dropPolicy=true;
 await control.getByRole('button',{name:'إيقاف البيع الحر واعتماد النسبة',exact:true}).click();
 await a.getByRole('button',{name:'إعادة تأكيد التغيير',exact:true}).click();
 await a.getByRole('status').filter({hasText:'تم اعتماد حد ربح 25٪'}).waitFor();
 assert.equal(count("select count(*)from solar_private.finance_requests where action='system_pricing_control'"),1);
 assert.equal(count("select count(*)from solar_notifications where title='تفعيل حد ربح المنظومات 25%'"),4);
 assert.equal(count("select count(*)from solar_private.push_deliveries"),1);assert.equal(financialHash(),before);
 await p.getByRole('button',{name:'فتح الإشعارات',exact:true}).click();await p.getByRole('dialog',{name:'الإشعارات',exact:true}).getByText('تفعيل حد ربح المنظومات 25%',{exact:true}).waitFor();await p.getByRole('dialog',{name:'الإشعارات',exact:true}).screenshot({path:dir+'/activation-notification.png'});await p.getByRole('dialog',{name:'الإشعارات',exact:true}).getByRole('button',{name:'إغلاق',exact:true}).click();
 await refreshPolicy(p);await p.getByTestId('system-minimum-price').filter({hasText:'1,250,000'}).waitFor();
 const save=p.getByRole('button',{name:'حفظ المنظومة وإسناد التنصيب',exact:true});assert.ok(await save.isDisabled());
 const rejected=await owner.ctx.request.post('http://127.0.0.1:3079/rpc/solar_invoice_save',{headers:{authorization:'Bearer '+owner.token},data:{request_id:'00000000-0000-0000-0000-000000397001',payload:{kind:'system',mode:'credit',party:'زبون حد الربح',partyId:-397001,installerId:ids.engineer,customerAddress:'محلي',total:1000000,cost:0,profit:99999999,items:[{id:-397001,qty:1,price:0}]}}});assert.equal(rejected.status(),422);assert.equal(financialHash(),before);
 await p.getByRole('button',{name:'استخدام الحد الأدنى للسعر',exact:true}).click();assert.equal((await p.getByLabel('سعر بيع المنظومة',{exact:true}).inputValue()).replaceAll(',',''),'1250000');
 await p.getByLabel('سعر بيع المنظومة',{exact:true}).fill('1300000');await p.screenshot({path:dir+'/seller-mandatory-25-higher-price.png',fullPage:true});await save.dblclick();
 await p.getByRole('heading',{name:/تم حفظ منظومة/}).waitFor();assert.equal(count("select count(*)from transactions where kind='system'"),1);
 let first=JSON.parse(sql("select row_to_json(t)from transactions t where kind='system'order by id limit 1"));assert.equal(first.total,1300000);assert.equal(first.cost,1000000);assert.equal(first.profit,300000);assert.equal(first.system_min_profit_percent,25);
 await control.getByLabel('نسبة الحد الأدنى لربح المنظومات',{exact:true}).selectOption('15');await control.getByRole('button',{name:'اعتماد نسبة 15٪',exact:true}).click();await a.getByRole('status').filter({hasText:'تم اعتماد حد ربح 15٪'}).waitFor();
 assert.equal(count("select count(*)from solar_notifications where title='تفعيل حد ربح المنظومات 15%'"),4);
 await refreshPolicy(p);await customer(p);await product(p,'مادة حد الربح');await product(p,'مادة ثانية للربح');
 await p.getByTestId('system-minimum-price').filter({hasText:'1,725,000'}).waitFor();await p.getByLabel('سعر بيع المنظومة',{exact:true}).fill('1700000');assert.ok(await save.isDisabled());await p.getByRole('button',{name:'استخدام الحد الأدنى للسعر',exact:true}).click();await Promise.all([p.waitForResponse(r=>r.url().endsWith('/solar_invoice_save')&&r.request().postDataJSON()?.payload?.total===1725000&&r.status()===200),save.click()]);
 await p.waitForFunction(()=>document.querySelectorAll('.warrantySaved h2').length>0);assert.equal(count("select count(*)from transactions where kind='system'"),2);
 const second=JSON.parse(sql("select row_to_json(t)from transactions t where kind='system'order by id desc limit 1"));assert.equal(second.total,1725000);assert.equal(second.cost,1500000);assert.equal(second.system_min_profit_percent,15);
 page=a;await a.goto('http://127.0.0.1:3073/?section=salesHistory');await a.locator('.saleHistoryCard').filter({hasText:'1,300,000'}).getByRole('button',{name:'تعديل الفاتورة',exact:true}).click();
 const editor=a.getByRole('region',{name:'تعديل فاتورة بيع منظومة',exact:true});await editor.getByLabel('تعديل مصاريف التنصيب المعتمدة',{exact:true}).fill('400000');await editor.getByTestId('system-minimum-price').filter({hasText:'1,750,000'}).waitFor();assert.ok(await editor.getByRole('button',{name:'حفظ التعديل',exact:true}).isDisabled());
 await editor.getByRole('button',{name:'استخدام نسبة الإدارة الحالية 15٪',exact:true}).click();await editor.getByTestId('system-minimum-price').filter({hasText:'1,610,000'}).waitFor();await editor.screenshot({path:dir+'/expense-and-repricing-minimum.png'});await editor.getByRole('button',{name:'حفظ التعديل',exact:true}).click();await a.locator('.salesArchive').waitFor();
 first=JSON.parse(sql('select row_to_json(t)from transactions t where id='+first.id));assert.equal(first.total,1610000);assert.equal(first.installation_expenses,400000);assert.equal(first.profit,210000);assert.equal(first.system_min_profit_percent,15);
 await a.goto('http://127.0.0.1:3073/?section=operationControl');await a.getByRole('region',{name:'إعدادات البيع الحر للمنظومات',exact:true}).getByRole('button',{name:'تشغيل البيع الحر وإلغاء حد الربح',exact:true}).click();await a.getByRole('status').filter({hasText:'تم تشغيل البيع الحر'}).waitFor();assert.equal(count("select count(*)from solar_notifications where title='تشغيل البيع الحر للمنظومات'"),4);
 page=p;await refreshPolicy(p);await p.getByText('البيع الحر للمنظومات متاح',{exact:true}).waitFor();await customer(p);await product(p,'مادة حد الربح');await p.getByLabel('سعر بيع المنظومة',{exact:true}).fill('500000');await Promise.all([p.waitForResponse(r=>r.url().endsWith('/solar_invoice_save')&&r.request().postDataJSON()?.payload?.total===500000&&r.status()===200),save.click()]);assert.equal(count("select count(*)from transactions where kind='system'"),3);
 const free=JSON.parse(sql("select row_to_json(t)from transactions t where kind='system'order by id desc limit 1"));assert.equal(free.total,500000);assert.equal(free.system_min_profit_percent,null);
 const denied=await owner.ctx.request.post('http://127.0.0.1:3079/rpc/solar_operation_control',{headers:{authorization:'Bearer '+owner.token},data:{request_id:'00000000-0000-0000-0000-000000397002',payload:{kind:'system_pricing',freePricing:false,markupPercent:25,expectedRevision:0}}});assert.equal(denied.status(),403);
 page=a;await a.getByRole('button',{name:'إيقاف بيع المنظومات',exact:true}).click();await a.getByRole('status').filter({hasText:'تم الإيقاف وإشعار جميع المستخدمين.'}).waitFor();await refreshPolicy(p);await p.getByText('البيع متوقف مؤقتًا',{exact:true}).waitFor();assert.equal(await p.locator('fieldset.deskForm').evaluate(el=>el.disabled),true);assert.ok(await save.isDisabled());
 await a.getByRole('button',{name:'استئناف بيع المنظومات',exact:true}).click();await a.getByRole('status').filter({hasText:'تم الاستئناف وإشعار جميع المستخدمين.'}).waitFor();
 for(const width of[360,768,1440]){await a.setViewportSize({width,height:920});assert.ok(await a.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await a.screenshot({path:dir+'/controls-'+width+'.png'});}
 assert.deepEqual(errors,[]);await writeFile(dir+'/results.json',JSON.stringify({pass:true,minimum25AndHigher:true,minimum15OnTotalSystem:true,expensesAndRepricing:true,freePricingLifted:true,notificationsAndPushOnce:true,controlLostAckReplayOnce:true,staleOpenFormRefresh:true,belowLimitRejectedAtAPI:true,rollbackLeavesFinancialHashUnchanged:true,adminOnlyAtAPI:true,fullPauseIndependent:true,noOverflow:[360,768,1440],calls,errors},null,2));console.log('PASS real browser/API/database: 25/15 total-cost minimum, above-floor sale, expenses/repricing, free mode, exact notifications/push retry, independent pause, server permissions and responsive layouts');
}catch(error){if(page)await page.screenshot({path:dir+'/failure.png',fullPage:true}).catch(()=>{});await writeFile(dir+'/failure.json',JSON.stringify({error:String(error),stack:error.stack,calls,errors},null,2));throw error;}finally{for(const ctx of contexts)await ctx.close();await browser.close();}
