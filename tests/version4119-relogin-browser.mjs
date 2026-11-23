// Chromium calls the actual public login Edge handler backed by disposable GoTrue and PostgreSQL.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {randomBytes,randomUUID} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {createClient} from '@supabase/supabase-js';
import {createLoginHandler} from '../supabase/functions/solar-login/handler.mjs';

const endpoints={
 app:process.env.SOLAR_APP_URL||'http://127.0.0.1:3263',
 auth:process.env.SOLAR_AUTH_URL||'http://127.0.0.1:3260',
 rest:process.env.SOLAR_FIXTURE_API||'http://127.0.0.1:3261',
 bridge:process.env.SOLAR_AUTH_BRIDGE||'http://127.0.0.1:3262'
};
for(const value of Object.values(endpoints))assert.equal(new URL(value).hostname,'127.0.0.1');
const database=process.env.SOLAR_FIXTURE_DB||'solar_v4119_auth_browser';
assert.equal(database,'solar_v4119_auth_browser');
const keys=JSON.parse(await readFile(process.env.SOLAR_AUTH_FIXTURE||'/workspace/solar-review/v4119/auth-fixture.json','utf8'));
const artifacts=process.env.SOLAR_ARTIFACT_DIR||'/workspace/solar-review/v4119/relogin-browser';
await mkdir(artifacts,{recursive:true,mode:0o700});
const sql=query=>execFileSync('python',['/workspace/solar-review/v359/db.py',database],{input:query,encoding:'utf8'}).trim();
const makeClient=key=>createClient(endpoints.bridge,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const handler=createLoginHandler({makeAdmin:()=>makeClient(keys.service),makeAuth:()=>makeClient(keys.anon)});
const checks={},requests=[];let injected='',browser,localServer,holdProfile=null,lastPage;
const display='مستخدم اختبار الدخول',otherDisplay='مستخدم اختبار آخر';
const tokenKey='sb-afxxaafsuscwyjzrnagc-auth-token';
const suffix=randomBytes(5).toString('hex');
const password='  Ab!9-'+randomUUID()+'  ',otherPassword='B!9'+randomUUID();
const legacy={id:randomUUID(),username:'Older_Account_'+suffix,email:'historic-'+suffix+'@example.test',password,display};
const modern={id:randomUUID(),username:'staff_'+suffix,email:'staff_'+suffix+'@solar-user.local',password:otherPassword,display:otherDisplay};
let initialHash;
const actualHash=()=>sql(`select md5(encrypted_password) from auth.users where id='${legacy.id}'`);
const storageId=page=>page.evaluate(key=>JSON.parse(localStorage.getItem(key)||'null')?.user?.id||null,tokenKey);
const button=(page,label)=>page.getByRole('button',{name:label,exact:true});
const username=page=>page.getByLabel('اسم المستخدم أو البريد الإلكتروني',{exact:true});
const secret=page=>page.getByLabel('الباسورد',{exact:true});
async function createAccount(account){
 const {data,error}=await makeClient(keys.service).auth.admin.createUser({id:account.id,email:account.email,password:account.password,email_confirm:true});
 assert.ok(!error,'local GoTrue fixture creation failed ('+error?.status+' '+error?.code+' '+error?.message+')');
 assert.equal(data.user.id,account.id);
 sql(`insert into profiles(id,username,display_name,user_type,active,is_admin,permissions,phone)
  values('${account.id}','${account.username}','${account.display}','admin_staff',true,false,'{}','0770${String(Math.floor(Math.random()*10000000)).padStart(7,'0')}')
  on conflict(id) do update set username=excluded.username,display_name=excluded.display_name,permissions=excluded.permissions`);
}
async function bridge(){
 localServer=createServer(async(req,res)=>{
  try{
   const body=[];for await(const part of req)body.push(part);
   const raw=Buffer.concat(body),path=req.url;
   let response;
   if(path.startsWith('/functions/v1/solar-login')){
    response=await handler(new Request(endpoints.bridge+path,{method:req.method,headers:req.headers,body:raw,duplex:'half'}));
   }else{
    const dest=path.startsWith('/auth/v1/')?endpoints.auth+path.slice(8):path.startsWith('/rest/v1/')?endpoints.rest+path.slice(8):null;
    if(!dest){res.writeHead(404);res.end();return;}
    const headers=new Headers(req.headers);for(const key of['host','accept-encoding','content-length','connection'])headers.delete(key);
    response=await fetch(dest,{method:req.method,headers,...(raw.length?{body:raw}:{})});
   }
   const headers=new Headers(response.headers);for(const key of['content-length','content-encoding','transfer-encoding','connection'])headers.delete(key);
   res.writeHead(response.status,Object.fromEntries(headers));res.end(Buffer.from(await response.arrayBuffer()));
  }catch{res.writeHead(503);res.end();}
 });
 await new Promise((resolve,reject)=>{localServer.once('error',reject);localServer.listen(Number(new URL(endpoints.bridge).port),'127.0.0.1',resolve);});
}
async function open(){
 const context=await browser.newContext({viewport:{width:390,height:850},serviceWorkers:'block'});context.setDefaultTimeout(15000);
 await context.routeWebSocket(/supabase/,socket=>socket.close());
 await context.route('**/*',async route=>{
  const req=route.request(),u=new URL(req.url());
  if(u.hostname==='127.0.0.1'||['data:','blob:'].includes(u.protocol))return route.continue();
  if(u.hostname!=='afxxaafsuscwyjzrnagc.supabase.co')return route.abort();
  if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*','access-control-allow-methods':'GET,POST,PATCH,DELETE,OPTIONS'}});
  const isLogin=u.pathname==='/functions/v1/solar-login';
  if(isLogin){
   assert.ok(req.headers().apikey,'public login must send the publishable key');
   assert.ok(!req.headers().authorization,'password login must not send a previous user session');
   if(['network','rate','service'].includes(injected)){
    const failure=injected;injected='';
    if(failure==='network')return route.abort('internetdisconnected');
    const rate=failure==='rate';return route.fulfill({status:rate?429:503,json:{code:rate?'rate_limited':'unavailable'}});
   }
  }
  if(u.pathname==='/auth/v1/user'&&injected==='adopt'){
   injected='';return route.fulfill({status:403,json:{error_code:'bad_jwt',msg:'local session validation failed'}});
  }
  if(u.pathname==='/auth/v1/logout'){
   requests.push({method:'logout',scope:u.searchParams.get('scope')});
   if(injected==='logout'){return route.fulfill({status:503,json:{code:'unavailable'}});}
  }
  if(!/^\/(functions\/v1\/solar-login|auth\/v1\/|rest\/v1\/)/.test(u.pathname))return route.fulfill({status:200,json:{}});
  const headers={...req.headers(),apikey:keys.anon};delete headers.host;delete headers.origin;
  if(headers.authorization&&!/^Bearer eyJ/.test(headers.authorization))headers.authorization='Bearer '+keys.anon;
  const response=await context.request.fetch(endpoints.bridge+u.pathname+u.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});
  if(isLogin)requests.push({method:'login',status:response.status()});
  if(u.pathname==='/auth/v1/user'||u.pathname==='/rest/v1/profiles')requests.push({path:u.pathname,status:response.status(),...(response.status()>=400?{code:(await response.json().catch(()=>({})))?.code}:{} )});
  if(holdProfile&&holdProfile.match(u)){
   const pending=holdProfile;holdProfile=null;pending.started();await pending.delay;
  }
  await route.fulfill({response});
 });
 const page=await context.newPage();
 await page.goto(endpoints.app);await username(page).waitFor();return {context,page};
}
async function submit(page,identifier,value,autofill=false){
 if(autofill){
  await page.evaluate(({name,password})=>{
   document.querySelector('input[autocomplete="username"]').value=name;
   document.querySelector('input[autocomplete="current-password"]').value=password;
  },{name:identifier,password:value});
 }else{await username(page).fill(identifier);await secret(page).fill(value);}
 await button(page,'دخول').click();
}
async function signedIn(page,account){
 lastPage=page;
 await page.locator('.smoothFrame').waitFor();
 assert.equal(await storageId(page),account.id);
}
async function menu(page){if(!await page.getByRole('dialog',{name:'حسابي',exact:true}).isVisible())await button(page,'فتح قائمة حسابي').click();}
async function signout(page,confirm=true){
 await menu(page);await button(page,'تسجيل خروج').click();
 await button(page,confirm?'نعم، تسجيل الخروج':'لا، أبقى بالحساب').click();
}
async function loginError(page,identifier,value,pattern){
 await submit(page,identifier,value);
 const message=page.locator('.loginError');await message.filter({hasText:pattern}).waitFor();
 assert.equal(await storageId(page),null);
 return message.textContent();
}
async function assertFreshRoles(page){
 await page.goto(endpoints.app+'/?section=deletionRequests');
 await page.locator('.deletionRequests').waitFor();
}
try{
 await bridge();
 await createAccount(legacy);await createAccount(modern);
 initialHash=actualHash();
 const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
 browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
 const first=await open(),other=await open(),page=first.page;
 await page.getByRole('checkbox',{name:'إظهار كلمة المرور'}).check();
 for(const field of[username(page),secret(page)]){
  assert.equal(await field.getAttribute('autocorrect'),'off');
  assert.equal(await field.getAttribute('autocapitalize'),'none');
  assert.equal(await field.getAttribute('spellcheck'),'false');
 }
 await page.getByRole('checkbox',{name:'إظهار كلمة المرور'}).uncheck();
 const wrong='Different-'+randomUUID();
 const bad=await loginError(page,legacy.username,wrong,/غير صحيحة/);
 assert.equal(await loginError(page,'missing_'+suffix,wrong,/غير صحيحة/),bad);
 injected='network';await loginError(page,legacy.username,password,/تعذر الاتصال/);
 injected='rate';await loginError(page,legacy.username,password,/محاولات الدخول كثيرة/);
 injected='service';await loginError(page,legacy.username,password,/غير متاحة/);
 injected='adopt';await loginError(page,legacy.username,password,/فتح الجلسة/);
 sql(`update profiles set active=false where id='${modern.id}'`);
 assert.equal(await loginError(page,modern.email,otherPassword,/غير صحيحة/),bad);
 sql(`update profiles set active=true where id='${modern.id}'`);
 checks.inactiveEmailAndInvalidSessionAdoption=true;
 checks.errorMessages={wrongOrUnknownIndistinguishable:true,offline:true,rate:true,upstreamUnavailable:true};
 const lockTab=await first.context.newPage();
 try{
  await lockTab.goto(endpoints.app+'/manifest.webmanifest');
  await lockTab.evaluate(key=>new Promise(ready=>{
   void navigator.locks.request('lock:'+key,()=>new Promise(release=>{window.releaseLoginFixture=release;ready();}));
  }),tokenKey);
  await submit(page,legacy.username,password);
  await page.locator('.loginError').filter({hasText:'أغلق أي تبويب آخر'}).waitFor({timeout:35000});
  assert.equal(await storageId(page),null);
  await lockTab.evaluate(()=>window.releaseLoginFixture());
  // Acquire the same lock again, behind any work that might still be queued.
  await lockTab.evaluate(key=>navigator.locks.request('lock:'+key,()=>{}),tokenKey);
  assert.equal(await storageId(page),null,'abandoned login must never install a late session');
 }finally{await lockTab.close();}
 checks.lockContentionAllowsRetryWithoutLateAdoption=true;
 await submit(page,'  '+legacy.username.toUpperCase()+'  ',password,true);await signedIn(page,legacy);
 assert.equal(actualHash(),initialHash);
 await submit(other.page,legacy.email.toUpperCase(),password);await signedIn(other.page,legacy);
 checks.legacyIdentityAndAutofill=true;
 await signout(page,false);await signedIn(page,legacy);
 const before=Number(sql(`select count(*) from auth.sessions where user_id='${legacy.id}'`));
 await signout(page);await username(page).waitFor();
 assert.equal(await storageId(page),null);
 assert.equal(Number(sql(`select count(*) from auth.sessions where user_id='${legacy.id}'`)),before-1);
 const secondaryRefresh=await other.page.evaluate(key=>JSON.parse(localStorage.getItem(key)).refresh_token,tokenKey);
 const verification=await fetch(endpoints.auth+'/token?grant_type=refresh_token',{method:'POST',headers:{'content-type':'application/json',apikey:keys.anon},body:JSON.stringify({refresh_token:secondaryRefresh})});
 assert.equal(verification.status,200,'second device session must remain usable');await verification.body?.cancel();
 assert.ok(requests.some(row=>row.method==='logout'&&row.scope==='local'));
 await page.reload();await username(page).waitFor();
 checks.logoutCancelledOrLocalOnly=true;
 sql(`update profiles set permissions='{"deletionRequests":true}' where id='${legacy.id}'`);
 await submit(page,legacy.username.toLowerCase(),password);await signedIn(page,legacy);await assertFreshRoles(page);
 assert.equal(actualHash(),initialHash);
 checks.samePasswordReloginAndRefreshedPermissions=true;
 let captured,release;
 const reading=new Promise(resolve=>{captured=resolve;});
 holdProfile={started:captured,delay:new Promise(resolve=>{release=resolve;}),
  match:url=>url.pathname==='/rest/v1/profiles'&&url.searchParams.get('id')==='eq.'+legacy.id};
 await page.evaluate(()=>window.dispatchEvent(new Event('solar-profile-changed')));
 await Promise.race([reading,new Promise((_,reject)=>{const timer=setTimeout(()=>reject(new Error('latest profile refresh did not start')),5000);timer.unref();})]);
 await signout(page);await username(page).waitFor();
 await submit(page,modern.username.toUpperCase(),otherPassword);await signedIn(page,modern);
 const oldReply=page.waitForResponse(r=>new URL(r.url()).pathname==='/rest/v1/profiles'&&new URL(r.url()).searchParams.get('id')==='eq.'+legacy.id);
 release();await oldReply;
 await page.getByText(otherDisplay,{exact:false}).first().waitFor();
 assert.equal(await storageId(page),modern.id);
 checks.delayedOldProfileCannotRestorePreviousRole=true;
 assert.equal(await page.locator('.deletionRequests').count(),0);
 injected='logout';await signout(page);await page.getByText(/تعذر تأكيد تسجيل الخروج/).first().waitFor();
 assert.equal(await page.locator('.smoothFrame').count(),0);
 injected='';await button(page,'إعادة المحاولة').click();await username(page).waitFor();
 await page.reload();await username(page).waitFor();
 assert.equal(await storageId(page),null);
 await submit(page,modern.email.toUpperCase(),otherPassword);await signedIn(page,modern);
 checks.failedLogoutIsBlockedUntilRetryAndSamePasswordWorks=true;
 assert.equal(actualHash(),initialHash);
 await writeFile(artifacts+'/results.json',JSON.stringify({pass:true,checks,requests},null,2));
 console.log('PASS isolated Chromium, login Edge, GoTrue and PostgreSQL');
}catch(error){
 if(lastPage)await lastPage.screenshot({path:artifacts+'/screen.png'}).catch(()=>{});
 await writeFile(artifacts+'/failure.json',JSON.stringify({checks,requests,error:String(error).replaceAll(password,'[redacted]').replaceAll(otherPassword,'[redacted]')},null,2));
 throw error;
}finally{
 for(const context of browser?.contexts()||[])await context.unrouteAll({behavior:'ignoreErrors'});
 await browser?.close();
 if(localServer)await new Promise(resolve=>localServer.close(resolve));
}
