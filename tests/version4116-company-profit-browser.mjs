// Read the same posted records through the profit RPC and the responsive report.
import assert from 'node:assert/strict';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4116_activity_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3224';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3225';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4116/company-browser';
const {createHarness,rpc,fingerprint}=await import('./version4-browser-support.mjs');

const h=await createHarness('company-profit');
const readBalance=type=>rpc('admin','solar_profit_workspace',{action:'balance',payload:{ownerId:'all',from:'',to:'',type}});
async function expectMoney(page,testId,value){
 await page.waitForFunction(({testId,value})=>{
  const text=document.querySelector('[data-testid="'+testId+'"] bdi')?.textContent||'';
  return /[0-9]/.test(text)&&Number(text.replace(/[^\d.-]/g,''))===Number(Number(value).toFixed(2));
 },{testId,value});
}
try{
 const before=fingerprint();
 const company=await readBalance('all');
 const systems=await readBalance('system');
 const {page,ctx}=await h.open('admin','/?section=profit');
 const workspace=page.locator('.companyProfit');
 const sections=workspace.getByRole('navigation',{name:'أقسام تقرير أرباح الشركة'});
 const selectTab=async name=>{
  const tab=sections.getByRole('button',{name,exact:true});
  await tab.click();
  assert.equal(await tab.getAttribute('aria-pressed'),'true');
 };
 await expectMoney(page,'profit-current-balance',company.remaining);
 await expectMoney(page,'profit-period-earned',company.period.earned);
 await h.layout(page,'company-profit-overview',workspace);
 await selectTab('المبيعات والمنظومات');
 for(const kind of ['sale','system'])await workspace.locator('[data-profit-sale-kind="'+kind+'"]').waitFor();
 await workspace.getByLabel('نوع مبيعات تقرير الأرباح',{exact:true}).selectOption('system');
 await expectMoney(page,'profit-period-earned',systems.period.earned);
 await expectMoney(page,'profit-current-balance',company.remaining);
 await workspace.locator('[data-profit-sale-kind="system"]').waitFor();
 assert.equal(await workspace.locator('[data-profit-sale-kind="sale"]').count(),0);
 await selectTab('المصاريف والحركات');
 await h.layout(page,'company-profit-movements',sections);
 await selectTab('التسويات والتوزيع');
 await workspace.getByText('سحب أرباح الإدارة',{exact:true}).first().waitFor();
 await selectTab('تصدير التقرير');
 const actions=workspace.locator('.reportExport').first();
 const html=await h.report(page,ctx,actions,'company-period-report');
 assert.ok(html.includes('الربح حسب نوع البيع')&&html.includes('المنظومات المغلقة'));
 assert.ok(html.includes('الرصيد الحالي · جميع الفترات')&&html.includes('نتائج الفترة المختارة'));
 assert.equal(fingerprint(),before);
 h.checks.periodTotalsMatchPostedLedger=true;
 h.checks.readOnlyFinancialRecords=true;
 await h.finish();
 console.log('PASS company report navigation, profit ledger balances, filtered PDF, mobile and desktop');
}catch(error){
 await h.fail(error);
 throw error;
}finally{
 await h.close();
}
