// Run against a dedicated loopback copy of the fully migrated database.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

process.env.SOLAR_FIXTURE_DB ||= 'solar_v4118_transfer_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3250';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3251';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4118/transfer-browser';
const {db,ids,rpc,sql,cash,createHarness}=await import('./version4-browser-support.mjs');
assert.ok(['solar_v4118_transfer_browser','solar_v4118_transfer_final_browser'].includes(db));

const customerId=Date.now(), productId=customerId+1;
const customerName='زبون التحويل التجريبي '+customerId;
const oldOwner=ids.owner,newOwner=ids.foreign;
const savedPermissions=JSON.parse(sql(`select jsonb_object_agg(id,permissions) from profiles where id in ('${oldOwner}','${newOwner}')`));
const permissions={sale:true,customers:true,customerPayment:true,customerDebts:true,customerStatement:true,ownCustomers:true,wholesaleFreePricing:true};
const transfers='تحويل الزبون';
const button=(view,label)=>view.getByRole('button',{name:label,exact:true});
const statement=actor=>rpc(actor,'solar_customer_statement',{customer_id:customerId});
const sessionDate=new Date().toISOString().slice(0,10);
const containsCustomer=row=>Number(row.id)===customerId;
const ownersDebt=async actor=>(await rpc(actor,'solar_party_balances',{report_kind:'customers',as_of:sessionDate})).rows.find(containsCustomer);
const creator=id=>sql(`select created_by from transactions where id=${Number(id)}`);
const ownerOfCustomer=()=>sql(`select owner_id from customers where id=${customerId}`);
function financialSnapshot(){
 return sql(`with receipts as (select * from public.transactions where party_id=${customerId})
 select jsonb_build_object(
  'receipts',(select jsonb_agg(to_jsonb(t) order by id) from receipts t),
  'materials',(select jsonb_agg(to_jsonb(i) order by i.id) from public.transaction_items i join receipts t on t.id=i.transaction_id),
  'product',(select to_jsonb(p) from public.products p where p.id=${productId}),
  'warehouse',(select jsonb_agg(to_jsonb(s) order by s.warehouse_id) from solar_private.warehouse_stocks s where s.product_id=${productId}),
  'cashLedger',(select jsonb_agg(to_jsonb(l) order by l.transaction_id) from public.cash_ledger l join receipts t on t.id=l.transaction_id),
  'cashEntries',(select jsonb_agg(to_jsonb(e) order by e.id) from public.solar_cash_entries e join receipts t on t.id=e.job_id),
  'foreignCurrency',(select jsonb_agg(to_jsonb(f) order by f.id) from solar_private.wallet_fx_entries f join receipts t on t.id=f.transaction_id)
 )`);
}
function restorePermissions(){
 for(const [id,p] of Object.entries(savedPermissions))sql(`update profiles set permissions='${JSON.stringify(p)}'::jsonb where id='${id}'`);
}
async function saveSale(actor,qty){
 return rpc(actor,'solar_invoice_save',{request_id:randomUUID(),payload:{kind:'sale',mode:'credit',partyId:customerId,party:customerName,
  warehouseId:1,items:[{id:productId,qty,price:50000}]}});
}
async function savePayment(actor,amount){
 const c=await rpc(actor,'solar_customer_payment_context',{customer_id:customerId});
 return rpc(actor,'solar_customer_payment_save',{request_id:randomUUID(),payload:{customerId,mode:'payment',amount,notes:'',expectedToken:c.token}});
}
async function seed(){
 sql(`begin;
 update profiles set permissions=permissions||'${JSON.stringify(permissions)}'::jsonb where id in ('${oldOwner}','${newOwner}');
 insert into customers(id,name,owner_id,customer_type) values (${customerId},'${customerName}','${oldOwner}','wholesale');
 insert into products(id,code,name,category,qty,cost) values(${productId},'TR-${productId}','مادة تجريبية للتحويل ${productId}','ألواح',30,10000);
 insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(1,${productId},30)
  on conflict(warehouse_id,product_id) do update set qty=30;
 commit;`);
 return {sale:await saveSale(oldOwner,2),payment:await savePayment(oldOwner,30000),adminSale:await saveSale(ids.admin,1)};
}
async function openAccount(h,actor,viaDebtors=false){
 const {page}=await h.open(actor,'/?section='+(viaDebtors?'customerDebts':'customerStatement'));
 if(viaDebtors){
  await page.getByLabel('بحث الأرصدة',{exact:true}).fill(customerName);
  await button(page,'فتح كشف حساب '+customerName).click();
 }else{
  await page.getByRole('combobox',{name:'بحث عميل الكشف'}).fill(customerName);
  await page.getByRole('option',{name:new RegExp(customerName)}).click();
 }
 await page.getByRole('heading',{name:customerName,exact:true}).waitFor();
 return page;
}
async function beginTransfer(page){
 await button(page,transfers).click();
 const target=page.getByRole('dialog',{name:transfers,exact:true}).getByRole('combobox',{name:/المسؤول الجديد/});
 await target.selectOption(newOwner);
 await button(page,'مراجعة التحويل').click();
 return button(page,'تأكيد تحويل الزبون');
}
async function focusAndCheckOwner(page){
 const checked=page.waitForResponse(response=>{
  const url=new URL(response.url());
  return response.request().method()==='GET'&&url.pathname.endsWith('/rest/v1/customers')&&url.searchParams.get('id')==='eq.'+customerId;
 });
 await page.evaluate(()=>window.dispatchEvent(new Event('focus')));
 return checked;
}
async function preserveDraftOnFocus(page,field,value){
 await field.fill(value);
 await focusAndCheckOwner(page);
 await field.waitFor({state:'visible'});
 assert.equal((await field.inputValue()).replaceAll(',',''),value);
}
function assertHistoricalPrivacy(rows){
 const restricted=rows.filter(row=>row.receiptRestricted);
 assert.equal(restricted.length,3);
 assert.deepEqual(restricted.map(row=>Number(row.effect)).sort((a,b)=>a-b),[-30000,50000,100000]);
 for(const row of restricted){
  assert.match(row.id,/^restricted:/);
  for(const key of ['receiptNo','notes','creatorName','createdBy','canEditReceipt','canDeleteReceipt'])assert.ok(!(key in row),key);
 }
}
const h=await createHarness('customer-transfer');
try{
 const original=await seed(),oldCash=cash(oldOwner),newCash=cash(newOwner);
 const priorStatement=await statement(ids.admin);
 assert.equal(Number(priorStatement.balance),120000);
 assert.equal((await ownersDebt(oldOwner)).owner_id,oldOwner);
 assert.equal(await ownersDebt(newOwner),undefined);
 const oldView=await openAccount(h,oldOwner);
 assert.equal(await button(oldView,transfers).count(),0);
 await button(oldView,'تعديل وصل البيع').first().click();
 await preserveDraftOnFocus(oldView,oldView.getByLabel(/^الكمية — /),'7');
 await button(oldView,'إلغاء التعديل').click();
 await button(oldView,'تعديل وصل التسديد').first().click();
 await preserveDraftOnFocus(oldView,oldView.getByLabel('مبلغ تعديل التسديد',{exact:true}),'35000');
 await button(oldView,'رجوع إلى الكشف').click();
 await button(oldView,'تعديل اسم العميل').click();
 await preserveDraftOnFocus(oldView,oldView.getByLabel('اسم العميل الجديد',{exact:true}),customerName+' مسودة');
 h.checks.sameOwnerDraftsSurviveFocus=true;
 const oldPaymentView=(await h.open(oldOwner,'/?section=customerPayment')).page;
 await oldPaymentView.getByRole('combobox',{name:'بحث عميل الكشف'}).fill(customerName);
 await oldPaymentView.getByRole('option',{name:new RegExp(customerName)}).click();
 await oldPaymentView.getByTestId('system-account-balance').filter({hasText:'120,000'}).waitFor();
 await oldPaymentView.getByLabel('مبلغ حركة الجملة').fill('1234');
 const initialFingerprint=financialSnapshot();
 const record=await rpc(oldOwner,'solar_customer_get',{customer_id:customerId});
 assert.equal((await rpc(oldOwner,'solar_customer_transfer_targets',{},403)).code,'42501');
 assert.equal((await rpc(oldOwner,'solar_customer_save',{action:'transfer_owner',request_id:randomUUID(),payload:{id:customerId,ownerId:newOwner,token:record.token}},403)).code,'42501');
 assert.equal(ownerOfCustomer(),oldOwner);
 assert.equal(financialSnapshot(),initialFingerprint);
 h.checks.ownerCannotTransferFromStatementOrAPI=true;

 const adminPage=await openAccount(h,'admin',true);
 const targets=await rpc('admin','solar_customer_transfer_targets',{});
 const oldName=targets.find(target=>target.id===oldOwner).name,newName=targets.find(target=>target.id===newOwner).name;
 assert.ok(!targets.some(target=>target.id===ids.warehouse||target.id===ids.installer));
 const confirm=await beginTransfer(adminPage);
 const review=adminPage.getByRole('dialog',{name:transfers,exact:true});
 await review.waitFor();
 const summary=await review.innerText();
 assert.ok(summary.includes(oldName)&&summary.includes(newName)&&summary.includes('120,000'));
 assert.equal(ownerOfCustomer(),oldOwner);
 assert.equal(financialSnapshot(),initialFingerprint);
 await h.layout(adminPage,'confirm-transfer',confirm);
 const transferReply=adminPage.waitForResponse(r=>r.request().method()==='POST'&&new URL(r.url()).pathname.endsWith('/rpc/solar_customer_save')&&r.request().postDataJSON()?.action==='transfer_owner');
 await confirm.click();
 const result=await transferReply;
 assert.equal(result.status(),200);
 assert.equal((await result.json()).ownerId,newOwner);
 await adminPage.getByRole('status').filter({hasText:/تم تحويل الزبون/}).first().waitFor();
 await adminPage.locator('.customerAccountHero').filter({hasText:newName}).waitFor();
 await adminPage.locator('[data-testid="customer-current-balance"][data-balance="120000"]').waitFor();
 await h.layout(adminPage,'transferred-account',adminPage.getByRole('heading',{name:customerName,exact:true}));
 assert.equal(ownerOfCustomer(),newOwner);
 assert.equal(financialSnapshot(),initialFingerprint);
 assert.equal(cash(oldOwner),oldCash);
 assert.equal(cash(newOwner),newCash);
 assert.equal(creator(original.sale.id),oldOwner);
 assert.equal(creator(original.payment.id),oldOwner);
 assert.equal(creator(original.adminSale.id),ids.admin);
 h.checks.financialDataPreserved={balance:120000,receiptsMaterialsStockAndFinancialEntriesUnchanged:true,creatorsAndBothWalletsUnchanged:true};

 assert.equal(await ownersDebt(oldOwner),undefined);
 const currentDebt=await ownersDebt(newOwner);
 assert.equal(currentDebt.owner_id,newOwner);
 assert.equal(Number(currentDebt.balance),120000);
 assert.ok(!(await rpc(oldOwner,'solar_statement_customers',{})).some(containsCustomer));
 assert.equal((await rpc(oldOwner,'solar_customer_statement',{customer_id:customerId},403)).code,'42501');
 h.setIntercept(async({route,call,response})=>{
  if(call.who===oldOwner&&['/rest/v1/rpc/solar_customer_statement','/rest/v1/rpc/solar_customer_payment_save'].includes(call.path)&&response.status()===403){
   await route.fulfill({response});return true;
  }
  return false;
 });
 await focusAndCheckOwner(oldView);
 await oldView.getByRole('combobox',{name:'بحث عميل الكشف'}).waitFor();
 assert.equal(await oldView.getByRole('heading',{name:customerName,exact:true}).count(),0);
 assert.equal(await oldView.getByTestId('customer-current-balance').count(),0);
 const deniedPayment=oldPaymentView.waitForResponse(r=>r.request().method()==='POST'&&new URL(r.url()).pathname.endsWith('/rpc/solar_customer_payment_save'));
 await button(oldPaymentView,'حفظ التسديد').click();
 assert.equal((await deniedPayment).status(),403);
 await oldPaymentView.getByTestId('system-account-balance').waitFor({state:'detached'});
 assert.equal(await oldPaymentView.getByTestId('system-projected-balance').count(),0);
 const paymentPicker=oldPaymentView.getByRole('combobox',{name:'بحث عميل الكشف'});
 await paymentPicker.fill(customerName);
 await oldPaymentView.getByRole('listbox').waitFor();
 assert.equal(await oldPaymentView.getByRole('option',{name:new RegExp(customerName)}).count(),0);
 assert.equal(financialSnapshot(),initialFingerprint);
 assert.equal(cash(oldOwner),oldCash);
 h.checks.preopenedPaymentDeniedAndCleared=true;
 h.setIntercept(null);
 const stalePicker=oldView.getByRole('combobox',{name:'بحث عميل الكشف'});
 await stalePicker.fill(customerName);
 await oldView.getByRole('listbox').waitFor();
 assert.equal(await oldView.getByRole('option',{name:new RegExp(customerName)}).count(),0);
 await oldView.reload();
 const picker=oldView.getByRole('combobox',{name:'بحث عميل الكشف'});
 await picker.fill(customerName);
 await oldView.getByRole('listbox').waitFor();
 assert.equal(await oldView.getByRole('option',{name:new RegExp(customerName)}).count(),0);
 const newView=await openAccount(h,newOwner);
 assert.equal(await button(newView,transfers).count(),0);
 assertHistoricalPrivacy((await statement(newOwner)).rows);
 await newView.locator('[data-testid="customer-current-balance"][data-balance="120000"]').waitFor();
 assert.equal(await newView.locator('.miniMovementRow:disabled').count(),3);
 assert.equal(await newView.getByRole('button',{name:/تعديل وصل|حذف وصل/}).count(),0);
 h.checks.transferVisibility={oldOwnerDirectoryAndDebtorsCleared:true,newOwnerSeesThreeBalanceOnlyRows:true};

 const newSale=await saveSale(newOwner,1),newPayment=await savePayment(newOwner,15000);
 const after=await statement(newOwner);
 assert.equal(Number(after.balance),155000);
 assert.equal((await ownersDebt(newOwner)).balance,155000);
 assert.equal(creator(newSale.id),newOwner);
 assert.equal(creator(newPayment.id),newOwner);
 assert.equal(cash(newOwner)-newCash,15000);
 assert.equal(cash(oldOwner),oldCash);
 assertHistoricalPrivacy(after.rows);
 assert.deepEqual(after.rows.filter(row=>!row.receiptRestricted).map(row=>row.id).sort(),[newSale.id,newPayment.id].sort());
 await button(newView,'تحديث الحساب').click();
 await newView.locator('[data-testid="customer-current-balance"][data-balance="155000"]').waitFor();
 assert.equal(await newView.locator('.miniMovementRow:enabled').count(),2);
 await h.layout(newView,'new-owner-statement',newView.locator('.miniMovementList'));
 h.checks.newBusiness={newSale:50000,newCashReceipt:15000,receivable:155000,originalWalletUnchanged:true};
 await h.finish();
 console.log('PASS administrator transfer, ownership, historical accounting and future business');
}catch(error){await h.fail(error);throw error;}
finally{restorePermissions();await h.close();}
