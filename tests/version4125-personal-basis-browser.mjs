// Exercise the admin checkbox and financial contracts through PostgREST against an isolated DB.
// All browser requests must go to the matching loopback database; production is never contacted.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4125_pricing_basis_verified_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3337';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3335';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4125/integration/browser';
const {db,api,sql,cash,rpc,tokenFor,createHarness}=await import('./version4-browser-support.mjs');
assert.match(db,/^solar_v4125_pricing_basis(?:_[a-z0-9]+)?_browser$/);
const seller=randomUUID(),standard=randomUUID(),engineer=randomUUID();
const sample=Date.now(),enabledProduct=sample,hiddenProduct=sample+1;
const enabledName='انفيرتر اختبار '+sample,hiddenName='لوح اختبار '+sample;
const productCost=385331,hiddenCost=98739,floor=430000;
const customer='متجر اختبار الأساس '+sample;
const receiverCustomer='منظومة اختبار الأساس '+sample;
const pricePermissions={sale:true,system:true,salesHistory:true,customers:true,customerStatement:true,stock:true,installations:true,profit:true,profitSettlement:true};
const priceState=()=>rpc('admin','solar_profit_basis_users',{action:'state'});
const userProfit=(who)=>rpc(who,'solar_profit_workspace',{action:'overview',payload:{}});
const resultFor=(w,id)=>w.rows.find(r=>r.key==='tx:'+id);
const profit=(who,id)=>rpc(who,'solar_profit_detail',{source_key:'tx:'+id,owner_id:who});
const event=(who,id,rev,action,payload={})=>rpc(who,'solar_installation_action',{job_id:id,expected_revision:rev,action,payload},204);
let h;
function noCosts(value,where){
 const visit=(item)=>{
  if(Array.isArray(item))return item.forEach(visit);
  if(item&&typeof item==='object')return Object.values(item).forEach(visit);
  if(typeof item==='number'||typeof item==='string'){
   for(const v of [productCost,hiddenCost])
    assert.ok(!new RegExp('(^|[^0-9])'+v+'(?:\\.0+)?(?![0-9])').test(String(item).replaceAll(',','')),where+' includes a company unit cost');
  }
 };
 visit(value);
}
async function configure(enabled){
 const current=await priceState();
 const payload={token:current.token,changes:[{id:seller,enabled}]};
 const request={action:'save',request_id:randomUUID(),payload};
 const changed=await rpc('admin','solar_profit_basis_users',request);
 assert.equal(changed.users.find(u=>u.id===seller)?.enabled,enabled);
 return {request,changed};
}
async function setPrices(price){
 const state=await rpc('admin','solar_wholesale_pricing',{action:'state'});
 const items=[[enabledProduct,price,true],[hiddenProduct,199000,false]].map(([productId,minPrice,enabled])=>{
  const row=state.products.find(p=>Number(p.id)===productId);
  assert.ok(row,'missing catalog setup row');
  return {productId,minPrice,enabled,expectedRevision:row.revision};
 });
 return rpc('admin','solar_wholesale_pricing',{action:'save',request_id:randomUUID(),payload:{items}});
}
function setup(){
 for(const [id,label,kind] of [[seller,'المستخدم المحدد','admin_staff'],[standard,'المستخدم الاعتيادي','admin_staff'],[engineer,'مهندس التجرِبة','installer']]){
  sql("insert into public.profiles(id,username,display_name,phone,active,is_admin,user_type,permissions) values ('"+id+"','personal_basis_"+id+"','"+label+' '+sample+"','07700000000',true,false,'"+kind+"','"+JSON.stringify(kind==='installer'?{installations:true}:pricePermissions)+"')");
 }
 sql("begin; insert into public.products(id,code,name,qty,cost) values ("+enabledProduct+",'PB-A-"+sample+"','"+enabledName+"',50,"+productCost+"),("+hiddenProduct+",'PB-B-"+sample+"','"+hiddenName+"',50,"+hiddenCost+"); insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values (1,"+enabledProduct+",50),(1,"+hiddenProduct+",50) on conflict(warehouse_id,product_id) do update set qty=excluded.qty; insert into public.customers(id,name,owner_id,customer_type) values ("+sample+",'"+customer+"','"+seller+"','wholesale'),("+(sample+1)+",'"+receiverCustomer+"','"+seller+"','system'),("+(sample+2)+",'"+customer+" عادي','"+standard+"','wholesale');commit");
}
function salePayload(who,mixed=false){
 return {kind:'sale',mode:'credit',partyId:who===seller?sample:sample+2,party:who===seller?customer:customer+' عادي',warehouseId:1,
  expenses:mixed?2000:0,expensesOnCustomer:false,items:[{id:enabledProduct,qty:mixed?2:1,price:455000},...(mixed?[{id:hiddenProduct,qty:1,price:150000}]:[])]};
}
async function invoice(who,body,check=false){
 const request={request_id:randomUUID(),payload:body};
 const result=await rpc(who,'solar_invoice_save',request);
 const id=Number(result.id);
 assert.ok(id);
 const duplicate=await rpc(who,'solar_invoice_save',request);
 assert.equal(Number(duplicate.id),id,'duplicate receipt on retry');
 if(check){noCosts(result,'invoice save');noCosts(duplicate,'invoice retry');}
 return {id,no:Number(sql('select receipt_no from public.transactions where id='+id)),request};
}
async function rawRows(path,params){
 const url=new URL(api+'/'+path);for(const [k,v] of Object.entries(params))url.searchParams.set(k,v);
 const response=await fetch(url,{headers:{authorization:'Bearer '+tokenFor(seller)}});
 if(response.status===403)return [];
 assert.equal(response.status,200,'raw '+path+' unexpected status');
 const rows=await response.json();
 noCosts(rows,'raw '+path);
 return rows;
}
async function assertBlockedRaw(sale){
 const rawProduct=await rawRows('products',{select:'*',id:'in.('+enabledProduct+','+hiddenProduct+')'});
 const rawTx=await rawRows('transactions',{select:'*',id:'eq.'+sale.id});
 const rawItems=await rawRows('transaction_items',{select:'*',transaction_id:'eq.'+sale.id});
 const counts={products:rawProduct.length,transactions:rawTx.length,transactionItems:rawItems.length};
 assert.deepEqual(counts,{products:0,transactions:0,transactionItems:0});
 return counts;
}
async function checkClosed(who,id,expected){
 const row=resultFor(await userProfit(who),id);
 assert.ok(row,'profit ledger missing receipt '+id);
 assert.equal(Number(row.value),expected,'posted staff profit');
 const doc=await profit(who,id);
 assert.equal(Number(doc.breakdown.netProfit),expected,'receipt detail profit');
 return doc;
}
async function run(){
 setup();
 await setPrices(floor);
 const legacy=await invoice(seller,salePayload(seller));
 await checkClosed(seller,legacy.id,455000-productCost);
 await rpc(seller,'solar_profit_basis_users',{action:'state'},403);
 const selected=await configure(true);
 const again=await rpc('admin','solar_profit_basis_users',selected.request);
 assert.equal(again.users.find(u=>u.id===seller)?.enabled,true);
 const ordinary=await invoice(standard,salePayload(standard));
 await checkClosed(standard,ordinary.id,455000-productCost);
 const mixed=await invoice(seller,salePayload(seller,true),true);
 const sales=1060000,personalCost=2*floor+hiddenCost,trueCost=2*productCost+hiddenCost;
 const mixedNet=sales-personalCost-2000;
 const mixedDetail=await checkClosed(seller,mixed.id,mixedNet);
 noCosts(mixedDetail,'personal profit detail');
 assert.equal(Number(resultFor(await userProfit(seller),legacy.id).value),455000-productCost,'historical receipt retroactively repriced');
 const source=sql('select total||\',\'||cost||\',\'||profit from public.transactions where id='+mixed.id).split(',').map(Number);
 assert.deepEqual(source,[sales,trueCost,sales-trueCost-2000],'company economics overwritten by personal basis');
 const policy=await rpc(seller,'solar_wholesale_pricing',{action:'state'});
 noCosts(policy,'pricing dashboard');
 const allStock=await rpc(seller,'solar_inventory',{action:'catalog'});
 noCosts(allStock,'material picker and catalog');
 const historical=await rpc(seller,'solar_sales_history_by_user',{owner_id:seller,search_text:customer,sale_kind:'sale',include_assigned:true,date_from:null,date_to:null,job_status:null,page_offset:0});
 noCosts(historical,'sales history');
 assert.ok(historical.rows.some(r=>String(r.id)===String(mixed.id)),'seller lost their receipt from protected archive');
 const document=await rpc(seller,'solar_statement_sale_for_edit',{customer_id:sample,movement_id:mixed.id});
 noCosts(document,'statement editor');
 assert.equal(Number(document.id??document.invoice?.id),mixed.id,'legitimate seller cannot edit own receipt from account');
 const deletion=await rpc(seller,'solar_receipt_delete_requests',{action:'context',payload:{invoiceId:mixed.id}});
 assert.ok(deletion.token);noCosts(deletion,'deletion dialog');
 const resumed=await rpc(seller,'solar_invoice_attempt_resolve',mixed.request);
 assert.equal(resumed.state,'saved');noCosts(resumed,'recovered invoice');
 const snapshots=await rpc(seller,'solar_personal_receipt_snapshot',{after_id:mixed.id-1,kinds:['sale']});
 const snapshot=snapshots.find(row=>Number(row.header.id)===mixed.id);assert.ok(snapshot);noCosts(snapshot,'receipt summary');
 const search=await rpc(seller,'solar_quick_search',{term:enabledName,category:'products'});
 assert.equal(Number(search.products.find(p=>Number(p.id)===enabledProduct)?.cost),floor);noCosts(search,'product search');
 const hidden=await rpc(seller,'solar_quick_search',{term:hiddenName,category:'products'});
 assert.equal(hidden.products.find(p=>Number(p.id)===hiddenProduct)?.cost,null);noCosts(hidden,'fallback product search');
 const visibility=await assertBlockedRaw(mixed);
 const beforeCash=cash(seller);
 const system=await invoice(seller,{kind:'system',mode:'credit',partyId:sample+1,party:receiverCustomer,warehouseId:1,installerId:engineer,customerAddress:'عنوان اختبار الأساس',total:810000,items:[{id:enabledProduct,qty:1,price:0},{id:hiddenProduct,qty:1,price:0}]},true);
 const pending=await rpc(seller,'solar_pending_systems',{});
 const pendingInvoice=[...pending.rows,...(pending.assignedRows||[])].find(x=>Number(x.id)===system.id);
 assert.equal(Number(pendingInvoice?.provisionalProfit),810000-floor-hiddenCost);
 noCosts(pendingInvoice,'pending system');
 assert.equal(resultFor(await userProfit(seller),system.id),undefined);
 sql("update public.transactions set warehouse_status='ready' where id="+system.id);
 await event(engineer,system.id,0,'start');
 await event(engineer,system.id,1,'complete',{notes:'تم تنصيب منظومة الاختبار',checks:{materials:true,tested:true,handover:true},expenses:[]});
 await event(seller,system.id,2,'close',{amount:25000});
 const systemNet=810000-floor-hiddenCost-25000;
 const systemDoc=await checkClosed(seller,system.id,systemNet);
 noCosts(systemDoc,'system profit detail');
 assert.equal(cash(seller),beforeCash-25000);
 assert.equal(Number(sql('select profit from public.transactions where id='+system.id)),810000-productCost-hiddenCost-25000);
 await setPrices(440000);
 await checkClosed(seller,mixed.id,mixedNet);
 await checkClosed(seller,system.id,systemNet);
 const next=await invoice(seller,salePayload(seller),true);
 await checkClosed(seller,next.id,15000);
 const {page:app,ctx:staffContext}=await h.open(seller,'/?section=profit&profitTab=settlements');
 const movement=app.locator('details.profitMovement').filter({has:app.locator('summary').filter({hasText:'#'+system.no})}).first();
 await movement.locator('summary').click();
 await movement.locator('[data-profit-component="net"]').waitFor();
 const screen=await movement.innerText();noCosts(screen,'personal visible profit');
 assert.ok(screen.replaceAll(',','').includes(String(systemNet)),'system personal net not displayed');
 await h.layout(app,'selected-account-profit',movement);
 const ledger=await rpc('admin','solar_profit_workspace',{action:'balance',payload:{ownerId:seller}});
 const personalEarned=(455000-productCost)+mixedNet+systemNet+15000;
 const companyEarned=2*(455000-productCost)+source[2]+(810000-productCost-hiddenCost-25000);
 assert.deepEqual(ledger.comparison,{companyEarned,personalEarned});
 const companyLabel='الربح على كلفة الشركة',personalLabel='ربح المستخدم المعتمد للتقسيم';
 const money=(value)=>Number(String(value).replace(/[^0-9.-]/g,''));
 assert.equal(money(await app.getByTestId('staff-profit-current-balance').innerText()),personalEarned);
 const staffReport=app.locator('section.uiPanel').filter({has:app.getByRole('heading',{name:/^كشف أرباح /})}).locator('.reportExport').first();
 await h.report(app,staffContext,staffReport,'personal-margin');
 const staffDoc=await app.evaluate(()=>window.__documentHtmls.find(html=>html.includes('كشف أرباح المستخدم')));
 assert.ok(staffDoc,'missing personal printable report');
 const searchable=(doc)=>doc.replace(/<[^>]*>/g,' ').replaceAll(',','');
 assert.ok(searchable(staffDoc).includes(String(personalEarned)),'personal PDF omits earned total');
 assert.ok(!searchable(staffDoc).includes(String(companyEarned))&&!staffDoc.includes(companyLabel),'staff PDF includes company margin');
 noCosts(staffDoc,'staff printable report');
 const {page:adminApp,ctx:adminCtx}=await h.open('admin','/?section=profit');
 const workspace=adminApp.locator('.companyProfit');
 await workspace.getByLabel('مستخدم تقرير الأرباح',{exact:true}).selectOption(seller);
 const dual=(label)=>workspace.locator('.companyFigure').filter({has:adminApp.getByText(label,{exact:true})});
 await dual(companyLabel).locator('bdi').waitFor();
 assert.equal(money(await dual(companyLabel).locator('bdi').innerText()),companyEarned);
 assert.equal(money(await dual(personalLabel).locator('bdi').innerText()),personalEarned);
 await h.layout(adminApp,'admin-personal-margin',dual(companyLabel));
 await workspace.getByRole('button',{name:'تصدير التقرير',exact:true}).click();
 await h.report(adminApp,adminCtx,workspace.locator('.reportExport'),'company-vs-personal-margin');
 const adminDoc=await adminApp.evaluate(()=>window.__documentHtmls.findLast(html=>html.includes('الربح على كلفة الشركة')));
 assert.ok(adminDoc?.includes(personalLabel),'admin printable report lacks labeled comparison');
 assert.ok(searchable(adminDoc).includes(String(companyEarned))&&searchable(adminDoc).includes(String(personalEarned)),'admin printable totals do not agree with ledger');
 h.checks.exportedProfit={companyEarned,personalEarned,staffContainsOnlyOwnMargin:true,adminContainsBothMargins:true};
 await configure(false);
 const frozenArchive=await rpc(seller,'solar_sales_history_by_user',{owner_id:seller,search_text:customer,sale_kind:'sale',include_assigned:true,date_from:null,date_to:null,job_status:null,page_offset:0});
 const frozenReceipt=frozenArchive.rows.find(row=>Number(row.id)===mixed.id);assert.ok(frozenReceipt);noCosts(frozenReceipt,'prior personal receipt archive after disabling');
 const frozenEditor=await rpc(seller,'solar_statement_sale_for_edit',{customer_id:sample,movement_id:mixed.id});
 noCosts(frozenEditor,'prior personal receipt editor after disabling');
 const oldDeletion=await rpc(seller,'solar_receipt_delete_requests',{action:'context',payload:{invoiceId:mixed.id}});
 assert.ok(oldDeletion.token);noCosts(oldDeletion,'prior personal receipt deletion dialog after disabling');
 const oldSnapshot=await rpc(seller,'solar_personal_receipt_snapshot',{after_id:mixed.id-1,kinds:['sale']});
 assert.ok(oldSnapshot.some(row=>Number(row.header.id)===mixed.id));
 noCosts(oldSnapshot.find(row=>Number(row.header.id)===mixed.id),'prior personal receipt in shared snapshot after disabling');
 const oldRaw=await rawRows('transaction_items',{select:'*',transaction_id:'eq.'+mixed.id});
 assert.equal(oldRaw.length,0,'raw line exposes prior protected receipt after disabling');
 await checkClosed(seller,mixed.id,mixedNet);
 await checkClosed(seller,system.id,systemNet);
 const after=await invoice(seller,salePayload(seller));
 await checkClosed(seller,after.id,455000-productCost);
 h.checks.pricingBasis={floor,personalWholesaleNet:mixedNet,companyWholesaleNet:source[2],personalSystemNet:systemNet,
  companySystemNet:810000-productCost-hiddenCost-25000,oldReceiptFrozen:true,newFloorUsedOnlyOnNextReceipt:true,uncheckedAffectsOnlyNew:true,
  singleCashExpense:25000,directData:visibility};
}
h=await createHarness('personal-pricing-basis');
try{await run();await h.finish();console.log('PASS verified independent marked/unmarked personal and company margins, protected reads, price and user changes, mobile and desktop');}
catch(e){await h.fail(e);throw e;}finally{await h.close();}
