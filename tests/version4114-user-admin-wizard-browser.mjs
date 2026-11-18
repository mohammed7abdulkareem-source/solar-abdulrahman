// Uses a synthetic admin session issued by real GoTrue and a local Edge gateway.
import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base=process.env.SOLAR_APP_URL||'http://127.0.0.1:3101';
const gateway=process.env.SOLAR_FIXTURE_GATEWAY||'http://127.0.0.1:3200';
const db=process.env.SOLAR_FIXTURE_DB||'solar_v4114_wizard_browser';
const dir=process.env.SOLAR_ARTIFACT_DIR||'/workspace/solar-review/v4114/user-admin-browser';
for(const endpoint of [base,gateway])assert.equal(new URL(endpoint).hostname,'127.0.0.1');
assert.equal(db,'solar_v4114_wizard_browser');
const admin=JSON.parse(await readFile(process.env.SOLAR_ADMIN_FIXTURE_SESSION,'utf8'));
assert.ok(admin.access_token&&admin.user?.id,'expected a local GoTrue session');
const sql=q=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:q,encoding:'utf8'}).trim();
const tag=randomUUID().slice(0,8),username='wizard_'+tag,password=randomBytes(18).toString('base64url');
const display='مندوب تجريبي '+tag,phone='07704114123';
const stored=()=>JSON.parse(sql(`select coalesce((select to_jsonb(p) from profiles p where username='${username}'),'null'::jsonb)`));
const route=base+'/?section=users',actions=[],errors=[],checks={},contexts=[];
await mkdir(dir,{recursive:true});
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
async function pageFor(session){
 const ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true});
 contexts.push(ctx);ctx.setDefaultTimeout(18000);
 await ctx.addInitScript(s=>localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify(s)),session);
 await ctx.routeWebSocket(/supabase/,ws=>ws.close());
 await ctx.route('**/*',async route=>{
  const request=route.request(),url=new URL(request.url());
  if(url.hostname==='127.0.0.1'||['data:','blob:'].includes(url.protocol))return route.continue();
  if(url.hostname!=='afxxaafsuscwyjzrnagc.supabase.co')return route.abort();
  const cors={'access-control-allow-origin':'*','access-control-allow-methods':'GET,POST,PATCH,HEAD,DELETE,OPTIONS',
   'access-control-allow-headers':'*','access-control-expose-headers':'content-range,range-unit,preference-applied'};
  if(request.method()==='OPTIONS')return route.fulfill({status:204,headers:cors});
  const headers={...request.headers()};
  delete headers.host;delete headers.origin;
  const response=await ctx.request.fetch(gateway+url.pathname+url.search,{method:request.method(),headers,data:request.postDataBuffer()||undefined});
  if(url.pathname.endsWith('/solar-admin-users')){
   const action=request.postDataJSON()?.action||'list';
   actions.push({actor:session.user.id,action,status:response.status()});
  }
  if(response.status()>=500)errors.push({path:url.pathname,status:response.status()});
  await route.fulfill({response,headers:{...response.headers(),...cors}});
 });
 const page=await ctx.newPage();page.on('pageerror',e=>errors.push(e.message));
 await page.goto(route);return page;
}
async function screenshots(page,region,label){
 for(const width of [360,1366]){
  await page.setViewportSize({width,height:920});await region.scrollIntoViewIfNeeded();
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),label+' overflows at '+width);
  await page.screenshot({path:dir+'/'+label+'-'+width+'.png',animations:'disabled'});
 }
 await page.setViewportSize({width:390,height:920});
}
let page;
try{
 page=await pageFor(admin);
 const manager=page.locator('.userAdminWorkspace');
 const step=n=>page.locator('.userAdminWizard[data-step="'+n+'"]');
 const row=id=>manager.locator('[data-user-id="'+id+'"]');
 const byName=(region,name)=>region.getByRole('button',{name,exact:true});
 const perm=key=>step(2).locator('[data-permission="'+key+'"]');
 await manager.getByRole('heading',{name:'المستخدمون والصلاحيات'}).waitFor();
 await manager.getByRole('searchbox',{name:'بحث المستخدمين'}).waitFor();
 assert.equal(await page.locator('.userAdminWizard:visible').count(),0);
 await manager.locator('.uaUserList').waitFor();
 assert.equal(await byName(row(admin.user.id),'حذف').count(),0,'administrator could remove their own login');
 await screenshots(page,manager,'directory');
 await byName(manager,'إضافة مستخدم').click();
 const identity=step(1);await identity.waitFor();
 await identity.getByLabel('اسم المستخدم',{exact:true}).fill(username);
 await identity.getByLabel('الاسم الظاهر',{exact:true}).fill(display);
 await identity.getByLabel('رقم هاتف المستخدم',{exact:true}).fill(phone);
 await identity.getByLabel('كلمة المرور',{exact:true}).fill(password);
 assert.equal(await identity.getByLabel('نوع المستخدم',{exact:true}).count(),0,'role belongs with access settings');
 await screenshots(page,identity,'identity');
 await byName(identity,'حفظ البيانات والمتابعة').click();
 await step(2).waitFor();
 const account=stored();
 assert.equal(account.active,false,'new identity must remain inactive before final review');
 assert.equal(account.is_admin,false);assert.equal(account.phone,phone);
 const hasBusinessRights=p=>['sale','purchase','stock','profit','users','cash','exchangeRate','tahseel','tahseelFull','tahseelDefaults','warranty','system'].some(k=>p?.[k]===true);
 assert.equal(hasBusinessRights(account.permissions),false,'new inactive identity has a feature grant');
 await byName(step(2),'رجوع إلى الدليل').click();
 const leave=page.locator('dialog.uaConfirm[open]');
 if(await leave.isVisible())await byName(leave,'الرجوع إلى الدليل').click();
 await row(account.id).waitFor();
 await row(account.id).getByText('موقوف',{exact:true}).waitFor();
 await byName(row(account.id),'تعديل').click();
 assert.equal(await identity.getByLabel('الاسم الظاهر',{exact:true}).inputValue(),display);
 assert.equal(await identity.getByLabel('كلمة المرور',{exact:true}).inputValue(),'');
 await byName(identity,'حفظ البيانات والمتابعة').click();
 await step(2).waitFor();
 checks.newIdentityPersisted=true;

 await step(2).getByLabel('نوع المستخدم',{exact:true}).selectOption('user');
 async function enablePermission(key){
  const box=perm(key),group=box.locator('xpath=ancestor::details[1]');
  if(!(await box.isVisible()))await group.locator('summary').click();
  await box.check();
 }
 await enablePermission('tahseelDefaults');
 for(const key of ['tahseel','tahseelFull','tahseelDefaults'])assert.ok(await perm(key).isChecked(),key);
 await perm('tahseelFull').uncheck();
 assert.equal(await perm('tahseelDefaults').isChecked(),false,'defaults requires full quote management');
 assert.ok(await perm('tahseel').isChecked(),'basic quote access survives removing full management');
 await enablePermission('warranty');
 await screenshots(page,step(2),'permissions');
 await byName(step(2),'مراجعة المخازن').click();
 await step(3).waitFor();
 checks.permissionDependencies=true;
 // Warehouse, review, reset and removal scenarios below use the same saved identity.
 const location=JSON.parse(sql("select to_jsonb(w) from solar_private.warehouses w where active order by is_primary,id limit 1"));
 const warehouseMembership=()=>JSON.parse(sql(`select to_jsonb(a) from solar_private.warehouse_access a where user_id='${account.id}'`));
 await step(3).getByRole('radio',{name:'مخازن محددة'}).check();
 const places=step(3).getByRole('group',{name:'المخازن المسموحة'});
 for(const other of await places.getByRole('checkbox').all())if(await other.isChecked())await other.uncheck();
 await places.getByRole('checkbox',{name:location.name,exact:true}).check();
 await byName(step(3),'مراجعة الحساب').click();
 await step(4).getByText(location.name,{exact:false}).waitFor();
 await step(4).getByRole('radio',{name:'فعّال',exact:true}).check();
 await screenshots(page,step(4),'review');
 await byName(step(4),'حفظ إعدادات المستخدم').click();
 await row(account.id).waitFor();
 const saved=stored();
 assert.equal(saved.active,true);assert.equal(saved.permissions.tahseel,true);assert.equal(saved.permissions.warranty,true);
 assert.notEqual(saved.permissions.tahseelFull,true);assert.notEqual(saved.permissions.cash,true);assert.equal(saved.is_admin,false);
 assert.deepEqual(warehouseMembership().warehouse_ids,[location.id]);assert.equal(warehouseMembership().all_warehouses,false);
 checks.reviewCommitted=true;
 const query=manager.getByRole('searchbox',{name:'بحث المستخدمين'});
 await query.fill(tag);
 assert.equal(await manager.locator('[data-user-id]').count(),1);
 await manager.getByRole('combobox',{name:'حالة الحساب'}).selectOption('inactive');
 await row(account.id).waitFor({state:'hidden'});
 await manager.getByRole('combobox',{name:'حالة الحساب'}).selectOption('active');
 await row(account.id).waitFor();
 const signIn=await fetch(gateway+'/auth/v1/token?grant_type=password',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email:username+'@solar-user.local',password})});
 assert.ok(signIn.ok,'newly activated account should authenticate');
 const memberSession=await signIn.json();
 const member=await pageFor(memberSession);
 await member.locator('.smoothFrame').waitFor();
 assert.equal(await member.locator('.userAdminWorkspace').count(),0,'staff account opened user management');
 const membershipProbe=await fetch(gateway+'/functions/v1/solar-admin-users',{method:'POST',headers:{authorization:'Bearer '+memberSession.access_token,'content-type':'application/json'},body:JSON.stringify({action:'directory'})});
 assert.ok([400,401,403].includes(membershipProbe.status),'staff could call administrator directory');
 checks.createdUserRestricted=true;

 await byName(row(account.id),'تعديل').click();
 await step(1).getByLabel('الاسم الظاهر',{exact:true}).fill(display+' المعدل');
 await byName(step(1),'حفظ البيانات والمتابعة').click();
 await step(2).waitFor();
 assert.equal(stored().display_name,display+' المعدل');
 assert.equal(stored().permissions.tahseel,true,'saving identity discarded existing features');
 await byName(step(2),'تصفير الصلاحيات').click();
 const confirm=page.locator('dialog.uaConfirm[open]');
 await byName(confirm,'إلغاء').click();
 assert.ok(await perm('tahseel').isChecked());assert.equal(stored().permissions.warranty,true);
 await byName(step(2),'تصفير الصلاحيات').click();
 await byName(confirm,'تأكيد التصفير').click();
 assert.equal(await perm('warranty').isChecked(),false);
 assert.equal(stored().permissions.tahseel,true,'staged reset changed live permissions before finalize');
 await byName(step(2),'مراجعة المخازن').click();
 assert.equal(await step(3).getByRole('checkbox',{name:location.name,exact:true}).isChecked(),true);
 await byName(step(3),'مراجعة الحساب').click();
 await byName(step(4),'حفظ إعدادات المستخدم').click();
 await row(account.id).waitFor();
 assert.equal(hasBusinessRights(stored().permissions),false);
 assert.equal(stored().active,true);assert.deepEqual(warehouseMembership().warehouse_ids,[location.id]);
 checks.resetSavedWithoutBroadening=true;

 await byName(row(account.id),'حذف').click();
 await byName(confirm,'إلغاء').click();
 assert.ok(stored(),'cancelling removal deleted the account');
 await byName(row(account.id),'حذف').click();
 await byName(confirm,'تأكيد حذف الحساب').click();
 await row(account.id).waitFor({state:'hidden'});
 assert.equal(stored(),null,'new clean synthetic account should be deleted');
 checks.cleanRemovalConfirmed=true;
 const historyName='history_'+tag,historyId=randomUUID(),historicalInvoice=Date.now();
 const seedReply=await fetch(gateway+'/functions/v1/solar-admin-users',{method:'POST',headers:{authorization:'Bearer '+admin.access_token,'content-type':'application/json'},body:JSON.stringify({action:'save_details',request_id:historyId,username:historyName,display_name:'موظف ذو سجل '+tag,phone,honorific:'',password})});
 assert.ok(seedReply.ok,'could not prepare isolated historical account');
 const historyUser=(await seedReply.json()).user;
 assert.equal(historyUser.id,historyId);
 const activated=await fetch(gateway+'/functions/v1/solar-admin-users',{method:'POST',headers:{authorization:'Bearer '+admin.access_token,'content-type':'application/json'},body:JSON.stringify({action:'finalize',request_id:randomUUID(),user_id:historyId,token:historyUser.token,permissions:{sale:true},role:'user',warehouse:null,active:true})});
 assert.ok(activated.ok,'could not activate isolated historical account');
 assert.equal((await activated.json()).user.active,true);
 sql(`insert into transactions(id,kind,total,subtotal,cost,profit,payment_mode,cash,fx_pricing,created_by,cashbox_user_id,party_name)
 values(${historicalInvoice},'sale',2200,2200,1200,1000,'credit',false,true,'${historyId}','${historyId}','وصل للتحقق من الأرشفة');`);
 const historicReceipt=()=>sql(`select to_jsonb(t)::text from transactions t where id=${historicalInvoice}`);
 const originalReceipt=historicReceipt();
 await manager.getByRole('combobox',{name:'حالة الحساب'}).selectOption('all');
 await query.fill(historyName);
 await manager.getByRole('button',{name:'تحديث دليل المستخدمين'}).click();
 await byName(row(historyId),'حذف').click();
 await byName(confirm,'تأكيد حذف الحساب').click();
 await manager.getByText(/تمت أرشفة حساب/).waitFor();
 assert.equal(sql(`select active from profiles where id='${historyId}'`),'f');
 assert.equal(historicReceipt(),originalReceipt,'archiving rewrote the historical receipt');
 checks.historicalArchive=true;
 assert.deepEqual(errors,[]);
 await writeFile(dir+'/results.json',JSON.stringify({pass:true,checks,actions},null,2));
 console.log('PASS real-admin wizard, persistent inactive identity, dependencies, restricted staff, warehouse scope, reset, and confirmed removal');
}catch(error){
 await page?.screenshot({path:dir+'/failure.png'}).catch(()=>{});
 await writeFile(dir+'/failure.json',JSON.stringify({error:String(error),stack:error.stack,checks,actions,errors},null,2));throw error;
}finally{
 for(const ctx of contexts)await ctx.unrouteAll({behavior:'ignoreErrors'}).catch(()=>{});
 await browser.close();
}
