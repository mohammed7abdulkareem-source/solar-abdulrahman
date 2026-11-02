// Compiled app → isolated PostgREST → local PostgreSQL. Never contacts live data.
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
import {sections} from '../app/section-directory.mjs';
import {canOpenPage} from '../app/access-utils.mjs';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const db=process.env.SOLAR_FIXTURE_DB||'solar_v394_browser',base=process.env.SOLAR_APP_URL||'http://127.0.0.1:3090',api=process.env.SOLAR_FIXTURE_API||'http://127.0.0.1:3089';
assert.match(db,/^solar_[a-z0-9_]+_browser$/);
for(const url of[base,api])assert.equal(new URL(url).hostname,'127.0.0.1');
const dir=process.env.SOLAR_ARTIFACT_DIR||'/workspace/solar-review/v394/workspace-browser';await mkdir(dir,{recursive:true});
const sql=q=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:q,encoding:'utf8'}).trim();
const hash=()=>sql("select md5(jsonb_build_object('transactions',(select jsonb_agg(to_jsonb(t) order by id) from transactions t),'items',(select jsonb_agg(to_jsonb(t) order by id) from transaction_items t),'cash',(select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from cash_ledger t),'entries',(select jsonb_agg(to_jsonb(t) order by id) from solar_cash_entries t),'stock',(select jsonb_agg(to_jsonb(t) order by warehouse_id,product_id) from solar_private.warehouse_stocks t))::text)");
const ids={admin:'00000000-0000-0000-0000-000000003920',full:'00000000-0000-0000-0000-000000003911',limited:'00000000-0000-0000-0000-000000003912',warehouse:'00000000-0000-0000-0000-000000003914',installer:'00000000-0000-0000-0000-000000003915'};
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),contexts=[],calls=[],errors=[],checks={};let currentPage;
const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
async function open(who,path='/',options={}){
 const uid=ids[who],raw=enc({alg:'HS256',typ:'JWT'})+'.'+enc({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600}),token=raw+'.'+createHmac('sha256','solar-local-test-only-signing-secret-347').update(raw).digest('base64url');
 const session={access_token:token,refresh_token:'local-test',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}};
 const ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true});contexts.push(ctx);ctx.setDefaultTimeout(20000);
 await ctx.addInitScript(session=>{window.__testSession=session;localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify(session));},session);
 await ctx.routeWebSocket(/supabase/,socket=>socket.close());
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),u=new URL(req.url());
  if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
  if(u.pathname==='/auth/v1/user')return route.fulfill({json:session.user});
  if(!u.pathname.startsWith('/rest/v1/'))return route.abort();
  const call={who,path:u.pathname,method:req.method(),payload:req.postData()?JSON.parse(req.postData()):null};calls.push(call);
  if(options.delay&&u.pathname==='/rest/v1/rpc/solar_inventory')await new Promise(r=>setTimeout(r,options.delay));
  if(options.failNotices&&u.pathname==='/rest/v1/solar_notifications')return route.fulfill({status:503,json:{message:'isolated unavailable'}});
  const headers={...req.headers(),authorization:'Bearer '+token};delete headers.apikey;delete headers.host;delete headers.origin;
  const response=await ctx.request.fetch(api+u.pathname.replace('/rest/v1','')+u.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});call.status=response.status();
  return route.fulfill({response});
 });
 await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const p=await ctx.newPage();currentPage=p;p.on('pageerror',e=>errors.push({who,error:String(e)}));p.on('console',e=>{if(e.type()==='error'&&/TypeError|ReferenceError|Minified React/.test(e.text()))errors.push({who,error:e.text()});});p.on('dialog',d=>d.dismiss());await p.goto(base+path);await p.locator('.smoothFrame').waitFor();
 return {p,ctx,options};
}
async function navigate(p,id){
 await p.getByRole('button',{name:'الأقسام',exact:true}).click();const dialog=p.getByRole('dialog',{name:'جميع الأقسام',exact:true});
 await dialog.getByLabel('البحث عن قسم',{exact:true}).fill(sections.flatMap(([,rows])=>rows).find(([key])=>key===id)[1]);
 await dialog.locator('a[href="/?section='+id+'"]').click();await p.waitForURL(u=>u.searchParams.get('section')===id);
}
async function home(p){await p.locator('.premiumMobileBrand').click();await p.waitForURL(u=>!u.searchParams.has('section'));await p.locator('.premiumDashboard').waitFor();}
async function refreshAuth(p){await p.evaluate(()=>{const ch=new BroadcastChannel('sb-afxxaafsuscwyjzrnagc-auth-token');ch.postMessage({event:'TOKEN_REFRESHED',session:window.__testSession});setTimeout(()=>ch.close(),100);});await p.waitForTimeout(350);}
async function shot(p,name){await p.screenshot({path:dir+'/'+name+'.png',fullPage:true,animations:'disabled'});assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Horizontal overflow: '+name);}
try{
 const before=hash(),{p,ctx}=await open('admin');
 await p.locator('.workspaceHomeTabs').waitFor();
 const layoutReads=()=>calls.filter(c=>c.who==='admin'&&c.path.endsWith('/solar_section_layout')&&c.payload?.action==='get').length;
 for(let i=0;i<50&&layoutReads()===0;i++)await p.waitForTimeout(50);
 assert.equal(layoutReads(),1,'Home fetched layout twice');
 for(const width of[360,390,430,768,1440]){
  await p.setViewportSize({width,height:920});await shot(p,'home-'+width);
  const sizes=await p.locator('.premiumTopTools button:visible,.appMobileBar :is(a,button):visible,.workspaceHomeTabs button:visible').evaluateAll(nodes=>nodes.map(n=>({label:n.getAttribute('aria-label')||n.innerText,w:n.getBoundingClientRect().width,h:n.getBoundingClientRect().height})));
  assert.deepEqual(sizes.filter(x=>x.w<43.5||x.h<43.5),[],'Small touch targets');
 }
 checks.responsive=[360,390,430,768,1440];
 await p.setViewportSize({width:390,height:920});
 await p.getByRole('button',{name:'فتح قائمة حسابي',exact:true}).click();const account=p.getByRole('dialog',{name:'حسابي',exact:true});
 for(const label of['تعديل رقم هاتفي','تحديث البرنامج','تسجيل خروج'])await account.getByRole('button',{name:label,exact:true}).waitFor();
 await account.getByRole('button',{name:'اختيار تصميم البرنامج',exact:true}).click();await shot(p,'account-design');
 await p.keyboard.press('Escape');assert.equal(await account.isVisible(),false);assert.equal(await p.getByRole('button',{name:'فتح قائمة حسابي',exact:true}).evaluate(n=>n===document.activeElement),true);checks.accountMenu=true;
 await p.keyboard.press('Control+k');await p.getByRole('dialog',{name:'البحث السريع',exact:true}).waitFor();await p.getByLabel('البحث العام',{exact:true}).fill('التحصيل');await p.getByRole('region',{name:'نتائج الأقسام',exact:true}).getByRole('button',{name:'التحصيل',exact:true}).click();
 await p.getByRole('region',{name:'حاسبة التحصيل وعروض المنظومات',exact:true}).waitFor();assert.ok(p.url().includes('section=tahseel'));checks.globalSearch=true;
 await p.getByRole('button',{name:'الرجوع إلى الشاشة السابقة',exact:true}).click();await p.locator('.premiumDashboard').waitFor();await p.evaluate(()=>history.forward());await p.getByRole('region',{name:'حاسبة التحصيل وعروض المنظومات',exact:true}).waitFor();checks.backForward=true;
 await p.getByLabel('اسم زبون العرض',{exact:true}).fill('عرض غير محفوظ لفحص التنقل');
 await p.getByRole('tab',{name:'الملاحظات',exact:true}).click();await p.getByLabel('ملاحظات العرض',{exact:true}).fill('احتفظ بهذه الملاحظة عند إلغاء الخروج');
 await p.getByRole('button',{name:'الأقسام',exact:true}).click();await p.getByRole('dialog',{name:'جميع الأقسام',exact:true}).getByLabel('البحث عن قسم',{exact:true}).fill('المبيعات السابقة');
 await p.getByRole('dialog',{name:'جميع الأقسام',exact:true}).getByRole('link',{name:'المبيعات السابقة',exact:true}).click();
 assert.ok(p.url().includes('section=tahseel'));assert.equal(await p.getByRole('dialog',{name:'جميع الأقسام',exact:true}).isVisible(),true);await p.keyboard.press('Escape');
 assert.equal(await p.getByLabel('ملاحظات العرض',{exact:true}).inputValue(),'احتفظ بهذه الملاحظة عند إلغاء الخروج');
 await p.evaluate(()=>history.back());await p.waitForTimeout(350);assert.ok(p.url().includes('section=tahseel'));assert.equal(await p.getByLabel('ملاحظات العرض',{exact:true}).inputValue(),'احتفظ بهذه الملاحظة عند إلغاء الخروج');checks.cancelPreservesFormAndURL=true;
 // Cancelled navigation through the global search also keeps its results open.
 await p.keyboard.press('Control+k');await p.getByLabel('البحث العام',{exact:true}).fill('المبيعات');await p.getByRole('region',{name:'نتائج الأقسام',exact:true}).getByRole('button',{name:'المبيعات السابقة',exact:true}).click();
 assert.equal(await p.getByRole('dialog',{name:'البحث السريع',exact:true}).isVisible(),true);await p.keyboard.press('Escape');
 p.removeAllListeners('dialog');p.on('dialog',d=>d.accept());await home(p);checks.confirmedNavigation=true;
 await navigate(p,'cash');await p.locator('.cashFinanceV2').waitFor();await shot(p,'cash-mobile');
 const cashUrl=p.url();await p.getByRole('button',{name:'جميع عمليات الصندوق',exact:true}).click();await p.waitForURL(u=>u.href!==cashUrl);await p.evaluate(()=>history.back());await p.waitForURL(cashUrl);await p.locator('.cashFinanceV2').waitFor();checks.cashNestedHistory=true;
 await home(p);await p.evaluate(()=>history.back());await p.waitForURL(u=>u.searchParams.get('section')==='cash');await p.locator('.cashFinanceV2').waitFor();
 for(const id of['sale','system','salesHistory','customerStatement','supplierPayment','stockMovement','installations','profit','capital']){await navigate(p,id);await p.waitForTimeout(250);await p.getByText('جاري فتح القسم…',{exact:true}).waitFor({state:'hidden'});await p.locator('.workspaceLoading').waitFor({state:'hidden'});assert.equal(await p.locator('.workspaceFailure').count(),0);await shot(p,'section-'+id);}
 checks.sectionSmoke=true;
 await ctx.setOffline(true);await p.getByRole('status').filter({hasText:'غير متصل'}).waitFor();await ctx.setOffline(false);await p.locator('.workspaceOffline').waitFor({state:'hidden'});checks.offlineState=true;
 // Reloaded URL and auth refresh must retain the section the user chose.
 await p.reload();await p.locator('.smoothFrame').waitFor();await p.waitForTimeout(300);assert.ok(p.url().includes('section=capital'));assert.equal(await p.locator('.premiumDashboard').count(),0);await home(p);await refreshAuth(p);assert.equal(new URL(p.url()).searchParams.get('section'),null);await p.locator('.premiumDashboard').waitFor();checks.authRefreshStaysInPlace=true;
 for(const who of['limited','warehouse','installer']){
  const {p:r}=await open(who,who==='warehouse'?'/?section=warehouse':'/');
  if(who==='warehouse'){await navigate(r,'stock');await refreshAuth(r);assert.ok(r.url().includes('section=stock'));}
  await r.getByRole('button',{name:'الأقسام',exact:true}).click();const menu=r.getByRole('dialog',{name:'جميع الأقسام',exact:true});
  const tabs=menu.locator('.workspaceCategoryTabs button'),found=new Set();
  for(let i=0;i<await tabs.count();i++){await tabs.nth(i).click();for(const href of await menu.locator('.workspaceSectionLinks a').evaluateAll(a=>a.map(x=>x.getAttribute('href'))))found.add(href.split('=')[1]);}
  const profile=JSON.parse(sql("select to_json(p) from profiles p where id='"+ids[who]+"'"));
  assert.deepEqual([...found].sort(),sections.flatMap(([,rows])=>rows).filter(([id])=>id!=='home'&&canOpenPage(profile,id)).map(([id])=>id).sort());
  await shot(r,who+'-permissions');await r.keyboard.press('Escape');
 }
 checks.permissionBoundedSections=true;
 // Each existing theme remains selectable and shares the same navigation.
 await home(p);
 for(const [mode,label]of[['columns','تصميم الأعمدة'],['premium','تصميم بريميوم'],['desk','تصميم المكتب'],['solar','أفق سولار'],['groups','التصميم المجمّع']]){
  await p.getByRole('button',{name:'فتح قائمة حسابي',exact:true}).click();const a=p.getByRole('dialog',{name:'حسابي',exact:true});
  const pick=a.getByRole('button',{name:'اختيار تصميم البرنامج',exact:true});if(await pick.getAttribute('aria-expanded')!=='true')await pick.click();
  await a.getByRole('button',{name:new RegExp('^'+label)}).click();await a.locator('.sectionDesignPopover').waitFor({state:'hidden'});await p.keyboard.press('Escape');
  await shot(p,'theme-'+mode);await p.setViewportSize({width:1440,height:920});await shot(p,'theme-desktop-'+mode);await p.setViewportSize({width:390,height:920});
 }
 checks.allFiveThemes=true;
 const flags={delay:4000,failNotices:true},{p:slow}=await open('full','/?section=system',flags);
 await slow.locator('.workspaceLoading').waitFor();await slow.getByRole('button',{name:'الأقسام',exact:true}).click();await slow.getByRole('dialog',{name:'جميع الأقسام',exact:true}).waitFor();await slow.keyboard.press('Escape');checks.navigationDuringLoad=true;
 await slow.getByRole('button',{name:'فتح الإشعارات',exact:true}).click();await slow.getByRole('alert').filter({hasText:'تعذر تحميل الإشعارات'}).waitFor();
 await slow.waitForFunction(()=>document.querySelector('.notificationList')?.getAttribute('aria-busy')==='false');
 flags.failNotices=false;await slow.evaluate(()=>document.querySelector('.notificationList [role=alert] button')?.click());await slow.getByRole('alert').filter({hasText:'تعذر تحميل الإشعارات'}).waitFor({state:'hidden'});await slow.keyboard.press('Escape');checks.notificationRecovery=true;
 assert.equal(hash(),before,'Read-only navigation changed accounting data');assert.deepEqual(errors,[]);
 await writeFile(dir+'/results.json',JSON.stringify({pass:true,checks,financialStateUnchanged:true,calls,errors},null,2));console.log('PASS workspace UX',JSON.stringify(checks));
}catch(error){if(currentPage)await currentPage.screenshot({path:dir+'/failure.png',fullPage:true}).catch(()=>{});await writeFile(dir+'/failure.json',JSON.stringify({error:String(error),stack:error.stack,calls,errors,checks},null,2));throw error;}finally{for(const c of contexts)await c.unrouteAll({behavior:'ignoreErrors'});await browser.close();}
