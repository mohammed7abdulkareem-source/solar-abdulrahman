// Uses the loopback Auth/Edge gateway, the historical honorary-title warranty fixture,
// and a real office administrator's local Auth session.
process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const base=process.env.SOLAR_APP_URL||'http://127.0.0.1:3101';
const gateway=process.env.SOLAR_WIZARD_GATEWAY||'http://127.0.0.1:3200';
const db=process.env.SOLAR_FIXTURE_DB||'solar_v4114_wizard_browser';
const dir=process.env.SOLAR_ARTIFACT_DIR||'/workspace/solar-review/v4114/honorific-browser';
for(const url of [base,gateway])assert.equal(new URL(url).hostname,'127.0.0.1');
assert.match(db,/^solar_[a-z0-9_]+_browser$/);
await mkdir(dir,{recursive:true});
const sql=query=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:query,encoding:'utf8'}).trim();
const admin=JSON.parse(await readFile(process.env.SOLAR_ADMIN_SESSION_FILE||'/workspace/solar-review/v4114/wizard-edge/admin-session.json','utf8'));
const ownerId='00000000-0000-0000-0000-000000003791';
const originalTitle=sql("select honorific from public.profiles where id='"+ownerId+"'");
const editedTitle=originalTitle==='الحاج'?'الإداري':'الحاج';
const invoice=JSON.parse(sql("select jsonb_build_object('id',id,'number',receipt_no,'token',warranty_token) from public.transactions where party_id=-379001 and warranty_token is not null"));
const hash=()=>sql("select md5(jsonb_build_array((select jsonb_agg(to_jsonb(t) order by id) from public.transactions t),(select jsonb_agg(to_jsonb(t) order by id) from public.transaction_items t),(select jsonb_agg(to_jsonb(e) order by id) from public.solar_cash_entries e))::text)");
const username='title_'+randomUUID().replaceAll('-','').slice(0,12),password=randomUUID();
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
const contexts=[],errors=[],actions=[];
async function open(path,session){
 const ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true});
 contexts.push(ctx);ctx.setDefaultTimeout(20000);
 await ctx.addInitScript(session=>{
  if(session)localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify(session));
  window.__documentHtmls=[];
  const descriptor=Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype,'srcdoc');
  Object.defineProperty(HTMLIFrameElement.prototype,'srcdoc',{...descriptor,set(html){window.__documentHtmls.push(html);return descriptor.set.call(this,html);}});
 },session||null);
 await ctx.routeWebSocket(/supabase/,s=>s.close());
 await ctx.route('**/*',async route=>{
  const req=route.request(),url=new URL(req.url());
  if(url.hostname==='127.0.0.1'||['data:','blob:'].includes(url.protocol))return route.continue();
  if(url.hostname!=='afxxaafsuscwyjzrnagc.supabase.co')return route.abort();
  if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
  const headers={...req.headers()};delete headers.host;delete headers.origin;delete headers.apikey;
  if(!session)delete headers.authorization;
  const response=await ctx.request.fetch(gateway+url.pathname+url.search,{headers,method:req.method(),data:req.postDataBuffer()||undefined});
  if(url.pathname==='/functions/v1/solar-admin-users')actions.push({action:req.postDataJSON()?.action,status:response.status()});
  if(response.status()>=400)errors.push({path:url.pathname,status:response.status()});
  return route.fulfill({response});
 });
 const page=await ctx.newPage();
 page.on('pageerror',error=>errors.push(error.message));page.on('dialog',dialog=>dialog.accept());
 await page.goto(base+path);return page;
}
async function finishWizard(page){
 for(const label of ['حفظ البيانات والمتابعة','مراجعة المخازن','مراجعة الحساب','حفظ إعدادات المستخدم'])
  await page.getByRole('button',{name:label,exact:true}).click();
 await page.getByRole('searchbox',{name:'بحث المستخدمين'}).waitFor();
}
async function userRow(page,handle){
 await page.getByRole('searchbox',{name:'بحث المستخدمين'}).fill(handle);
 const row=page.locator('[data-user-id]').filter({hasText:'@'+handle});await row.waitFor();return row;
}
async function receiptHtml(page,download=false){
 await page.goto(base+'/?section=salesHistory');
 const card=page.getByRole('article',{name:'بيع منظومة رقم '+invoice.number,exact:true});
 // Filtering by receipt number also works when newer records fill the first page.
 const input=page.locator('.salesArchive form input').first();
 await input.fill(String(invoice.number));await input.press('Enter');
 const [pdf]=await Promise.all([page.waitForEvent('popup'),card.getByRole('button',{name:'معاينة وصل الزبون',exact:true}).click()]);
 await pdf.locator('.pdfPage img').first().waitFor({timeout:45000});
 if(download){
  await pdf.screenshot({path:dir+'/warranty-pdf-preview.png'});
  const [file]=await Promise.all([pdf.waitForEvent('download'),pdf.locator('#pdfDownload').click()]);
  await file.saveAs(dir+'/warranty-with-brand.pdf');
  assert.equal((await readFile(dir+'/warranty-with-brand.pdf')).subarray(0,5).toString(),'%PDF-');
 }
 const html=await page.evaluate(()=>window.__documentHtmls.at(-1));await pdf.close();return html;
}
try{
 const before=hash(),page=await open('/?section=users',admin);
 await page.getByRole('button',{name:'إضافة مستخدم',exact:true}).click();
 await page.getByLabel('اسم المستخدم',{exact:true}).fill(username);
 await page.getByLabel('الاسم الظاهر',{exact:true}).fill('وليد');
 await page.getByLabel('كنية المستخدم',{exact:true}).fill('المهندس');
 await page.getByLabel('رقم هاتف المستخدم',{exact:true}).fill('07701234567');
 await page.getByLabel('كلمة المرور',{exact:true}).fill(password);
 await finishWizard(page);
 const row=await userRow(page,username);
 await row.getByRole('heading',{name:'المهندس وليد',exact:true}).waitFor();
 const created=JSON.parse(sql("select jsonb_build_object('id',id,'honorific',honorific,'name',display_name,'admin',is_admin) from profiles where username='"+username+"'"));
 assert.deepEqual([created.honorific,created.name,created.admin],['المهندس','وليد',false]);
 await row.getByRole('button',{name:'تعديل',exact:true}).click();
 assert.equal(await page.getByLabel('كنية المستخدم',{exact:true}).inputValue(),'المهندس');
 await page.getByLabel('كنية المستخدم',{exact:true}).fill('الإداري');
 await finishWizard(page);
 const saved=await userRow(page,username);
 await saved.getByRole('heading',{name:'الإداري وليد',exact:true}).waitFor();
 await saved.screenshot({path:dir+'/user-title-saved.png'});
 const email=sql("select email from auth.users where id='"+created.id+"'");
 const signed=await fetch(gateway+'/auth/v1/token?grant_type=password',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email,password})});
 assert.equal(signed.status,200);const session=await signed.json();
 const self=await open('/?section=home',session);
 await self.locator('.premiumMobileBrand').getByText('الإداري وليد',{exact:true}).waitFor();
 const denied=await fetch(gateway+'/functions/v1/solar-admin-users',{method:'POST',headers:{authorization:'Bearer '+session.access_token,'content-type':'application/json'},body:JSON.stringify({action:'directory'})});
 assert.ok([400,403].includes(denied.status));
 const html=await receiptHtml(page,true),warranty=html.match(/<section class="invoiceWarranty">([\s\S]*?)<\/section>/)?.[1];
 assert.ok(warranty);
 for(const label of ['FULLMAX','DEYE','بطارية','انفيرتر'])assert.ok(warranty.includes(label),label);
 assert.ok(!warranty.includes('ضمان الصيانة')&&!warranty.includes('بدون ضمان'));
 assert.ok(html.includes(originalTitle+' سفيان'));assert.ok(html.includes('المهندس صفاء'));
 const cert=await open('/warranty/'+invoice.token);
 await cert.getByRole('heading',{name:'شهادة ضمان الفاتورة',exact:true}).waitFor();
 assert.equal(await cert.locator('.certificateMaintenance').count(),0);
 assert.match(await cert.innerText('body'),/FULLMAX/);assert.ok(!(await cert.innerText('body')).includes('بدون ضمان'));
 await cert.screenshot({path:dir+'/certificate-no-maintenance.png',fullPage:true});
 await page.goto(base+'/?section=users');
 const owner=await userRow(page,'title_staff');
 await owner.getByRole('button',{name:'تعديل',exact:true}).click();
 await page.getByLabel('كنية المستخدم',{exact:true}).fill(editedTitle);
 await finishWizard(page);
 await (await userRow(page,'title_staff')).getByRole('heading',{name:editedTitle+' سفيان',exact:true}).waitFor();
 assert.ok((await receiptHtml(page)).includes(editedTitle+' سفيان'));
 assert.equal(hash(),before);assert.deepEqual(errors,[]);
 await writeFile(dir+'/results.json',JSON.stringify({pass:true,actions,errors,createAndUpdateTitlesPersisted:true,currentTitleOnOldInvoice:true,nonAdminDenied:true,warrantyBrandCategory:true,maintenanceOmitted:true,financialRecordsUnchanged:true},null,2));
 console.log('PASS wizard title create/edit, real staff login and role check, historical invoice and public warranty QR, unchanged financial records.');
}catch(error){
 for(const [i,ctx] of contexts.entries())await ctx.pages()[0]?.screenshot({path:dir+'/failure-'+i+'.png'}).catch(()=>{});
 await writeFile(dir+'/failure.json',JSON.stringify({error:error.message,actions,errors},null,2));throw error;
}finally{await browser.close();}
