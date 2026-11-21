// A transferred system with a saved material rate differs from today's catalog price.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4124_delegated_profit_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3320';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3321';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4124/final-browser';
const {db,ids,sql,scalar,cash,rpc,createHarness}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4124_delegated_profit_browser');
const source=randomUUID(),receiver=randomUUID(),field=randomUUID(),peer=randomUUID();
const id=Date.now(),party='زبون كشف الكلفة '+id;
const button=(p,name)=>p.getByRole('button',{name,exact:true});
const state=revision=>({job_id:job.id,expected_revision:revision});
const act=(who,revision,action,payload={})=>rpc(who,'solar_installation_action',{...state(revision),action,payload},204);
const result=(who)=>rpc(who,'solar_profit_workspace',{action:'overview',payload:{ownerId:who}});
const detail=(who,owner=who)=>rpc(who,'solar_profit_detail',{owner_id:owner,source_key:'tx:'+job.id});
const pending=who=>rpc(who,'solar_pending_systems',{owner_id:who,date_from:null,date_to:null});
let job;
async function create(){
 const permission=JSON.stringify({system:true,installations:true,customers:true,customerStatement:true,profit:true,profitSettlement:true});
 for(const [uid,label,role] of [[source,'صاحب البيع','admin_staff'],[receiver,'مستلم الملف','admin_staff'],[peer,'مسؤول مستقل','admin_staff'],[field,'مهندس التنفيذ','installer']]){
  sql(`insert into public.profiles(id,display_name,username,user_type,is_admin,active,phone,permissions)
  values('${uid}','${label} ${id}','dp_${uid}','${role}',false,true,'07700000000','${role==='installer'?'{}':permission}'::jsonb)`);
 }
 sql(`begin;insert into public.customers(id,name,owner_id,customer_type) values(${id},'${party}','${source}','system');
 insert into public.products(id,code,name,qty,cost) values(${id},'DP-A-${id}','لوح أول ${id}',20,120000),(${id+1},'DP-B-${id}','بطارية ثانية ${id}',20,80000);
 insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(1,${id},20),(1,${id+1},20) on conflict(warehouse_id,product_id) do update set qty=excluded.qty;commit;`);
 const r=await rpc(source,'solar_invoice_save',{request_id:randomUUID(),payload:{kind:'system',mode:'credit',partyId:id,party,total:1295000,
  customerAddress:'عنوان تجريبي',installerId:field,warehouseId:1,items:[{id,qty:3,price:0},{id:id+1,qty:2,price:0}]}});
 job={id:Number(r.id),receiptNo:scalar('select receipt_no from transactions where id='+Number(r.id))};
 sql("update public.transactions set warehouse_status='ready' where id="+job.id);
 sql('update public.products set cost=990000 where id in ('+id+','+(id+1)+')');
 await act(field,0,'start');await act(field,1,'complete',{checks:{materials:true,tested:true,handover:true},notes:'تم فحص المنظومة',expenses:[]});
 await act(source,2,'close',{amount:60000});
}
async function assignFinancially(owner){
 const params={invoiceIds:[job.id],ownerId:owner,note:'التحويل المالي التجريبي'};
 const view=await rpc(ids.admin,'solar_profit_transfer',{action:'preview',payload:params});
 const mutation={action:'apply',request_id:randomUUID(),payload:{...params,expectedToken:view.token}};
 await rpc(ids.admin,'solar_profit_transfer',mutation);
}
async function assignOperationally(owner){
 const [record,choices]=await Promise.all([
  rpc('admin','solar_customer_get',{customer_id:id}),rpc('admin','solar_customer_transfer_receipts',{customer_id:id})]);
 await rpc('admin','solar_customer_save',{action:'transfer_owner',request_id:randomUUID(),payload:{id,ownerId:owner,token:record.token,receiptToken:choices.receiptToken,receiptIds:[job.id]}});
}
async function component(container,key,want){
 const row=container.locator('[data-profit-component="'+key+'"]');
 await row.waitFor();
 const text=(await row.innerText()).replace(/[٬,]/g,'').replace(/\s+/g,' ');
 assert.ok(text.includes(String(want)),key+' expected '+want+', got '+text);
}
async function verifySheet(scope,expense,net){
 for(const [key,value] of Object.entries({sale:1295000,materials:520000,gross:775000,installation:expense,net}))await component(scope,key,value);
}
const h=await createHarness('delegated-production-cost');
try{
 await create();
 assert.equal(Number((await detail(source)).breakdown.grossProfit),775000);
 await assignFinancially(receiver);
 assert.equal(Number((await result(receiver)).available),715000);
 assert.equal((await detail(receiver)).breakdown,null);
 const money=[source,receiver,peer].map(cash);
 const stock=()=>sql('select jsonb_agg(to_jsonb(s) order by s.product_id) from solar_private.warehouse_stocks s where s.product_id in ('+id+','+(id+1)+')');
 const previousStock=stock();
 await assignOperationally(receiver);
 const d=await detail(receiver);
 assert.equal(Number(d.breakdown.materialsCost),520000);
 assert.equal(Number(d.breakdown.netProfit),715000);
 assert.equal(Number(d.breakdown.profitAdjustment),0);
 assert.deepEqual(d.breakdown.items.map(x=>Number(x.unitCost)).sort((a,b)=>a-b),[80000,120000]);
 assert.deepEqual([source,receiver,peer].map(cash),money);
 assert.equal(stock(),previousStock);
 const user=(await h.open(receiver,'/?section=profit')).page;
 const receipt=page=>page.locator('details.profitMovement').filter({has:page.locator('summary[aria-label="تفاصيل الوصل '+job.receiptNo+'"]')});
 let movement=receipt(user);
 await movement.locator('summary').click();
 await verifySheet(movement,60000,715000);
 assert.ok(!(await movement.innerText()).includes('تعديلات ربح الفاتورة المحفوظة'));
 await h.layout(user,'posted-receipt-profit',movement);
 const office=(await h.open(receiver,'/?section=installations')).page;
 await button(office,'الكل').click();
 const managed=office.locator('[data-job-id="'+job.id+'"]');
 const officeSheet=managed.locator('.installationFinancials');
 await officeSheet.waitFor();
 for(const value of ['1,295,000','520,000','775,000','60,000','715,000'])assert.ok((await officeSheet.innerText()).includes(value),value);
 await h.layout(office,'authorized-installation-profit',officeSheet);
 const engineer=(await h.open(field,'/?section=installations')).page;
 await engineer.locator('[data-agenda-filter="all"]').click();
 await engineer.locator('[data-job-id="'+job.id+'"]').waitFor();
 assert.equal(await engineer.locator('.installationFinancials').count(),0);
 const engineerJob=(await rpc(field,'solar_installation_jobs',{})).find(j=>+j.id===job.id);
 for(const key of ['total','cost','expenses','sellingPrice','installationExpenses'])assert.ok(!(key in engineerJob));
 await rpc(peer,'solar_profit_detail',{source_key:'tx:'+job.id,owner_id:peer},403);
 await button(managed,'إعادة فتح للمراجعة').click();
 await managed.getByLabel('المصاريف النهائية للمنظومة',{exact:true}).waitFor();
 assert.equal(Number((await result(receiver)).available),0);
 const statement=await pending(receiver);
 assert.equal(statement.assignedRows.length,1);
 assert.equal(Number(statement.summary.provisionalProfit),715000);
 const sellerPending=await pending(source);
 const sourceRow=sellerPending.rows.find(r=>+r.id===job.id);
 assert.equal(sourceRow.profitAttributedElsewhere,true);
 assert.equal(Number(sourceRow.provisionalProfit),0);
 assert.equal(Number(sourceRow.receiptProvisionalProfit),715000);
 const sellerView=(await h.open(source,'/?section=profit')).page;
 const sellerPortfolio=sellerView.getByRole('region',{name:'المنظومات غير المغلقة'});
 await sellerPortfolio.locator('summary').first().click();
 const sourceCard=sellerPortfolio.locator('[data-pending-receipt="'+job.id+'"]');
 await sourceCard.waitFor();
 assert.match(await sourceCard.innerText(),/حصة هذا الحساب من الربح غير النهائي/);
 assert.equal(await sourceCard.locator('[data-profit-component="contribution"] bdi').innerText(),'0');
 const draftOffice=managed.locator('.installationFinancials');
 await draftOffice.waitFor();
 assert.ok((await draftOffice.innerText()).includes('صافي الربح غير النهائي'));
 await h.layout(office,'provisional-installation-profit',draftOffice);
 const closedPage=(await h.open(receiver,'/?section=profit')).page;
 const portfolio=closedPage.getByRole('region',{name:'المنظومات غير المغلقة'});
 await portfolio.locator('summary').first().click();
 const draft=portfolio.locator('[data-pending-receipt="'+job.id+'"]');
 await verifySheet(draft,60000,715000);
 await h.layout(closedPage,'pending-receipt-cost',draft);
 assert.equal(await receipt(closedPage).count(),0);
 await managed.getByLabel('المصاريف النهائية للمنظومة',{exact:true}).fill('75000');
 assert.ok((await managed.locator('.approvalForm').innerText()).includes('700,000'));
 await button(managed,'اعتماد المصاريف وإغلاق الملف').click();
 await office.locator('.installationActionToast').getByText('تم الغلق',{exact:true}).waitFor();
 assert.equal(Number((await result(receiver)).available),700000);
 assert.equal(Number((await result(source)).available),0);
 const latest=await detail(receiver);
 assert.equal(Number(latest.breakdown.installationExpenses),75000);
 assert.equal(Number(latest.breakdown.netProfit),700000);
 assert.equal(Number(latest.breakdown.profitAdjustment),0);
 assert.equal(cash(source),money[0]);
 assert.equal(cash(receiver),money[1]-15000);
 assert.equal(stock(),previousStock);
 assert.equal(sql('select created_by from transactions where id='+job.id),source);
 assert.ok(!(await pending(receiver)).assignedRows.length);
 await closedPage.reload();
 movement=receipt(closedPage);
 await movement.locator('summary').click();
 await verifySheet(movement,75000,700000);
 h.checks.delegatedProfit={historicalCosts:[120000,80000],catalogCostNow:990000,sale:1295000,materialCost:520000,
  gross:775000,firstApprovedExpense:60000,firstNet:715000,correctedExpense:75000,correctionToCash:15000,finalNet:700000,
  pendingNotPosted:true,restrictedWithOneAssignment:true,unrelatedEmployeeAndEngineerProtected:true};
 await h.finish();
 console.log('PASS delegated closed/open profit, saved material costs, corrected expenses once and role protection');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
