// Real compiled app → isolated PostgREST → local PostgreSQL; no live writes.
process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
import assert from 'node:assert/strict';
import {createHmac,createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const db=process.env.SOLAR_FIXTURE_DB||'solar_v391_browser';
if(!/^solar_[a-z0-9_]+_browser$/.test(db))throw Error('An isolated local browser database is required');
const dir=process.env.SOLAR_ARTIFACT_DIR||'/workspace/solar-review/v391/browser';await mkdir(dir,{recursive:true});
const sql=q=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:q,encoding:'utf8'}).trim();
const ids={full:'00000000-0000-0000-0000-000000003911',limited:'00000000-0000-0000-0000-000000003912',warehouse:'00000000-0000-0000-0000-000000003914',installer:'00000000-0000-0000-0000-000000003915'};
const dirApi=process.env.SOLAR_FIXTURE_API||'http://127.0.0.1:3079',base=process.env.SOLAR_APP_URL||'http://127.0.0.1:3073',contexts=[],calls=[],errors=[],enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
const tokenFor=uid=>{const raw=enc({alg:'HS256',typ:'JWT'})+'.'+enc({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600});return raw+'.'+createHmac('sha256','solar-local-test-only-signing-secret-347').update(raw).digest('base64url');};
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});let page;
async function open(who){
 const uid=ids[who],token=tokenFor(uid),ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true});contexts.push(ctx);ctx.setDefaultTimeout(25000);
 // Optional saved presentation exercises the same real financial flows in a new design.
 if(process.env.SOLAR_TEST_DESIGN){
  assert.equal(new URL(dirApi).hostname,'127.0.0.1');
  const state=await ctx.request.post(dirApi+'/rpc/solar_section_layout',{headers:{authorization:'Bearer '+token},data:{action:'get'}});assert.equal(state.status(),200);
  const layout=await state.json(),saved=await ctx.request.post(dirApi+'/rpc/solar_section_layout',{headers:{authorization:'Bearer '+token},data:{action:'view',payload:{mode:process.env.SOLAR_TEST_DESIGN,expectedRevision:layout.revision}}});assert.equal(saved.status(),200);
 }
 await ctx.addInitScript(({uid,token})=>{localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify({access_token:token,refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}}));window.__documentHtmls=[];window.__sharedPdfs=[];Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>true});Object.defineProperty(navigator,'share',{configurable:true,value:async data=>{const f=data.files[0];window.__sharedPdfs.push({name:f.name,active:navigator.userActivation.isActive,hash:Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',await f.arrayBuffer()))).map(x=>x.toString(16).padStart(2,'0')).join('')});}});const descriptor=Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype,'srcdoc');Object.defineProperty(HTMLIFrameElement.prototype,'srcdoc',{...descriptor,set(html){window.__documentHtmls.push(html);return descriptor.set.call(this,html);}});},{uid,token});
 await ctx.routeWebSocket(/supabase/,socket=>socket.close());
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),u=new URL(req.url());
  if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
  if(u.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:uid,email:'fixture@local.test',aud:'authenticated'})});
  if(!u.pathname.startsWith('/rest/v1/'))return route.abort();
  const headers={...req.headers(),authorization:'Bearer '+token};delete headers.apikey;delete headers.host;delete headers.origin;
  const r=await ctx.request.fetch(dirApi+u.pathname.replace('/rest/v1','')+u.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined}),body=await r.text();
  if(u.pathname.includes('/rpc/')||u.pathname.endsWith('/solar_quotes'))calls.push({who,path:u.pathname,method:req.method(),payload:req.postData()?JSON.parse(req.postData()):null,status:r.status()});
  if(r.status()>=400)errors.push({who,path:u.pathname,status:r.status(),body});
  return route.fulfill({response:r,body});
 });
 await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const p=await ctx.newPage();p.on('dialog',d=>d.accept());p.on('pageerror',e=>errors.push(String(e)));await p.goto(base+'/?section=tahseel');await p.getByRole('region',{name:'حاسبة التحصيل وعروض المنظومات',exact:true}).waitFor();return{p,ctx,token};
}
const financialHash=()=>sql("select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from transactions t),'items',(select jsonb_agg(to_jsonb(t)order by id)from transaction_items t),'products',(select jsonb_agg(to_jsonb(t)order by id)from products t),'stock',(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),'cash',(select jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text)from cash_ledger t),'entries',(select jsonb_agg(to_jsonb(t)order by id)from solar_cash_entries t))::text)");
const legacyHash=()=>sql("select md5(payload::text)from solar_quotes where id='00000000-0000-0000-0000-000000391001'");
async function fill(p,name){await p.getByLabel('اسم زبون العرض',{exact:true}).fill(name);await p.getByLabel('هاتف زبون العرض',{exact:true}).fill('07701234567');await p.getByLabel('أمبير نهاري',{exact:true}).fill('15');await p.getByLabel('أمبير ليلي',{exact:true}).fill('15');await p.getByLabel('سعة البطارية',{exact:true}).selectOption('15');await p.getByRole('tab',{name:'المواد',exact:true}).click();await p.getByLabel('الانفيرتر',{exact:true}).selectOption('391001');await p.getByLabel('لوح 600 واط',{exact:true}).selectOption('391002');await p.getByLabel('بطارية 15 كيلو',{exact:true}).selectOption('391003');}
async function readyPdf(p){await p.waitForFunction(()=>document.querySelector('.quoteDocumentTools .reportButton.download')?.disabled===false);}
async function pdf(p,name){await readyPdf(p);const[download]=await Promise.all([p.waitForEvent('download'),p.getByRole('button',{name:'حفظ PDF',exact:true}).click()]);await download.saveAs(dir+'/'+name);const bytes=await readFile(dir+'/'+name);assert.equal(bytes.subarray(0,5).toString(),'%PDF-');return bytes;}

const notes='ملاحظات جهاز متكامل <script> & تفاصيل';
async function fillAllInOne(p,name,device='391005',qty='2'){
 await p.getByLabel('اسم زبون العرض',{exact:true}).fill(name);
 await p.getByRole('radio',{name:/ALL IN ONE/}).check();
 await p.getByLabel('أمبير نهاري',{exact:true}).fill('15');await p.getByLabel('أمبير ليلي',{exact:true}).fill('15');
 assert.equal(await p.getByLabel('سعة البطارية',{exact:true}).count(),0);
 await p.getByRole('tab',{name:'المواد',exact:true}).click();
 assert.equal(await p.getByLabel('الانفيرتر',{exact:true}).count(),0);assert.equal(await p.getByLabel('بطارية 15 كيلو',{exact:true}).count(),0);
 await p.getByLabel('ALL IN ONE',{exact:true}).selectOption(device);await p.getByLabel('لوح 600 واط',{exact:true}).selectOption('391002');
 await p.getByLabel('عدد أجهزة ALL IN ONE',{exact:true}).fill(qty);
}
try{
 const before=financialHash(),old=legacyHash(),full=await open('full'),p=full.p;page=p;
 assert.ok(await p.getByRole('radio',{name:/النظام العادي/}).isChecked());
 await fillAllInOne(p,'عرض متكامل كامل');
 await p.getByTestId('quote-final-price').filter({hasText:'8,841,000'}).waitFor();
 await p.getByTestId('quote-materials-cost').filter({hasText:'7,700,000'}).waitFor();
 await p.getByTestId('quote-allinone-total').filter({hasText:'7,000,000'}).waitFor();
 for(const width of[320,360,390,768,1440]){
  await p.setViewportSize({width,height:920});await p.getByRole('tab',{name:'الطلب',exact:true}).click();await p.evaluate(()=>scrollTo(0,0));
  assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'Integrated quote overflow '+width);
  await p.screenshot({path:dir+'/request-'+width+'.png',fullPage:true});
 }
 await p.setViewportSize({width:390,height:920});await p.getByRole('tab',{name:'المواد',exact:true}).click();
 await p.getByLabel('ALL IN ONE',{exact:true}).selectOption('391006');await p.getByLabel('عدد أجهزة ALL IN ONE',{exact:true}).fill('1');
 await p.getByTestId('quote-final-price').filter({hasText:'8,316,000'}).waitFor();
 await p.getByLabel('ALL IN ONE',{exact:true}).selectOption('391005');await p.getByLabel('عدد أجهزة ALL IN ONE',{exact:true}).fill('2');
 await p.getByRole('tab',{name:'الطلب',exact:true}).click();await p.getByLabel('أمبير نهاري',{exact:true}).fill('');await p.getByLabel('أمبير ليلي',{exact:true}).fill('');await p.getByLabel('عدد الألواح',{exact:true}).fill('10');
 await p.getByTestId('quote-final-price').filter({hasText:'9,297,750'}).waitFor();
 await p.getByRole('tab',{name:'الملاحظات',exact:true}).click();await p.getByLabel('ملاحظات العرض',{exact:true}).fill(notes);
 await p.getByRole('button',{name:'حفظ كمسودة',exact:true}).dblclick();await p.getByRole('status').filter({hasText:'تم حفظ المسودة في حسابك.'}).waitFor();
 const saved=JSON.parse(sql("select payload from solar_quotes where payload->>'customer'='عرض متكامل كامل'"));assert.equal(saved.systemType,'all_in_one');assert.equal(saved.allInOneQty,'2');assert.equal(saved.allInOnePanelQty,'10');assert.equal(saved.notes,notes);
 assert.equal(Number(sql("select count(*)from solar_quotes where payload->>'customer'='عرض متكامل كامل'")),1);
 const customerPdf=await pdf(p,'all-in-one-customer.pdf');await p.getByRole('button',{name:'مشاركة',exact:true}).click();await p.getByText('تمت مشاركة ملف PDF.',{exact:true}).waitFor();
 let shares=await p.evaluate(()=>window.__sharedPdfs);assert.ok(shares.at(-1).active);assert.equal(shares.at(-1).hash,createHash('sha256').update(customerPdf).digest('hex'));
 let htmls=await p.evaluate(()=>window.__documentHtmls),doc=htmls.findLast(x=>x.includes('5KW/ALLINONE')&&x.includes('ملاحظات جهاز متكامل'));
 assert.ok(doc.includes('&lt;script&gt;'));assert.ok(!doc.includes('<script>'));assert.match(doc,/5KW\/ALLINONE[\s\S]*?<td>2<\/td>/);assert.ok(!doc.includes('3,500,000')&&!doc.includes('15KW'));
 const[preview]=await Promise.all([full.ctx.waitForEvent('page'),p.getByRole('button',{name:'معاينة',exact:true}).click()]);await preview.waitForLoadState();await preview.getByRole('button',{name:'طباعة',exact:true}).waitFor();await preview.close();
 await p.getByLabel('نسخة مستند التحصيل',{exact:true}).selectOption('internal');await pdf(p,'all-in-one-internal.pdf');
 htmls=await p.evaluate(()=>window.__documentHtmls);doc=htmls.findLast(x=>x.includes('5KW/ALLINONE')&&x.includes('3,500,000'));assert.ok(doc&&doc.includes('7,000,000'));
 await p.reload();await p.getByRole('tab',{name:/المسودات/}).click();await p.getByLabel('بحث المسودات',{exact:true}).fill('عرض متكامل كامل');await p.getByRole('button',{name:'فتح وتعديل',exact:true}).click();
 assert.equal(await p.getByLabel('عدد أجهزة ALL IN ONE',{exact:true}).inputValue(),'2');await p.getByTestId('quote-final-price').filter({hasText:'9,297,750'}).waitFor();
 await p.getByRole('tab',{name:'الطلب',exact:true}).click();assert.ok(await p.getByRole('radio',{name:/ALL IN ONE/}).isChecked());assert.equal(await p.getByLabel('عدد الألواح',{exact:true}).inputValue(),'10');
 await p.getByRole('radio',{name:/النظام العادي/}).check();await p.getByLabel('سعة البطارية',{exact:true}).waitFor();
 await p.getByRole('radio',{name:/ALL IN ONE/}).check();await p.getByRole('tab',{name:'المواد',exact:true}).click();assert.equal(await p.getByLabel('عدد أجهزة ALL IN ONE',{exact:true}).inputValue(),'2');
 const limited=await open('limited'),l=limited.p;page=l;await fillAllInOne(l,'عرض متكامل محدود');
 await l.getByTestId('quote-final-price').filter({hasText:'9,683,000'}).waitFor();assert.equal(await l.locator('.quoteMaterialCosts,.quoteCostBreakdown').count(),0);
 await l.getByRole('tab',{name:'الطلب',exact:true}).click();await l.getByLabel('أمبير نهاري',{exact:true}).fill('');await l.getByLabel('أمبير ليلي',{exact:true}).fill('');await l.getByLabel('عدد الألواح',{exact:true}).fill('10');await l.getByTestId('quote-final-price').filter({hasText:'10,183,250'}).waitFor();
 await l.getByRole('button',{name:'حفظ كمسودة',exact:true}).click();await l.getByRole('status').filter({hasText:'تم حفظ المسودة في حسابك.'}).waitFor();
 await pdf(l,'all-in-one-limited.pdf');htmls=await l.evaluate(()=>window.__documentHtmls);doc=htmls.findLast(x=>x.includes('5KW/ALLINONE'));assert.ok(doc&&!doc.includes('3,500,000')&&!doc.includes('7,000,000'));
 await l.reload();await l.getByRole('tab',{name:/المسودات/}).click();await l.getByLabel('بحث المسودات',{exact:true}).fill('عرض متكامل محدود');await l.getByRole('button',{name:'فتح وتعديل',exact:true}).click();
 assert.equal(await l.getByLabel('عدد أجهزة ALL IN ONE',{exact:true}).inputValue(),'2');await l.getByTestId('quote-final-price').filter({hasText:'10,183,250'}).waitFor();
 await l.getByLabel('ALL IN ONE',{exact:true}).selectOption('391006');await l.getByLabel('عدد أجهزة ALL IN ONE',{exact:true}).fill('1');await l.getByTestId('quote-final-price').filter({hasText:'9,608,250'}).waitFor();
 const forged={systemType:'all_in_one',day:'15',night:'15',allInOneQty:'2',panel:{id:391002,cost:'1'},allInOne:{id:391005,cost:'1'},battery:{id:391003,cost:'99999999'},inverter:{id:391001,cost:'99999999'},perPanel:'0',expenses:{},markupPercent:'0'};
 const response=await limited.ctx.request.post(dirApi+'/rpc/solar_limited_quote',{headers:{authorization:'Bearer '+limited.token},data:{action:'preview',quote_payload:forged}});assert.equal(response.status(),200);const answer=await response.json();assert.equal(answer.price,9683000);assert.ok(!/unitCost|materialsTotal|expensesTotal|"cost"/.test(JSON.stringify(answer)));
 const bad=await limited.ctx.request.post(dirApi+'/rpc/solar_limited_quote',{headers:{authorization:'Bearer '+limited.token},data:{action:'preview',quote_payload:{...forged,allInOne:{id:391001}}}});assert.equal((await bad.json()).price,null);
 assert.equal(financialHash(),before);assert.equal(legacyHash(),old);assert.deepEqual(errors,[]);
 await writeFile(dir+'/results.json',JSON.stringify({pass:true,bothModels:true,multipleDevices:true,manualPanelCountWithoutAmps:true,sameExpenses:true,restrictedTrustedCost:true,oldDraftUnchanged:true,pdfPreviewDownloadShare:true,persistence:true,privacy:true,financialStateUnchanged:true,noOverflow:[320,360,390,768,1440],calls,errors},null,2));
 console.log('PASS ALL IN ONE full/limited quotes: 5KW/10KW, quantities, expense/markup pricing, trusted costs, drafts, privacy, PDFs and unchanged financial data');
}catch(error){if(page)await page.screenshot({path:dir+'/failure.png',fullPage:true}).catch(()=>{});await writeFile(dir+'/failure.json',JSON.stringify({error:String(error),stack:error.stack,calls,errors},null,2));throw error;}finally{for(const c of contexts)await c.unrouteAll({behavior:'ignoreErrors'}).catch(()=>{});await browser.close();}
