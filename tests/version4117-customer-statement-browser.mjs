// Exercise the account opened from the debtor directory using real, disposable ledger data.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

process.env.SOLAR_FIXTURE_DB ||= 'solar_v4117_statement_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3240';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3241';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4117/statement-browser';
const {db,ids,sql,rpc,scalar,cash,createHarness}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4117_statement_browser');

const run=Date.now(),wholesale=run,system=run+1,product=run+2;
const customerName='العميل التجريبي '+run,systemName='عميل منظومة تجريبي '+run;
const newName=customerName+' المعدل';
const owner=ids.owner,admin=ids.admin;
const originalPermissions=sql(`select permissions from profiles where id='${owner}'`);
const permissionPatch={sale:true,system:true,customerPayment:true,customers:true,customerDebts:true,customerStatement:true,systemPayment:true,wholesaleFreePricing:true,salesDeleteOwn:true,deletionRequests:true};
const stock=()=>scalar(`select qty from solar_private.warehouse_stocks where warehouse_id=1 and product_id=${product}`);
const movement=id=>JSON.parse(sql(`select coalesce((select to_jsonb(t) from transactions t where id=${Number(id)}),'null'::jsonb)`));
const balance=async id=>Number((await rpc(owner,'solar_customer_statement',{customer_id:id})).balance);
const saveSale=(actor,partyId,party,kind,qty)=>rpc(actor,'solar_invoice_save',{request_id:randomUUID(),payload:{kind,mode:'credit',partyId,party,warehouseId:1,...(kind==='system'?{total:300000,customerAddress:'عنوان تجريبي',installerId:ids.installer}:{}),items:[{id:product,qty,price:kind==='system'?0:50000}]}});
async function savePayment(actor,customerId,invoiceId,value){
 const prefix=invoiceId?'solar_system_payment':'solar_customer_payment';
 const state=await rpc(actor,prefix+'_context',{customer_id:customerId});
 return rpc(actor,prefix+'_save',{request_id:randomUUID(),payload:{customerId,invoiceId,amount:value,mode:'payment',notes:'',expectedToken:state.token}});
}
async function seed(){
 sql(`begin;
 update profiles set permissions=permissions || '${JSON.stringify(permissionPatch)}'::jsonb where id='${owner}';
 insert into customers(id,name,customer_type,owner_id) values (${wholesale},'${customerName}','wholesale','${owner}'),(${system},'${systemName}','system','${owner}');
 insert into products(id,code,name,category,qty,cost) values (${product},'ST-${run}','مادة اختبار الكشف ${run}','ألواح',40,10000);
 insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(1,${product},40) on conflict(warehouse_id,product_id) do update set qty=40;
 commit;`);
 const sale=await saveSale(owner,wholesale,customerName,'sale',2);
 const hiddenSale=await saveSale(admin,wholesale,customerName,'sale',1);
 const job=await saveSale(owner,system,systemName,'system',1);
 const payment=await savePayment(owner,wholesale,null,25000);
 const deposit=await savePayment(owner,system,job.id,40000);
 return {sale,hiddenSale,job,payment,deposit};
}
const restoreOwner=()=>sql(`update profiles set permissions='${originalPermissions}'::jsonb where id='${owner}'`);

const button=(surface,name)=>surface.getByRole('button',{name,exact:true});
const editSale='تعديل وصل البيع',deleteSale='حذف وصل البيع';
const editPayment='تعديل وصل التسديد',deletePayment='حذف وصل التسديد';
const rename='تعديل اسم العميل';
async function openAccount(h,actor,name,fromDebtors=false){
 const {page}=await h.open(actor,'/?section='+(fromDebtors?'customerDebts':'customerStatement'));
 if(fromDebtors){
  await page.getByLabel('بحث الأرصدة',{exact:true}).fill(name);
  await button(page,'فتح كشف حساب '+name).click();
 }else{
  await page.getByRole('combobox',{name:'بحث عميل الكشف'}).fill(name);
  await page.getByRole('option',{name:new RegExp(name)}).click();
 }
 await page.getByRole('heading',{name,exact:true}).waitFor();
 return page;
}
async function checkBalance(page,customerId,expected){
 await page.locator('[data-testid="customer-current-balance"][data-balance="'+expected+'"]').waitFor();
 assert.equal(await balance(customerId),expected);
}
async function markAction(page,name,callback,expected){
 const incoming=page.waitForResponse(r=>
  r.request().method()==='POST' && new URL(r.url()).pathname.endsWith('/rpc/'+name) &&
  (!expected || expected(r.request().postDataJSON()))
 );
 await callback();
 const response=await incoming;
 assert.equal(response.status(),200,name+': '+(response.ok()?'':await response.text()));
}
async function updatePayment(page,customerId,value,remaining,expectedDelta){
 const oldCash=cash(owner);
 await button(page,editPayment).first().click();
 await page.getByLabel('مبلغ تعديل التسديد',{exact:true}).fill(String(value));
 await button(page,'حفظ تعديل التسديد').click();
 await checkBalance(page,customerId,remaining);
 assert.equal(cash(owner)-oldCash,expectedDelta);
}
async function requestDelete(page,receipt){
 await button(page,deletePayment).first().click();
 await markAction(page,'solar_receipt_delete_requests',()=>button(page,'إرسال طلب حذف التسديد').click(),body=>body.action==='request');
 await page.getByTestId('customer-current-balance').waitFor();
 assert.equal(sql(`select status from solar_private.receipt_delete_requests where invoice_id=${receipt.id} order by created_at desc limit 1`),'pending');
}
async function approve(page,receipt){
 const party=movement(receipt.id).party_name;
 const row=page.locator('.deletionRequestRow').filter({hasText:party}).filter({hasText:new RegExp('#'+receipt.receiptNo+'(?![0-9])')});
 await row.click();
 await markAction(page,'solar_receipt_delete_requests',()=>button(page,'موافقة وحذف الوصل').click(),body=>body.action==='approve');
 assert.equal(movement(receipt.id),null);
}
async function assertPrivate(h,page,customerId,hiddenSale){
 const state=await rpc(owner,'solar_customer_statement',{customer_id:customerId});
 const hidden=state.rows.filter(row=>row.receiptRestricted);
 assert.equal(hidden.length,1);
 assert.equal(Number(hidden[0].effect),50000);
 assert.ok(!('receiptNo' in hidden[0])&&!('notes' in hidden[0])&&!hidden[0].canEditReceipt&&!hidden[0].canDeleteReceipt);
 assert.notEqual(String(hidden[0].id),String(hiddenSale.id));
 const privateCard=page.locator('article').filter({has:page.locator('.miniMovementRow:disabled')}).last();
 await privateCard.waitFor();
 assert.equal(await privateCard.getByRole('button',{name:/تعديل وصل|حذف وصل/}).count(),0);
 assert.ok(!(await privateCard.innerText()).includes('#'+hiddenSale.receiptNo));
 h.checks.foreignReceipt='amount only; receipt number and actions absent';
}
const h=await createHarness('customer-statement-actions');
try{
 const {sale,hiddenSale,job,payment,deposit}=await seed(),cashBefore=cash(owner);
 assert.equal(stock(),36);
 const authorized=sql(`select permissions from profiles where id='${owner}'`);
 sql(`update profiles set permissions='{"customerStatement":true,"ownCustomers":true,"ownSales":true,"ownPayments":true}' where id='${owner}'`);
 const readonly=await openAccount(h,owner,systemName);
 await checkBalance(readonly,system,260000);
 assert.equal(await readonly.locator('article:has(.miniMovementRow)').count(),2);
 for(const action of[rename,editSale,deleteSale,editPayment,deletePayment])assert.equal(await button(readonly,action).count(),0,action);
 h.checks.statementOnly={viewBalance:true,viewOwnSaleAndPayment:true,canMutate:false};
 sql(`update profiles set permissions='${authorized}'::jsonb || '{"deletionRequests":false}'::jsonb where id='${owner}'`);
 const editorOnly=await openAccount(h,owner,systemName);
 assert.equal(await button(editorOnly,editPayment).count(),1);
 assert.equal(await button(editorOnly,deletePayment).count(),0);
 h.checks.paymentEditorWithoutDeletePermission=true;
 sql(`update profiles set permissions='${authorized}' where id='${owner}'`);
 const page=await openAccount(h,owner,customerName,true);
 await checkBalance(page,wholesale,125000);
 await assertPrivate(h,page,wholesale,hiddenSale);
 await h.layout(page,'debtor-statement-actions',button(page,rename));

 await button(page,rename).click();
 await page.getByLabel('اسم العميل الجديد',{exact:true}).fill(newName);
 await button(page,'حفظ الاسم').click();
 await page.getByRole('heading',{name:newName,exact:true}).waitFor();
 await checkBalance(page,wholesale,125000);
 assert.equal(cash(owner),cashBefore);
 assert.equal(movement(sale.id).party_id,wholesale);
 h.checks.rename={sameAccount:true,balance:125000,unchangedCash:true};

 await button(page,'كشف حساب').click();
 const table=page.locator('.customerStatementLedger');
 await table.waitFor();
 const ownRow=table.getByRole('row').filter({has:button(page,editSale)});
 assert.equal(await ownRow.count(),1);
 await h.layout(page,'statement-table-actions',ownRow);
 await button(ownRow,editSale).click();
 await page.getByLabel(/^الكمية — /).fill('3');
 await button(page,'حفظ التعديل').click();
 await checkBalance(page,wholesale,175000);
 assert.equal(stock(),35);
 assert.equal(Number(movement(sale.id).total),150000);
 assert.equal(Number(movement(sale.id).profit),120000);
 assert.equal(cash(owner),cashBefore);
 await table.waitFor();
 h.checks.wholesaleSaleEdit={sameReceipt:true,newQuantity:3,remaining:175000,stock:35,profit:120000,tableRestored:true};

 await updatePayment(page,wholesale,35000,165000,10000);
 assert.equal(Number(movement(payment.id).total),35000);
 await table.waitFor();
 await requestDelete(page,payment);
 await checkBalance(page,wholesale,165000);
 assert.equal(cash(owner),cashBefore+10000);
 await markAction(page,'solar_receipt_delete_requests',()=>button(table,deleteSale).click(),body=>body.action==='request');
 await checkBalance(page,wholesale,165000);
 const approvals=(await h.open('admin','/?section=deletionRequests')).page;
 await approve(approvals,sale);
 assert.equal(await balance(wholesale),15000);
 assert.equal(stock(),38);
 assert.equal(movement(sale.id),null);
 h.checks.wholesaleDelete={stockRestored:38,balance:15000,creditSaleDidNotChangeCash:true};

 const systems=await openAccount(h,owner,systemName);
 await systems.setViewportSize({width:390,height:915});
 await checkBalance(systems,system,260000);
 await button(systems,'مبيعات').click();
 await button(systems,editSale).first().click();
 await systems.getByLabel('تعديل سعر بيع المنظومة',{exact:true}).fill('340000');
 await button(systems,'حفظ التعديل').click();
 await checkBalance(systems,system,300000);
 assert.equal(Number(movement(job.id).total),340000);
 await button(systems,'تسديدات').click();
 await updatePayment(systems,system,50000,290000,10000);
 assert.equal(Number(movement(deposit.id).system_invoice_id),Number(job.id));
 await requestDelete(systems,deposit);
 await checkBalance(systems,system,290000);
 assert.equal(cash(owner),cashBefore+20000);

 await button(approvals,'تحديث').click();
 await approve(approvals,deposit);
 assert.equal(await balance(system),340000);
 assert.equal(cash(owner),cashBefore-30000);
 await approve(approvals,payment);
 assert.equal(await balance(wholesale),50000);
 assert.equal(cash(owner),cashBefore-65000);
 h.checks.payments={wholesaleAndSystemEdited:true,linkedInvoicePreserved:true,deletionPendingBeforeApproval:true,approvedPaymentsRemoved:true,cashReversed:85000};

 const direct=await saveSale(owner,wholesale,newName,'sale',2);
 const fresh=await openAccount(h,owner,newName);
 await checkBalance(fresh,wholesale,150000);
 await markAction(fresh,'solar_receipt_delete_requests',()=>button(fresh,deleteSale).first().click(),body=>body.action==='delete_direct');
 await checkBalance(fresh,wholesale,50000);
 assert.equal(movement(direct.id),null);
 assert.equal(stock(),38);
 assert.equal(cash(owner),cashBefore-65000);
 h.checks.unpreparedSaleDeletedDirectly=true;

 const adminStatement=await openAccount(h,'admin',systemName);
 await button(adminStatement,'مبيعات').click();
 await adminStatement.locator('.miniMovementRow').first().click();
 await button(adminStatement,editSale).waitFor();
 await h.layout(adminStatement,'system-receipt-detail',button(adminStatement,deleteSale));
 await markAction(adminStatement,'solar_receipt_delete_requests',()=>button(adminStatement,deleteSale).click(),body=>body.action==='request');
 assert.equal(await balance(system),340000);
 await button(approvals,'تحديث').click();
 await approve(approvals,job);
 assert.equal(await balance(system),0);
 assert.equal(stock(),39);
 assert.equal(cash(owner),cashBefore-65000);
 h.checks.systemSaleDeleteFromDetail={stockRestored:true,customerBalance:0};
 await h.finish();
 console.log('PASS customer statement actions (real PostgREST and Chromium)');
}catch(error){await h.fail(error);throw error;}
finally{restoreOwner();await h.close();}
