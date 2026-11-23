import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createHarness, rpc, sql} from './version4-browser-support.mjs';

const manager = randomUUID(), seller = randomUUID(), expensesOnly = randomUUID();
sql(`insert into public.profiles(id,display_name,is_admin,user_type,active,permissions,phone) values
 ('${manager}','مدير اختبار الربح الخارجي',true,'admin_staff',true,'{}','07700000001'),
 ('${seller}','موظف اختبار الربح الخارجي',false,'admin_staff',true,'{"cash":true,"cashExpense":true,"cashExternalProfit":true,"profit":true,"profitSettlement":true}','07700000002'),
 ('${expensesOnly}','موظف اختبار المصروف',false,'admin_staff',true,'{"cash":true,"cashExpense":true}','07700000003')`);

const button = (root, name) => root.getByRole('button',{name,exact:true});
const box = () => rpc(seller,'solar_cash_workspace',{payload:{ownerId:seller}});
const report = (who, ownerId) => rpc(who,'solar_profit_workspace',{action:'balance',payload:{ownerId}});
const entryLabel = 'تسجيل ربح خارجي';
const value = 17325;
const note = 'أجرة خدمة خارج المنظومات';
const h = await createHarness('external-profit-shortcut');
try {
 const beforeBox = await box();
 const beforeCompany = await report(manager,'all');
 const {page} = await h.open(seller,'/?section=cash');
 await button(page,'تسجيل مصروف').waitFor();
 await button(page,entryLabel).click();

 const form = page.getByRole('region',{name:'إضافة حركة مالية'});
 assert.equal(await button(form,entryLabel).getAttribute('aria-pressed'),'true');
 assert.ok(await form.getByLabel('قاصة الحركة').isDisabled());
 assert.equal(await form.getByLabel('قاصة الحركة').inputValue(),seller);
 await form.getByLabel('مبلغ الحركة').fill(String(value));
 await form.getByLabel('بيان الحركة').fill(note);
 await button(form,'حفظ الحركة').click();
 await page.getByRole('heading',{name:'تم حفظ الحركة بنجاح',exact:true}).waitFor();
 const saves = h.calls.filter(call=>call.path.endsWith('/rpc/solar_cash_save'));
 assert.equal(saves.length,1);
 const posted = saves[0].body;
 assert.equal(posted.payload.mode,'external_profit');
 assert.equal(posted.payload.ownerId,seller);
 const receipt = await rpc(seller,'solar_cash_save',posted);
 assert.equal(receipt.profitAmountIQD,value);
 const afterBox = await box();
 assert.equal(afterBox.summary.IQD-beforeBox.summary.IQD,value);
 const movements = afterBox.rows.filter(row=>row.request_id===posted.request_id);
 assert.equal(movements.length,1);
 assert.equal(movements[0].delta,value);
 assert.equal(movements[0].note,note);
 const ownReport = await report(seller,seller), afterCompany = await report(manager,'all');
 assert.equal(ownReport.period.earned,value);
 assert.equal(Math.round((afterCompany.period.earned-beforeCompany.period.earned)*100),value*100);
 for (const result of [ownReport,afterCompany])
  assert.equal(result.rows.filter(row=>row.ownerId===seller&&row.kind==='external_profit'&&row.value===value).length,1);

 const {page:limited} = await h.open(expensesOnly,'/?section=cash');
 await button(limited,'تسجيل مصروف').click();
 const limitedForm = limited.getByRole('region',{name:'إضافة حركة مالية'});
 await limitedForm.getByLabel('قاصة الحركة').waitFor();
 assert.equal(await button(limited,entryLabel).count(),0);
 assert.equal(await button(limitedForm,'تسجيل مصروف').getAttribute('aria-pressed'),'true');

 const direct = await h.open(expensesOnly,'/?section=cash&cashView=entry&cashMode=external_profit');
 const locked = direct.page.getByRole('region',{name:'إضافة حركة مالية'});
 await locked.getByText('هذه الحركة غير متاحة', {exact:false}).waitFor();
 assert.equal(await button(locked,'حفظ الحركة').count(),0);
 assert.equal(await button(locked,entryLabel).count(),0);
 await button(locked,'تسجيل مصروف').click();
 await locked.getByLabel('مبلغ الحركة').waitFor();
 assert.equal(await locked.getByLabel('قاصة الحركة').inputValue(),expensesOnly);
 await h.finish();
 console.log('Own-box shortcut and receipt, exact cash and company/personal profit, replay, and expense-only visibility passed.');
} catch (error) {
 await h.fail(error);
 throw error;
} finally {
 await h.close();
}
