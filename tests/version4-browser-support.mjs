// Shared isolated browser plumbing. Every financial request is redirected to
// loopback PostgREST; external requests are denied, including production writes.
process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
import assert from 'node:assert/strict';
import {createHmac,createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
export const db=process.env.SOLAR_FIXTURE_DB||'solar_v4_browser',base=process.env.SOLAR_APP_URL||'http://127.0.0.1:3140',api=process.env.SOLAR_FIXTURE_API||'http://127.0.0.1:3141';
assert.match(db,/^solar_[a-z0-9_]+_browser$/);for(const url of[base,api])assert.equal(new URL(url).hostname,'127.0.0.1');
export const ids={admin:'00000000-0000-0000-0000-000000400101',owner:'00000000-0000-0000-0000-000000400102',foreign:'00000000-0000-0000-0000-000000400103',warehouse:'00000000-0000-0000-0000-000000400104',installer:'00000000-0000-0000-0000-000000400105',manager:'00000000-0000-0000-0000-000000400106'};
export const sql=query=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:query,encoding:'utf8'}).trim();
export const fingerprint=()=>sql("select md5(jsonb_build_array((select jsonb_agg(to_jsonb(t)order by id)from transactions t),(select jsonb_agg(to_jsonb(t)order by id)from transaction_items t),(select jsonb_agg(to_jsonb(t)order by id)from products t),(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),(select jsonb_agg(to_jsonb(t)order by id)from solar_private.wallet_fx_entries t),(select jsonb_agg(to_jsonb(t)order by id)from solar_private.supplier_fx_entries t),(select jsonb_agg(to_jsonb(t)order by id)from solar_cash_entries t),(select jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text)from cash_ledger t),(select jsonb_agg(to_jsonb(t)order by invoice_id)from solar_private.deleted_sales t))::text)");
export const scalar=query=>Number(sql(query)),cash=owner=>scalar("select solar_private.cash_balance('"+owner+"')"),amount=text=>Number(text.replace(/[^\d.-]/g,''));
const encode=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
export const tokenFor=uid=>{const raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600});return raw+'.'+createHmac('sha256','solar-local-test-only-signing-secret-347').update(raw).digest('base64url');};
export async function rpc(who,name,payload,expectedStatus=200){const response=await fetch(api+'/rpc/'+name,{method:'POST',headers:{authorization:'Bearer '+tokenFor(ids[who]||who),'content-type':'application/json'},body:JSON.stringify(payload)});const text=await response.text(),data=text?JSON.parse(text):null;assert.equal(response.status,expectedStatus,name+': '+text);return data;}
export async function createHarness(name){
 const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core'),dir=process.env.SOLAR_ARTIFACT_DIR||'/workspace/solar-review/v4/'+name;await mkdir(dir,{recursive:true});
 const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),contexts=[],calls=[],errors=[],checks={};let currentPage,intercept=null;
 async function open(who,path='/?'){
  const uid=ids[who]||who,token=tokenFor(uid),session={access_token:token,refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}};
  const ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true,acceptDownloads:true});contexts.push(ctx);ctx.setDefaultTimeout(25000);
  await ctx.addInitScript(s=>{localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify(s));window.__documentHtmls=[];window.__shares=[];window.__printCalls=0;window.print=()=>window.__printCalls++;Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>true});Object.defineProperty(navigator,'share',{configurable:true,value:async data=>{const f=data.files[0],hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await f.arrayBuffer()))).map(n=>n.toString(16).padStart(2,'0')).join('');window.__shares.push({name:f.name,type:f.type,size:f.size,hash,active:navigator.userActivation.isActive});}});const descriptor=Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype,'srcdoc');Object.defineProperty(HTMLIFrameElement.prototype,'srcdoc',{...descriptor,set(html){window.__documentHtmls.push(html);return descriptor.set.call(this,html);}});},session);
  await ctx.routeWebSocket(/supabase/,socket=>socket.close());
  await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
   const req=route.request(),url=new URL(req.url());if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});if(url.pathname==='/auth/v1/user')return route.fulfill({json:session.user});
   if(url.pathname==='/functions/v1/solar-admin-users'&&uid===ids.admin)return route.fulfill({json:{ok:true,users:JSON.parse(sql('select jsonb_agg(to_jsonb(p)order by id)from(select id,display_name,username,honorific,phone,permissions,is_admin,user_type,active from profiles)p'))}});
   if(!url.pathname.startsWith('/rest/v1/'))return route.abort();
   const call={who,path:url.pathname,method:req.method(),body:req.postData()?JSON.parse(req.postData()):null};calls.push(call);const headers={...req.headers(),authorization:'Bearer '+token};delete headers.apikey;delete headers.host;delete headers.origin;
   const response=await ctx.request.fetch(api+url.pathname.replace('/rest/v1','')+url.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});call.status=response.status();
   if(intercept&&await intercept({route,call,response}))return;
   if(response.status()>=400)errors.push({who,path:url.pathname,status:response.status(),body:await response.text()});return route.fulfill({response});
  });
  await ctx.route('**/*',route=>{const url=new URL(route.request().url());if(url.hostname==='127.0.0.1'||['data:','blob:'].includes(url.protocol))return route.continue();if(url.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
  const page=await ctx.newPage();currentPage=page;page.on('pageerror',error=>errors.push(String(error)));page.on('dialog',dialog=>dialog.accept());await page.goto(base+path);await page.locator('.smoothFrame').waitFor();return{page,ctx,token};
 }
 async function layout(page,label,region){currentPage=page;for(const width of[360,390,1366]){await page.setViewportSize({width,height:920});if(region)await region.scrollIntoViewIfNeeded();assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),label+' horizontal overflow at '+width);await page.screenshot({path:dir+'/'+label+'-'+width+'.png',animations:'disabled'});}await page.setViewportSize({width:390,height:920});checks[label+'Responsive']=[360,390,1366];}
 async function report(page,ctx,actions,label){
  await actions.locator('.reportButton.download:not([disabled])').waitFor({timeout:180000});
  const [preview]=await Promise.all([ctx.waitForEvent('page'),actions.getByRole('button',{name:'معاينة',exact:true}).click()]);await preview.locator('.pdfPage img').first().waitFor({timeout:30000});const pages=await preview.locator('.pdfPage').count();assert.ok(pages>0);await preview.screenshot({path:dir+'/'+label+'-preview.png'});await preview.close();
  const [download]=await Promise.all([page.waitForEvent('download'),actions.getByRole('button',{name:'حفظ PDF',exact:true}).click()]);await download.saveAs(dir+'/'+label+'.pdf');const bytes=await readFile(dir+'/'+label+'.pdf');assert.equal(bytes.subarray(0,5).toString(),'%PDF-');
  const count=await page.evaluate(()=>window.__shares.length);await actions.getByRole('button',{name:'مشاركة',exact:true}).click();await page.waitForFunction(n=>window.__shares.length>n,count);const shared=await page.evaluate(()=>window.__shares.at(-1));assert.equal(shared.hash,createHash('sha256').update(bytes).digest('hex'));assert.equal(shared.active,true);checks[label+'PDF']={pages,bytes:bytes.length,sameSharedFile:true};return page.evaluate(()=>window.__documentHtmls.at(-1));
 }
 async function finish(){assert.deepEqual(errors,[]);await writeFile(dir+'/results.json',JSON.stringify({pass:true,checks,calls,errors},null,2));}
 async function fail(error){await currentPage?.screenshot({path:dir+'/failure.png',timeout:5000}).catch(()=>{});await writeFile(dir+'/failure.json',JSON.stringify({error:String(error),stack:error.stack,checks,calls,errors},null,2));}
 async function close(){for(const ctx of contexts)await ctx.unrouteAll({behavior:'ignoreErrors'}).catch(()=>{});await browser.close();}
 return{open,layout,report,finish,fail,close,calls,errors,checks,dir,setCurrent:page=>currentPage=page,setIntercept:fn=>intercept=fn};
}
