// Compiled material ledger → real local API → isolated stock records. No production writes.
process.env.PW_TEST_SCREENSHOT_NO_FONTS_READY='1';
import assert from 'node:assert/strict';
import {createHmac,createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const db=process.env.SOLAR_FIXTURE_DB||'solar_v389_browser';
if(!/^solar_[a-z0-9_]+_browser$/.test(db))throw Error('Use an isolated local browser database');
const dir=process.env.SOLAR_ARTIFACT_DIR||'/workspace/solar-review/v389/material-browser';await mkdir(dir,{recursive:true});
const sql=q=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:q,encoding:'utf8'}).trim();
const ids={admin:'00000000-0000-0000-0000-000000003920',seller:'00000000-0000-0000-0000-000000003921',warehouse:'00000000-0000-0000-0000-000000003922',other:'00000000-0000-0000-0000-000000003923',quantity:'00000000-0000-0000-0000-000000003924'};
const errors=[],calls=[],contexts=[],encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url');let failBalance=false;
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
  return route.fulfill({response:r});
 });
 await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||u.protocol==='data:')return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
 const page=await ctx.newPage();page.on('pageerror',e=>errors.push(e.message));await page.goto('http://127.0.0.1:3073/?section='+section);return {page,ctx,token};
}
const fingerprint=()=>sql("select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from transactions t),'items',(select jsonb_agg(to_jsonb(t)order by id)from transaction_items t),'stock',(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),'transfers',(select jsonb_agg(to_jsonb(t)order by id)from solar_private.stock_transfers t),'cash',(select jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text)from cash_ledger t))::text)");
async function selectMaterial(p){const box=p.getByRole('combobox',{name:'اختيار مادة للحركة',exact:true});await box.fill('39201');await p.getByRole('option',{name:/39201.*لوح كشف الحركة/}).click();}
let page;
try{
 sql("update solar_private.stock_adjustments set created_at=now()-interval'2 days'where product_id=-392001");
 const before=fingerprint(),admin=await open('admin','stockMovement');page=admin.page;const p=page;
 await p.getByRole('heading',{name:'اختر المادة لعرض كشفها',exact:true}).waitFor();
 await selectMaterial(p);await p.getByTestId('material-current-qty').filter({hasText:/^12$/}).waitFor();
 const full=await admin.ctx.request.post('http://127.0.0.1:3079/rpc/solar_inventory',{headers:{authorization:'Bearer '+admin.token},data:{action:'material_report',payload:{productId:-392001}}});assert.equal(full.status(),200);const fullData=await full.json();
 assert.equal(await p.locator('.mlMovement').count(),fullData.rows.length);
 let sale=p.locator('.mlMovement').filter({hasText:'زبون بيع الألواح'});await sale.getByText('مجهز كشف المواد',{exact:true}).waitFor();
 assert.ok((await sale.innerText()).includes('بائع كشف المواد'));
 assert.ok(!(await p.locator('.mlWorkspace').innerText()).includes('3,000 د.ع'));
 await p.screenshot({path:dir+'/selected-material-mobile.png',fullPage:true});
 const today=sql("select(now()at time zone'Asia/Baghdad')::date::text");
 await p.getByLabel('بداية حركة المادة',{exact:true}).fill(today);await p.getByRole('button',{name:'عرض حركة المادة',exact:true}).click();
 await p.getByTestId('material-current-qty').filter({hasText:/^12$/}).waitFor();
 await p.waitForFunction(()=>!Array.from(document.querySelectorAll('.mlBadge')).some(x=>x.textContent.includes('تسوية رصيد')));
 for(const r of fullData.rows.filter(r=>r.kind!=='stock_adjustment')){
  const entry=p.locator('[data-movement-id="'+r.id+'"]');await entry.waitFor();assert.equal((await entry.locator('.mlQty.balance b').innerText()).replaceAll(',',''),String(Number(r.balance)));
 }
 await p.getByLabel('عرض الأسعار المثبتة بالمستند',{exact:true}).check();
 await p.locator('.mlPrice').filter({hasText:'3,000 د.ع'}).waitFor();
 await p.locator('.mlPrice').filter({hasText:'2,075 د.ع'}).waitFor();
 const system=p.locator('.mlMovement').filter({hasText:'زبون منظومة الألواح'});assert.ok((await system.innerText()).includes('سعر المادة غير موزّع'));
 await p.screenshot({path:dir+'/priced-material-mobile.png',fullPage:true});
 const report=p.locator('.mlWorkspace>.reportExport');
 await p.waitForFunction(()=>document.querySelector('.mlWorkspace>.reportExport .reportButton.download')?.disabled===false);
 const [download]=await Promise.all([p.waitForEvent('download'),report.getByRole('button',{name:'حفظ PDF',exact:true}).click()]);await download.saveAs(dir+'/priced-material.pdf');const bytes=await readFile(dir+'/priced-material.pdf');assert.equal(bytes.subarray(0,5).toString(),'%PDF-');
 const documents=await p.evaluate(()=>window.__documentHtmls);assert.ok(documents.some(x=>x.includes('كشف حركة مادة')&&x.includes('3,000 د.ع')&&x.includes('المجهّز: مجهز كشف المواد')&&x.includes('الرصيد بعد الحركة')));
 await report.getByRole('button',{name:'مشاركة',exact:true}).click();await report.getByText('تمت مشاركة ملف PDF.',{exact:true}).waitFor();const shared=await p.evaluate(()=>window.__sharedPdfs);assert.ok(shared[0].active);assert.equal(shared[0].hash,createHash('sha256').update(bytes).digest('hex'));
 const [preview]=await Promise.all([admin.ctx.waitForEvent('page'),report.getByRole('button',{name:'معاينة',exact:true}).click()]);await preview.getByRole('button',{name:'طباعة',exact:true}).waitFor();await preview.screenshot({path:dir+'/material-pdf-preview.png'});await preview.close();
 await p.getByRole('group',{name:'اتجاه حركة المادة',exact:true}).getByRole('button',{name:'خروج',exact:true}).click();
 assert.ok((await p.locator('.mlMovement').count())<fullData.rows.length);
 sale=p.locator('.mlMovement').filter({hasText:'زبون بيع الألواح'});const expectedSale=fullData.rows.find(r=>r.kind==='sale');assert.equal(Number(await sale.locator('.mlQty.balance b').innerText()),Number(expectedSale.balance));
 await p.getByRole('group',{name:'اتجاه حركة المادة',exact:true}).getByRole('button',{name:'الكل',exact:true}).click();
 await p.getByLabel('بحث تفاصيل حركة المادة',{exact:true}).fill('مجهز كشف المواد');assert.ok(await p.locator('.mlMovement').count()>=1);await p.locator('.mlMovement').filter({hasText:'زبون بيع الألواح'}).waitFor();
 await p.getByLabel('بحث تفاصيل حركة المادة',{exact:true}).fill('');
 for(const width of[360,768,1440]){await p.setViewportSize({width,height:920});assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await p.screenshot({path:dir+'/material-'+width+'.png'});}
 await p.getByLabel('مخزن كشف المادة',{exact:true}).selectOption('2');await p.getByRole('button',{name:'عرض حركة المادة',exact:true}).click();await p.getByTestId('material-current-qty').filter({hasText:/^2$/}).waitFor();
 assert.ok((await p.locator('.mlWarehouseGrid').innerText()).includes('مخزن صيادة'));
 await p.getByRole('tab',{name:'جميع الحركات',exact:true}).click();await p.locator('.movementEntry').first().waitFor();
 await p.getByRole('tab',{name:'حركة المادة وعميل',exact:true}).click();await p.getByLabel('اسم العميل في الحركة',{exact:true}).waitFor();
 const warehouse=await open('warehouse','stockMovement');page=warehouse.page;await selectMaterial(page);await page.getByTestId('material-current-qty').filter({hasText:/^10$/}).waitFor();
 assert.equal(await page.getByLabel('عرض الأسعار المثبتة بالمستند',{exact:true}).count(),0);assert.ok((await page.locator('.mlMovementParty>small').allTextContents()).every(x=>x!=='مخزن صيادة'));assert.equal(await page.locator('.mlPrice').count(),0);
 const denied=await warehouse.ctx.request.post('http://127.0.0.1:3079/rpc/solar_inventory',{headers:{authorization:'Bearer '+warehouse.token},data:{action:'material_report',payload:{productId:-392001,withPrices:true}}});assert.equal(denied.status(),403);
 const other=await open('other','stockMovement');page=other.page;await selectMaterial(page);await page.getByTestId('material-current-qty').waitFor();assert.equal(await page.locator('.mlMovement').count(),0);assert.ok(!(await page.locator('.mlWorkspace').innerText()).includes('زبون بيع الألواح'));
 assert.equal(fingerprint(),before);assert.deepEqual(errors,[]);
 await writeFile(dir+'/results.json',JSON.stringify({pass:true,exactMaterialSelection:true,unchangedRunningBalancesWithDateDirectionSearch:true,sourceAndPreparer:true,pricesFrozenInIQD:true,noGuessedSystemUnitPrice:true,warehousesSeparate:true,legacyViewsPreserved:true,pdfPreviewDownloadShare:true,serverEnforcesNoWarehousePrices:true,foreignDetailsIsolated:true,readOnlyStockFinanceHashUnchanged:true,noOverflow:[360,768,1440],calls,errors},null,2));
 console.log('PASS material picker → real stock ledger: all movements/balances, date and warehouse filters, source/preparer, price/no-price and system totals, PDFs/share, scoped API access, immutable stock/finance');
}catch(error){if(page)await page.screenshot({path:dir+'/failure.png',fullPage:true}).catch(()=>{});await writeFile(dir+'/failure.json',JSON.stringify({error:String(error),stack:error.stack,calls,errors},null,2));throw error;}finally{for(const ctx of contexts)await ctx.close();await browser.close();}
