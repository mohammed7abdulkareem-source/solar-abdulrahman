import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createHarness, rpc, sql} from './version4-browser-support.mjs';

const admin = randomUUID();
const clerk = randomUUID();
const buyer = randomUUID();
const ordinaryId = -Date.now();
const ordinaryName = 'مورد بيع تجريبي '+Math.abs(ordinaryId);
const protectedName = 'ABDULRAHMAN';
const protectedId = Number(sql("select id from suppliers where name='ABDULRAHMAN' limit 1")) || ordinaryId-1;
sql(`insert into profiles(id,display_name,phone,active,is_admin,user_type,permissions) values
 ('${admin}','مدير المورد التجريبي','07700000100',true,true,'admin_staff','{}'),
 ('${clerk}','عبدالرحمن التجريبي','07700000200',true,false,'admin_staff','{"supplierStatement":true,"supplierBalances":true,"supplierPayment":true,"suppliers":true,"purchase":true,"cash":true,"cashDeposit":true}'),
 ('${buyer}','موظف شراء تجريبي','07700000300',true,false,'admin_staff','{"purchase":true,"cash":true}');
 insert into suppliers(id,name,account_currency) values(${ordinaryId},'${ordinaryName}','IQD');
 insert into suppliers(id,name,account_currency) select ${protectedId},'${protectedName}','IQD' where not exists(select 1 from suppliers where id=${protectedId});`);

const {rate} = await rpc(clerk,'solar_exchange_rate_get',{});
const amount = {amount:3000,currency:'IQD',rate,accountRevision:0,mode:'charge_other',note:'رصيد تجريبي'};
const getStatement = (user,supplierId)=>rpc(user,'solar_fx',{action:'statement',payload:{supplierId}});
const namedBefore = (await getStatement(admin,protectedId)).balance;
for(const [user,supplierId,paymentId] of [[admin,protectedId,ordinaryId-2],[clerk,ordinaryId,ordinaryId-3]]) {
 await rpc(user,'solar_fx',{action:'payment',request_id:randomUUID(),payload:{...amount,supplierId,paymentId}});
 await rpc(user,'solar_cash_save',{request_id:randomUUID(),payload:{mode:'deposit',ownerId:user,currency:'IQD',amount:5000,note:'تمويل للاختبار'}});
}
const h = await createHarness('restricted-supplier');
const button = (page,label)=>page.getByRole('button',{name:label,exact:true});
const supplierPicker = page=>page.getByRole('combobox',{name:'ابحث عن المورد بالاسم أو الهاتف…',exact:true});
async function selectSupplier(page,picker,name) {
 await picker.fill(name);
 await page.getByRole('option').filter({has:page.getByText(name,{exact:true})}).click();
}
async function checkProtectedAbsent(page,picker) {
 await picker.fill(protectedName);
 await page.getByRole('listbox').waitFor();
 assert.equal(await page.getByRole('option').filter({has:page.getByText(protectedName,{exact:true})}).count(),0);
}
async function pay(user,supplierName,amount) {
 const {page}=await h.open(user,'/?section=supplierPayment');
 const picker=supplierPicker(page);
 if(user!==admin) await checkProtectedAbsent(page,picker);
 await selectSupplier(page,picker,supplierName);
 await page.getByLabel('مبلغ حركة المورد',{exact:true}).fill(String(amount));
 await button(page,'حفظ التسديد وخصمه من القاصة').click();
 await page.getByText('تم حفظ التسديد بنجاح',{exact:true}).waitFor();
 await button(page,'تعديل أو حذف هذا التسديد').click();
 await page.getByLabel('مبلغ تعديل تسديد المورد',{exact:true}).waitFor();
}
try {
 const {page:statement}=await h.open(clerk,'/?section=supplierStatement');
 await checkProtectedAbsent(statement,supplierPicker(statement));
 await selectSupplier(statement,supplierPicker(statement),ordinaryName);
 await statement.locator('.miniMovementRow').first().waitFor();
 assert.equal(await button(statement,'تسديد جديد').count(),1);
 await pay(clerk,ordinaryName,700);
 const clerkAfter=await getStatement(clerk,ordinaryId);
 assert.equal(clerkAfter.balance,2300);
 assert.equal(clerkAfter.cashBalance,4300);
 // The ordinary supplier and the protected one use precisely the same RPC.
 // Filtering the selector alone cannot account for the rejected posting.
 await rpc(clerk,'solar_fx',{action:'payment',request_id:randomUUID(),payload:{...amount,supplierId:protectedId,paymentId:ordinaryId-4}},403);
 await rpc(clerk,'solar_fx',{action:'statement',payload:{supplierId:protectedId}},403);

 for(const section of ['supplierPayment','suppliers','supplierStatement','supplierBalances']) {
  const {page}=await h.open(buyer,'/?section='+section);
  await page.locator('.premiumDashboard').waitFor();
  assert.equal(await page.getByRole('link',{name:'كشف حساب مورد',exact:true}).count(),0);
 }
 const {page:purchase}=await h.open(buyer,'/?section=purchase');
 const picker=purchase.locator('.deskMeta').getByRole('combobox').first();
 await checkProtectedAbsent(purchase,picker);
 await selectSupplier(purchase,picker,ordinaryName);
 const product=sql("select name from products where btrim(coalesce(name,''))<>'' group by name having count(*)=1 order by min(id) limit 1");
 await purchase.getByLabel('طريقة الدفع',{exact:true}).selectOption('credit');
 await purchase.getByLabel('عملة الشراء',{exact:true}).selectOption('IQD');
 await purchase.getByLabel('البحث عن مادة',{exact:true}).fill(product);
 await button(purchase,'إضافة '+product).click();
 await purchase.getByLabel('الكمية — '+product,{exact:true}).fill('1');
 await purchase.getByLabel('سعر الشراء — '+product,{exact:true}).fill('800');
 const saved=purchase.waitForResponse(r=>r.url().includes('/rpc/solar_invoice_save')&&r.request().method()==='POST');
 await button(purchase,'حفظ الوصل').click();
 assert.ok((await saved).ok());
 assert.equal(Number(sql(`select count(*) from transactions where kind='purchase' and created_by='${buyer}' and party_id=${ordinaryId} and total=800`)),1);
 assert.ok(h.calls.some(c=>c.who===buyer && c.path==='/rest/v1/rpc/solar_purchase_suppliers'));
 assert.ok(!h.calls.some(c=>c.who===buyer && (c.path==='/rest/v1/suppliers'||c.body?.action==='account'||c.body?.action==='statement')));

 await pay(admin,protectedName,1100);
 const protectedAfter=await getStatement(admin,protectedId);
 assert.equal(protectedAfter.balance,namedBefore+1900);
 assert.equal(protectedAfter.cashBalance,3900);
 assert.equal((await getStatement(admin,ordinaryId)).balance,3100);
 for (const actor of [admin,clerk]) {
  assert.equal(h.calls.filter(c=>c.who===actor&&c.path==='/rest/v1/rpc/solar_fx'&&c.body?.action==='payment').length,1);
 }
 h.checks.ordinarySupplierPaymentAndStatement=true;
 h.checks.buyerCanCreateOrdinaryCreditPurchase=true;
 h.checks.protectedSupplierOnlyForAdmin=true;
 await h.finish();
 console.log('Admin and staff payments, scoped statements and a new credit purchase passed.');
} catch(error) {
 await h.fail(error);
 throw error;
} finally {
 await h.close();
}
