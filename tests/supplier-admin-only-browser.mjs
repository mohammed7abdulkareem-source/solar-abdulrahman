import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createHarness, rpc, sql} from './version4-browser-support.mjs';

const admin = randomUUID(), office = randomUUID(), buyer = randomUUID();
const supplierId = -Date.now(), name = 'مورد تجريبي ' + Math.abs(supplierId);
sql(`insert into profiles(id,display_name,phone,active,is_admin,user_type,permissions) values
 ('${admin}','مدير المورد التجريبي','07700000100',true,true,'admin_staff','{}'),
 ('${office}','موظف كشف المورد التجريبي','07700000200',true,true,'admin_staff','{}'),
 ('${buyer}','عبدالرحمن التجريبي','07700000300',true,false,'admin_staff','{"purchase":true,"cash":true}');
 insert into suppliers(id,name,account_currency) values(${supplierId},'${name}','IQD');`);
const adminPayment = {supplierId, amount:3000, currency:'IQD', rate:1450, accountRevision:0, mode:'charge_other', note:'رصيد تجريبي'};
await rpc(office,'solar_fx',{action:'payment',request_id:randomUUID(),payload:{...adminPayment,paymentId:supplierId-1}});
await rpc(admin,'solar_cash_save',{request_id:randomUUID(),payload:{mode:'deposit',ownerId:admin,currency:'IQD',amount:5000,note:'تمويل للاختبار'}});
sql(`update profiles set is_admin=false,permissions='{"supplierStatement":true,"supplierBalances":true,"supplierPayment":true,"suppliers":true,"purchase":true,"deletionRequests":true,"cash":true}' where id='${office}'`);

const h = await createHarness('supplier-admin-payments');
async function chooseSupplier(page) {
 const search=page.getByRole('combobox',{name:'ابحث عن المورد بالاسم أو الهاتف…',exact:true});
 await search.fill(name);
 await page.getByRole('option').filter({hasText:name}).click();
}
const button=(page,label)=>page.getByRole('button',{name:label,exact:true});

try {
 const {page:direct}=await h.open(office,'/?section=supplierPayment');
 await direct.locator('.premiumDashboard').waitFor();
 assert.equal(await direct.getByLabel('مبلغ حركة المورد').count(),0);
 assert.equal(await direct.getByRole('link',{name:'تسديد مورد',exact:true}).count(),0);

 const {page:statement}=await h.open(office,'/?section=supplierStatement');
 await chooseSupplier(statement);
 const row=statement.locator('.miniMovementRow').first();
 await row.waitFor();
 assert.equal(await button(statement,'تسديد جديد').count(),0);
 assert.equal(await button(statement,'تعديل البيانات').count(),0);
 assert.equal(await button(statement,'عملة الحساب').count(),0);
 if(await row.isEnabled()) {
  await row.click();
  await statement.locator('.miniDetail').waitFor();
  assert.equal(await button(statement,'تعديل الحركة').count(),0);
  assert.equal(await button(statement,'حذف التسديد').count(),0);
 }
 assert.ok(!h.calls.some(c=>c.who===office && c.body?.action==='payment'));

 for (const section of ['supplierPayment','suppliers','supplierStatement','supplierBalances']) {
  const {page:denied}=await h.open(buyer,'/?section='+section);
  await denied.locator('.premiumDashboard').waitFor();
  assert.equal(await denied.getByRole('link',{name:'كشف حساب مورد',exact:true}).count(),0);
 }
 const {page:purchase}=await h.open(buyer,'/?section=purchase');
 const picker=purchase.locator('.deskMeta').getByRole('combobox').first();
 await picker.fill(name);
 await purchase.getByRole('option').filter({hasText:name}).click();
 assert.equal(await picker.inputValue(),name);
 const product=sql("select name from products where btrim(coalesce(name,''))<>'' group by name having count(*)=1 order by min(id) limit 1");
 await purchase.getByLabel('طريقة الدفع',{exact:true}).selectOption('credit');
 await purchase.getByLabel('عملة الشراء',{exact:true}).selectOption('IQD');
 await purchase.getByLabel('البحث عن مادة',{exact:true}).fill(product);
 await button(purchase,'إضافة '+product).click();
 await purchase.getByLabel('الكمية — '+product,{exact:true}).fill('1');
 await purchase.getByLabel('سعر الشراء — '+product,{exact:true}).fill('800');
 const saved=purchase.waitForResponse(response=>response.url().includes('/rpc/solar_invoice_save')&&response.request().method()==='POST');
 await button(purchase,'حفظ الوصل').click();
 assert.ok((await saved).ok());
 assert.equal(Number(sql(`select count(*) from transactions where kind='purchase' and created_by='${buyer}' and party_id=${supplierId} and total=800`)),1);

 assert.ok(h.calls.some(c=>c.who===buyer && c.path==='/rest/v1/rpc/solar_purchase_suppliers'));
 assert.ok(!h.calls.some(c=>c.who===buyer && (c.path==='/rest/v1/suppliers'||c.body?.action==='account'||c.body?.action==='statement')));
 const {page}=await h.open(admin,'/?section=supplierPayment');
 await chooseSupplier(page);
 await page.getByLabel('مبلغ حركة المورد',{exact:true}).fill('700');
 await button(page,'حفظ التسديد وخصمه من القاصة').click();
 await page.getByText('تم حفظ التسديد بنجاح',{exact:true}).waitFor();
 const result=await rpc(admin,'solar_fx',{action:'statement',payload:{supplierId}});
 assert.equal(result.balance,3100);
 assert.equal(result.cashBalance,4300);
 assert.equal(h.calls.filter(c=>c.who===admin&&c.path==='/rest/v1/rpc/solar_fx'&&c.body?.action==='payment').length,1);
 await button(page,'تعديل أو حذف هذا التسديد').click();
 await page.getByLabel('مبلغ تعديل تسديد المورد',{exact:true}).waitFor();

 h.checks.readOnlySupplierStatement=true;
 h.checks.purchaseWithMinimalSupplierPicker=true;
 h.checks.adminPaymentAndManagement=true;
 await h.finish();
 console.log('Admin settlement saved once; staff direct link and statement actions are restricted.');
} catch(error) {
 await h.fail(error);
 throw error;
} finally { await h.close(); }
