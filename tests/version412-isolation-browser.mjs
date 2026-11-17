// Read-only application flows against the synthetic seller-isolation database.
// Role changes below affect fixture profiles only and are restored in finally.
process.env.SOLAR_FIXTURE_DB||='solar_seller_scope_browser';
process.env.SOLAR_FIXTURE_API||='http://127.0.0.1:3149';
process.env.SOLAR_APP_URL||='http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR||='/workspace/solar-review/v412/browser';
import assert from 'node:assert/strict';
const {createHarness,rpc,sql,fingerprint,base,api,tokenFor}=await import('./version4-browser-support.mjs');
const h=await createHarness('version412-isolation'),ids={admin:'00000000-0000-0000-0000-000000412101',sufyan:'00000000-0000-0000-0000-000000412102',abdul:'00000000-0000-0000-0000-000000412103'};
const forbidden=/PRIVATE_FOREIGN_V412|مادة عبدالرحمن الخاصة V412|9876543|9,876,543|7654321|7,654,321/;
const foreignDetails=/PRIVATE_FOREIGN_V412|مادة عبدالرحمن الخاصة V412|عبدالرحمن اختبار V412/;
const receipts=JSON.parse(sql("select jsonb_object_agg(id,receipt_no)from transactions where id between -412108 and -412101"));
const ownSaleLabel='بيع جملة رقم '+receipts[-412101],foreignSaleLabel='بيع جملة رقم '+receipts[-412102];
const authSession=id=>({access_token:tokenFor(id),refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id,email:'fixture@local.test',aud:'authenticated'}});
const original=JSON.parse(sql("select to_jsonb(p)from profiles p where id='"+ids.sufyan+"'"));
let inject='',holdUser='',held=null,release=null;
const heldReady=()=>new Promise(resolve=>{held=resolve;});
async function proxy({route,call,response}){
 if(holdUser&&call.who===holdUser&&call.path.endsWith('/solar_sales_history_by_user')){holdUser='';const pause=new Promise(resolve=>{release=resolve;});held?.();await pause;}
 if(inject&&call.who===ids.sufyan&&response.status()===200&&((inject==='history'&&call.path.endsWith('/solar_sales_history_by_user'))||(inject==='period'&&call.path.endsWith('/solar_sales_period_by_user')))){
  const type=inject;inject='';const body=await response.json();if(type==='history'){const foreign=await rpc(ids.admin,'solar_sales_history_by_user',{owner_id:null,search_text:String(receipts[-412102])});body.rows.push(foreign.rows.find(row=>row.id===-412102));body.count++;}else body.ownerId=ids.abdul;
  call.injectedForeignScope=true;await route.fulfill({json:body,headers:{'access-control-allow-origin':'*'}});return true;
 }
 if(response.status()>=400)h.errors.push({path:call.path,status:response.status(),body:await response.text()});
 await route.fulfill({response,headers:{...response.headers(),'access-control-allow-origin':'*','access-control-expose-headers':'content-range,range-unit,preference-applied'}});return true;
}
 h.setIntercept(proxy);
async function refreshAuth(page,id=ids.sufyan,event='TOKEN_REFRESHED'){
 await page.evaluate(({session,event})=>{const key='sb-afxxaafsuscwyjzrnagc-auth-token';localStorage.setItem(key,JSON.stringify(session));const channel=new BroadcastChannel(key);channel.postMessage({event,session});setTimeout(()=>channel.close(),100);},{session:authSession(id),event});
}
function promote(on){sql("update profiles set is_admin="+(on?'true':'false')+" where id='"+ids.sufyan+"'");}
async function search(page,value='V412_SCOPE'){await page.getByLabel('بحث الوصل أو الزبون',{exact:true}).fill(value);await page.getByRole('button',{name:'بحث / تحديث',exact:true}).click();}
async function ownArchive(page){await page.locator('.saleHistoryCard').first().waitFor();assert.equal(await page.locator('.saleHistoryCard').count(),2);assert.doesNotMatch(await page.locator('.salesArchive').innerText(),forbidden);assert.equal(await page.getByLabel('مستخدم المبيعات السابقة',{exact:true}).count(),0);}
async function refreshFromRole(page,admin){promote(admin);await page.evaluate(()=>window.dispatchEvent(new Event('focus')));if(admin)await page.getByLabel('مستخدم المبيعات السابقة',{exact:true}).waitFor();else await page.getByLabel('مستخدم المبيعات السابقة',{exact:true}).waitFor({state:'detached'});}
async function latestHtml(page,start,required){await page.waitForFunction(n=>window.__documentHtmls.length>n,start,{timeout:90000});const html=await page.evaluate(()=>window.__documentHtmls.at(-1));assert.doesNotMatch(html,forbidden);if(required)assert.match(html,required);return html;}
async function archivePreview(page,ctx){const card=page.getByRole('article',{name:ownSaleLabel,exact:true}),start=await page.evaluate(()=>window.__documentHtmls.length);const popupPromise=ctx.waitForEvent('page');await card.getByRole('button',{name:'معاينة وصل الزبون',exact:true}).click();const popup=await popupPromise;await popup.locator('.pdfPage img').first().waitFor({timeout:90000});await latestHtml(page,start,/مادة سفيان الخاصة V412/);await popup.screenshot({path:h.dir+'/own-invoice-preview.png'});await popup.close();}
async function dynamicActorRoute(ctx){
 await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
  const req=route.request(),url=new URL(req.url());if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*'}});
  const authorization=req.headers().authorization||'',token=authorization.replace(/^Bearer /,''),who=JSON.parse(Buffer.from(token.split('.')[1]||'e30','base64url').toString()).sub;
  if(url.pathname==='/auth/v1/user')return route.fulfill({json:{id:who,email:'fixture@local.test',aud:'authenticated'}});
  if(!url.pathname.startsWith('/rest/v1/'))return route.abort();
  const call={who,path:url.pathname,method:req.method(),body:req.postData()?JSON.parse(req.postData()):null};h.calls.push(call);const headers={...req.headers()};delete headers.apikey;delete headers.host;delete headers.origin;
  const response=await ctx.request.fetch(api+url.pathname.replace('/rest/v1','')+url.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined});call.status=response.status();await proxy({route,call,response});
 });
}
try{
 const customerOnly=process.env.SOLAR_SHARED_CUSTOMER_ONLY==='1',skipCustomer=process.env.SOLAR_SKIP_SHARED_CUSTOMER==='1';
 const before=fingerprint(),seller=await h.open(ids.sufyan,'/?section=salesHistory'),s=seller.page;
 if(!customerOnly){
 await search(s);await ownArchive(s);await s.getByRole('article',{name:ownSaleLabel,exact:true}).locator('summary').filter({hasText:'تفاصيل المواد'}).click();await archivePreview(s,seller.ctx);h.checks.ownArchiveDetailsAndInvoicePdfExcludeForeignReceipts=true;
 await s.getByRole('button',{name:'مبيعات الفترة',exact:true}).click();await s.locator('.periodMaterialsTable').waitFor();assert.equal(await s.locator('.periodMaterialsTable tbody tr').count(),1);assert.doesNotMatch(await s.locator('.periodSales').innerText(),forbidden);const periodHtml=await h.report(s,seller.ctx,s.locator('.periodSales .reportExport'),'own-period');assert.doesNotMatch(periodHtml,forbidden);assert.match(periodHtml,/مادة سفيان الخاصة V412/);await h.layout(s,'own-period-scope',s.locator('.periodSales'));h.checks.periodPreviewSaveShareOnlyOwnData=true;
 await s.goto(base+'/?section=sale');await s.locator('.deskHistory > summary').waitFor();await s.locator('.deskHistory > summary').click();assert.doesNotMatch(await s.locator('.deskHistory').innerText(),forbidden);assert.match(await s.locator('.deskHistory').innerText(),/عميل مشترك V412_SCOPE/);h.checks.inlinePreviousInvoicesOnlyOwn=true;
 }
 if(!skipCustomer){
 // A customer owner must not see another seller's original invoice or notes.
 await s.goto(base+'/?section=customers');await s.getByLabel('بحث الزبائن المسجلين',{exact:true}).fill('07700412901');await s.getByRole('button',{name:'حساب عميل مشترك V412_SCOPE',exact:true}).click();await s.getByTestId('statement-balance').waitFor();assert.doesNotMatch(await s.locator('main').innerText(),foreignDetails);assert.equal(await s.locator('.miniMovementRow:disabled').count(),3);await s.getByRole('button',{name:'مبيعات',exact:true}).click();await s.locator('.partyInvoiceCard').first().waitFor();assert.equal(await s.locator('.partyInvoiceCard').count(),1);assert.doesNotMatch(await s.locator('main').innerText(),forbidden);let html=await h.report(s,seller.ctx,s.locator('.partyReportActions'),'shared-customer-own-invoices');assert.doesNotMatch(html,forbidden);await s.getByRole('button',{name:'رجوع للحساب',exact:true}).click();await s.getByRole('button',{name:'كشف حساب',exact:true}).click();await s.locator('.miniStatementTable').waitFor();assert.doesNotMatch(await s.locator('.miniStatementTable').innerText(),foreignDetails);assert.equal(await s.locator('.miniStatementOpen:disabled').count(),3);assert.match(await s.locator('.miniStatementTable').innerText(),/أثر حسابي/);html=await h.report(s,seller.ctx,s.locator('.partyReportActions'),'shared-customer-own-statement');assert.doesNotMatch(html,foreignDetails);assert.match(html,/أثر حسابي/);h.checks.sharedCustomerPreservesBalanceButHidesForeignReceiptMetadata=true;
 }
 if(!customerOnly){
 // Malformed upstream scope must not keep even an apparently valid row or count.
 await s.goto(base+'/?section=salesHistory');await s.getByRole('button',{name:'العرض الحالي',exact:true}).click();await search(s);await ownArchive(s);inject='history';await search(s);await s.getByRole('alert').filter({hasText:/تعذر/}).waitFor();assert.equal(await s.locator('.saleHistoryCard').count(),0);assert.equal(await s.getByRole('button',{name:'معاينة وصل الزبون',exact:true}).count(),0);assert.doesNotMatch(await s.locator('.salesArchive').innerText(),forbidden);h.checks.injectedMixedHistoryFailsClosed=true;
 await search(s);await ownArchive(s);inject='period';await s.getByRole('button',{name:'مبيعات الفترة',exact:true}).click();await s.getByRole('alert').filter({hasText:/تعذر/}).waitFor();assert.equal(await s.locator('.periodSales .reportExport').count(),0);assert.equal(await s.locator('.periodMaterialsTable').count(),0);h.checks.injectedWrongPeriodScopeHasNoPdf=true;
 await s.getByRole('button',{name:'العرض الحالي',exact:true}).click();await search(s);await ownArchive(s);
 // Same signed-in user loses administrator access while reports/editors are open.
 await refreshFromRole(s,true);await s.getByLabel('مستخدم المبيعات السابقة',{exact:true}).selectOption(ids.abdul);await search(s);await s.getByRole('article',{name:foreignSaleLabel,exact:true}).waitFor();assert.equal(await s.locator('.saleHistoryCard').count(),4);await refreshFromRole(s,false);await ownArchive(s);h.checks.sameAccountDowngradeClearsForeignArchive=true;
 await refreshFromRole(s,true);await search(s);await s.getByRole('button',{name:'مبيعات الفترة',exact:true}).click();await s.locator('.periodMaterialsTable').waitFor();assert.match(await s.locator('.periodMaterialsTable').innerText(),/مادة عبدالرحمن الخاصة V412/);await refreshFromRole(s,false);await s.locator('.periodMaterialsTable').waitFor();assert.doesNotMatch(await s.locator('.periodSales').innerText(),forbidden);assert.equal(await s.locator('.periodMaterialsTable tbody tr').count(),1);h.checks.sameAccountDowngradeClearsPeriodSnapshot=true;
 await s.getByRole('button',{name:'العرض الحالي',exact:true}).click();await refreshFromRole(s,true);await search(s);await s.getByRole('article',{name:foreignSaleLabel,exact:true}).getByRole('button',{name:'تعديل الفاتورة',exact:true}).click();await s.locator('.invoiceWorkspace').waitFor();await refreshFromRole(s,false);await s.locator('.invoiceWorkspace').waitFor({state:'detached'});await ownArchive(s);assert.equal(await s.getByText('سياسة حساب صاحب الفاتورة: عبدالرحمن اختبار V412',{exact:true}).count(),0);h.checks.sameAccountDowngradeDiscardsForeignEditorAndPricing=true;
 // Release an old authorized administrator response only after the new role's
 // own request has completed. It must not repopulate cards or PDF controls.
 await refreshFromRole(s,true);await search(s);await s.getByRole('article',{name:foreignSaleLabel,exact:true}).waitFor();holdUser=ids.sufyan;const oldAdminReady=heldReady();await search(s);await oldAdminReady;await refreshFromRole(s,false);await ownArchive(s);release();release=null;await s.waitForTimeout(250);await ownArchive(s);h.checks.delayedOldRoleResponseCannotRestoreForeignRows=true;
 // Real SDK BroadcastChannel event updates the session; API proxy reads each
 // request's bearer, rather than fixing the original actor for the context.
 const switched=await h.open(ids.abdul,'/?section=salesHistory'),p=switched.page;await dynamicActorRoute(switched.ctx);await search(p);await p.getByRole('article',{name:foreignSaleLabel,exact:true}).waitFor();holdUser=ids.abdul;const oldAccountReady=heldReady();await search(p);await oldAccountReady;await refreshAuth(p,ids.sufyan,'SIGNED_IN');await p.getByRole('article',{name:ownSaleLabel,exact:true}).waitFor();await ownArchive(p);release();release=null;await p.waitForTimeout(250);await ownArchive(p);h.checks.accountSwitchIgnoresDelayedOtherAccountSnapshot=true;
 const ownCalls=h.calls.filter(c=>c.who===ids.sufyan&&c.path.endsWith('/solar_sales_history_by_user')&&!c.injectedForeignScope);assert.ok(ownCalls.some(c=>c.body.owner_id===ids.sufyan));assert.ok(h.calls.some(c=>c.who===ids.sufyan&&c.path.endsWith('/solar_sales_period_by_user')&&c.body.owner_id===ids.sufyan));
 }
 assert.equal(fingerprint(),before);h.checks.noFinancialWrites=true;await h.finish();console.log(customerOnly?'PASS V4.1.2 shared-customer effects, own invoice export and statement PDF privacy':skipCustomer?'PASS V4.1.2 archive/PDF isolation, fail-closed responses, focus demotion and account switch':'PASS V4.1.2 combined seller isolation browser suite');
}catch(error){await h.fail(error);throw error;}finally{if(release)release();sql("update profiles set is_admin="+(original.is_admin?'true':'false')+",permissions='"+JSON.stringify(original.permissions).replaceAll("'","''")+"'::jsonb where id='"+ids.sufyan+"'");await h.close();}
