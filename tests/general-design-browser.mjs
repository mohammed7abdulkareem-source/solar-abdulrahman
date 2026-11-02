// Compiled app → isolated PostgREST → local PostgreSQL. Never contacts live data.
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
import {sections} from '../app/section-directory.mjs';
import {canOpenPage} from '../app/access-utils.mjs';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const db=process.env.SOLAR_FIXTURE_DB||'solar_v395_browser',base=process.env.SOLAR_APP_URL||'http://127.0.0.1:3094',api=process.env.SOLAR_FIXTURE_API||'http://127.0.0.1:3093';
assert.match(db,/^solar_[a-z0-9_]+_browser$/);
for(const url of[base,api])assert.equal(new URL(url).hostname,'127.0.0.1');
const dir=process.env.SOLAR_ARTIFACT_DIR||'/workspace/solar-review/v395/general-browser';await mkdir(dir,{recursive:true});
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
  if(u.pathname==='/functions/v1/solar-admin-users'&&who==='admin'){const users=JSON.parse(sql("select jsonb_agg(to_jsonb(p) order by id) from(select id,display_name,username,honorific,phone,permissions,is_admin,user_type,active from profiles)p"));return route.fulfill({json:{ok:true,users}});}
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
 return {p,ctx,options,token};
}
async function navigate(p,id){
 await p.getByRole('button',{name:'الأقسام',exact:true}).click();const dialog=p.getByRole('dialog',{name:'جميع الأقسام',exact:true});
 await dialog.getByLabel('البحث عن قسم',{exact:true}).fill(sections.flatMap(([,rows])=>rows).find(([key])=>key===id)[1]);
 await dialog.locator('a[href="/?section='+id+'"]').click();await p.waitForURL(u=>u.searchParams.get('section')===id);
}
async function home(p){await p.locator('.premiumMobileBrand').click();await p.waitForURL(u=>!u.searchParams.has('section'));await p.locator('.premiumDashboard').waitFor();}
async function refreshAuth(p){await p.evaluate(()=>{const ch=new BroadcastChannel('sb-afxxaafsuscwyjzrnagc-auth-token');ch.postMessage({event:'TOKEN_REFRESHED',session:window.__testSession});setTimeout(()=>ch.close(),100);});await p.waitForTimeout(350);}
async function shot(p,name){await p.screenshot({path:dir+'/'+name+'.png',fullPage:true,animations:'disabled'});assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Horizontal overflow: '+name);}
async function chooseGeneral(p){
 await p.getByRole('button',{name:'فتح قائمة حسابي',exact:true}).click();const a=p.getByRole('dialog',{name:'حسابي',exact:true});
 const pick=a.getByRole('button',{name:'اختيار تصميم البرنامج',exact:true});if(await pick.getAttribute('aria-expanded')!=='true')await pick.click();
 await a.getByRole('button',{name:/^التصميم العام/}).click();await a.locator('.sectionDesignPopover').waitFor({state:'hidden'});await p.keyboard.press('Escape');await p.locator('.generalDesignTheme').waitFor();
}
const expectedFor=profile=>sections.flatMap(([,rows])=>rows).filter(([id])=>id!=='home'&&canOpenPage(profile,id)).map(([id])=>id).sort();
async function checkDirectory(p,profile,root='.generalDashboard'){
 const cards=p.locator(root+' .generalSectionCard'),rows=await cards.evaluateAll(nodes=>nodes.map(n=>({id:new URL(n.href).searchParams.get('section'),w:n.getBoundingClientRect().width,h:n.getBoundingClientRect().height,text:n.innerText,labelFits:n.querySelector('b').scrollHeight<=n.querySelector('b').clientHeight+1})));
 assert.deepEqual(rows.map(x=>x.id).sort(),expectedFor(profile));assert.equal(new Set(rows.map(x=>x.id)).size,rows.length);assert.ok(rows.every(x=>x.w>=100&&x.h>=44&&x.text&&x.labelFits),'Cards are hidden, clipped, duplicated or too small');
}
try{
 const before=hash(),admin=await open('admin'),{p,ctx,token}=admin,profile=JSON.parse(sql("select to_json(p)from profiles p where id='"+ids.admin+"'"));
 await chooseGeneral(p);await checkDirectory(p,profile);assert.equal(await p.locator('.generalSectionGroup').count(),6);
 for(const width of[320,360,390,430,768,1024,1366,1600]){
  await p.setViewportSize({width,height:920});await shot(p,'general-home-'+width);await checkDirectory(p,profile);
  const columns=await p.locator('.generalSectionGrid').first().evaluate(n=>getComputedStyle(n).gridTemplateColumns.split(' ').length);assert.equal(columns,width<=700?2:width<=1000?3:width<1250?4:5);
 }
 checks.allSectionsAlwaysVisible=true;checks.responsive=[320,360,390,430,768,1024,1366,1600];
 await p.setViewportSize({width:390,height:920});await p.getByRole('navigation',{name:'الانتقال إلى مجموعة أقسام',exact:true}).getByRole('link',{name:'الإعدادات والنظام',exact:true}).click();await p.waitForTimeout(350);await checkDirectory(p,profile);assert.equal(new URL(p.url()).searchParams.get('section'),null);checks.categoryLinksOnlyScroll=true;
 await p.getByLabel('البحث في الأقسام',{exact:true}).fill('تسديد مورد');assert.equal(await p.locator('.generalDashboard .generalSectionCard').count(),1);await p.getByRole('button',{name:'مسح البحث في الأقسام',exact:true}).click();await checkDirectory(p,profile);checks.searchAcrossGroups=true;
 const state=await ctx.request.post(api+'/rpc/solar_section_layout',{headers:{authorization:'Bearer '+token},data:{action:'get'}});assert.equal(state.status(),200);assert.equal((await state.json()).mode,'general');
 await p.reload();await p.locator('.generalDesignTheme').waitFor();await checkDirectory(p,profile);const second=await open('admin');await second.p.locator('.generalDesignTheme').waitFor();await checkDirectory(second.p,profile);await second.ctx.unrouteAll({behavior:'ignoreErrors'});await second.ctx.close();checks.persistedAcrossSessions=true;
 await p.getByRole('button',{name:'الأقسام',exact:true}).click();const dialog=p.getByRole('dialog',{name:'جميع الأقسام',exact:true});await checkDirectory(p,profile,'.workspaceSectionsDialog');await shot(p,'all-sections-dialog');await p.keyboard.press('Escape');checks.dialogShowsAllSections=true;
 // Open every permitted section; the updater stays behind its existing password gate.
 const destinations=expectedFor(profile);
 for(const id of destinations){
  currentPage=p;await navigate(p,id);await p.waitForTimeout(200);await p.getByText('جاري فتح القسم…',{exact:true}).waitFor({state:'hidden'});await p.locator('.workspaceLoading').waitFor({state:'hidden'});
  if(id==='updates'){await p.getByRole('heading',{name:'تحديثات البرنامج محمية',exact:true}).waitFor();assert.equal(await p.locator('.updateBox').count(),0);}
  assert.equal(await p.locator('.workspaceFailure').count(),0,id+' render failed');assert.equal(await p.locator('.generalDesignTheme').count(),1);assert.equal(await p.evaluate(()=>document.body.dataset.workspaceDesign),'general');
  for(const width of[360,1366]){await p.setViewportSize({width,height:920});await p.evaluate(()=>scrollTo(0,0));await shot(p,'inside-'+id+'-'+width);}
 }
 checks.existingSections=destinations;
 await p.setViewportSize({width:390,height:920});await home(p);await p.locator('.generalDashboard').waitFor();
 // The opt-in design leaves every older design available.
 await p.getByRole('button',{name:'فتح قائمة حسابي',exact:true}).click();const a=p.getByRole('dialog',{name:'حسابي',exact:true});await a.getByRole('button',{name:'اختيار تصميم البرنامج',exact:true}).click();assert.equal(await a.locator('.sectionDesignSwitch button').count(),6);await a.getByRole('button',{name:/^التصميم المجمّع/}).click();await a.locator('.sectionDesignPopover').waitFor({state:'hidden'});await p.keyboard.press('Escape');await p.locator('.workspaceHomeDirectory').waitFor();assert.equal(await p.locator('.generalDesignTheme').count(),0);await chooseGeneral(p);checks.existingDesignsPreserved=true;
 for(const who of['limited','warehouse','installer']){
  const other=await open(who),r=other.p;currentPage=r;await chooseGeneral(r);const pr=JSON.parse(sql("select to_json(p)from profiles p where id='"+ids[who]+"'"));await checkDirectory(r,pr);await shot(r,who+'-scope');
  await r.reload();await r.locator('.generalDesignTheme').waitFor();await checkDirectory(r,pr);
  const otherState=await other.ctx.request.post(api+'/rpc/solar_section_layout',{headers:{authorization:'Bearer '+other.token},data:{action:'get',payload:{userId:ids.admin}}});assert.equal(otherState.status(),200);assert.equal((await otherState.json()).mode,'general');
 }
 checks.rolesAndOwnership=true;
 const denied=await ctx.request.post(api+'/rpc/solar_section_layout',{data:{action:'view',payload:{mode:'general',expectedRevision:0}}});assert.equal(denied.status(),401);checks.anonymousDenied=true;
 assert.equal(hash(),before,'Design changes touched accounting data');assert.deepEqual(errors,[]);
 await writeFile(dir+'/results.json',JSON.stringify({pass:true,checks,financialStateUnchanged:true,calls,errors},null,2));console.log('PASS general design',JSON.stringify(checks));
}catch(error){if(currentPage)await currentPage.screenshot({path:dir+'/failure.png',fullPage:true}).catch(()=>{});await writeFile(dir+'/failure.json',JSON.stringify({error:String(error),stack:error.stack,calls,errors,checks},null,2));throw error;}finally{for(const c of contexts)await c.unrouteAll({behavior:'ignoreErrors'}).catch(()=>{});await browser.close();}
