// Dedicated local database and loopback PostgREST. No production requests.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4113_restricted_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3185';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4113/restricted-account-browser';
const {db,base,ids,sql,createHarness,rpc,fingerprint}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4113_restricted_browser');

const owner=randomUUID(), limited=randomUUID(), certificate=randomUUID(), invoice=Date.now();
const party='زبون شهادة الاختبار',marker='تنبيه خاص بالمالية',announcement='رسالة عامة للاختبار';
const permissions={tahseel:true,tahseelFull:true,ownSales:true,ownCustomers:true,ownPayments:true,salesDeleteOwn:true};
sql(`begin;
 insert into profiles(id,username,display_name,phone,user_type,is_admin,active,permissions)
 values('${owner}','qa_${owner}','موظف التحصيل','07704113103','admin_staff',false,true,'${JSON.stringify(permissions)}'),
 ('${limited}','qa_${limited}','تحصيل بنسبة ثابتة','07704113104','admin_staff',false,true,'{"tahseel":true,"tahseelFull":false}');
 insert into public.transactions(id,kind,total,subtotal,cost,profit,payment_mode,cash,fx_pricing,created_by,cashbox_user_id,party_name)
 values(${invoice},'sale',2000,2000,1500,500,'credit',false,true,'${ids.owner}','${ids.owner}','${party}');
 insert into solar_private.warranty_certificates(token,invoice_id,document) values('${certificate}',${invoice},
 jsonb_build_object('receiptNo',17,'kind','sale','date',current_date,'customer','${party}',
 'warranty','{"enabled":true,"maintenance":{"duration":12,"unit":"months"}}'::jsonb,
 'items','[{"name":"لوح ضمان اختباري","qty":1,"term":{"duration":12,"unit":"months"}}]'::jsonb));
 insert into public.solar_notifications(user_id,event,title,body) values
 ('${owner}','cash_received','${marker}','توريد من مستخدم آخر'),
 ('${owner}','receipt_delete_requested','طلب حذف خاص بالمالية','تفاصيل الوصولات'),
 ('${owner}','admin_message','${announcement}','تعليمات الدوام');
 commit;`);

const modes=[
 ['general','التصميم العام','.generalDirectory'],
 ['groups','التصميم المجمّع','.groupedSectionDirectory'],
 ['columns','تصميم الأعمدة','.sectionDirectory.customLayout'],
 ['premium','تصميم بريميوم','.premiumCommandDirectory'],
 ['desk','تصميم المكتب','.deskSectionDirectory'],
 ['solar','أفق سولار','.solarHorizonDirectory']
];
const expected=['tahseel','warranty'];
async function sectionIds(region){
 const sections=await region.locator('a[href*="section="]').evaluateAll(links=>links.map(link=>new URL(link.href).searchParams.get('section')));
 return [...new Set(sections)].sort();
}
const h=await createHarness('restricted-account');
// Match the public API gateway's exposed pagination header on our loopback proxy.
let revoking=false;
h.setIntercept(async({route,call,response})=>{
 if(revoking&&call.who===owner&&call.path.endsWith('/solar_quote_defaults')&&response.status()===403){
  assert.equal((await response.json()).code,'42501','a stale, in-flight quote read must be denied');
  await route.fulfill({response});return true;
 }
 if(call.method!=='HEAD'||!call.path.endsWith('/solar_notifications'))return false;
 await route.fulfill({response,headers:{...response.headers(),'access-control-allow-origin':'*','access-control-expose-headers':'content-range,range-unit,preference-applied'}});
 return true;
});
try{
 const before=fingerprint(),{page}=await h.open(owner);
 const home=page.locator('.premiumDashboard');
 await home.waitFor();
 for(const [mode,title,selector] of modes){
  await page.getByRole('button',{name:'فتح قائمة حسابي'}).click();
  const account=page.getByRole('dialog',{name:'حسابي'});
  await account.getByRole('button',{name:'اختيار تصميم البرنامج'}).click();
  await account.getByRole('button',{name:new RegExp('^'+title)}).click();
  await account.locator('.sectionDesignPopover').waitFor({state:'hidden'});
  await page.keyboard.press('Escape');
  const directory=home.locator(selector);
  await directory.waitFor();
  assert.deepEqual(await sectionIds(directory),expected,mode+' directory');
  assert.deepEqual(await sectionIds(page.locator('.appContent')),expected,mode+' all work links');
  assert.equal(await home.locator('.premiumMetrics,.salesTrend').count(),0,mode+' financial summaries');
  if(mode==='general'){
   assert.equal(await home.locator('.generalDirectorySummary b').innerText(),'2 قسم');
   assert.deepEqual(await home.locator('[data-group]').evaluateAll(groups=>groups.map(g=>[g.dataset.group,g.dataset.count])),[['reports','2']]);
   await h.layout(page,'restricted-general',directory);
  }
  await page.locator('.appMobileBar').getByRole('button',{name:'الأقسام'}).click();
  const picker=page.getByRole('dialog',{name:'جميع الأقسام'});
  assert.deepEqual(await sectionIds(picker),expected,mode+' section picker');
  await page.keyboard.press('Escape');
 }
 h.checks.designs=modes.map(([mode])=>mode);

 await page.getByRole('button',{name:'فتح البحث العام'}).filter({visible:true}).click();
 const search=page.getByRole('dialog',{name:'البحث السريع'});
 assert.equal(await search.locator('.quickSearchTabs button').count(),0);
 await search.getByRole('textbox',{name:'البحث العام'}).fill('فاتورة');
 await search.locator('.quickSearchSections button').first().waitFor();
 assert.deepEqual(await search.locator('.quickSearchSections button').allTextContents(),['فحص ضمان فاتورة']);
 for(const term of ['الصندوق','حذف','المبيعات','سعر الصرف']){
  await search.getByRole('textbox',{name:'البحث العام'}).fill(term);
  await search.getByText(/لا توجد نتائج ضمن صلاحياتك/).waitFor();
  assert.equal(await search.locator('.quickSearchGroup').count(),0);
 }
 await page.keyboard.press('Escape');
 const searchData=await rpc(owner,'solar_quick_search',{term:party,category:'all'});
 for(const type of ['customers','products','suppliers'])assert.deepEqual(searchData[type],[]);
 assert.equal(h.calls.some(call=>call.path.endsWith('/solar_quick_search')),false,'section-only search queried unrelated business records');
 h.checks.quickSearch=true;

 await page.getByRole('button',{name:'فتح الإشعارات'}).click();
 const inbox=page.getByRole('dialog',{name:'الإشعارات'});
 await inbox.getByText(announcement,{exact:true}).waitFor();
 assert.equal(await inbox.getByText(marker).count(),0);
 assert.equal(await inbox.getByText('طلب حذف خاص بالمالية').count(),0);
 await inbox.getByText('1 غير مقروء',{exact:true}).waitFor();
 await inbox.getByRole('button',{name:'إغلاق',exact:true}).click();
 h.checks.inbox=true;

 for(const id of ['cash','exchangeRate','salesHistory','deletionRequests','profit','sale','purchasesHub','users','userActivity']){
  await page.goto(base+'/?section='+id);
  await page.locator('.smoothFrame').waitFor();
  await page.locator('.premiumDashboard,.empty').first().waitFor();
  const allowed=await page.locator('.premiumDashboard').isVisible();
  if(!allowed)await page.getByText('هذا القسم غير متاح لحسابك.').waitFor();
  assert.equal(await page.locator('.cashWorkspace,.archiveInvoice,.invoiceBuilder,.deletionWorkspace,.activityWorkspace').count(),0,id);
 }
 const forbiddenReads=new Set(['cash_ledger','transactions','transaction_items','solar_cash_entries','solar_cash_workspace','solar_exchange_rates','solar_archive','solar_delete_requests','solar_profit_workspace','solar_user_activity']);
 const attempted=h.calls.filter(call=>forbiddenReads.has(call.path.split('/').at(-1)));
 assert.deepEqual(attempted,[],'restricted routes should never fetch their record data');
 h.checks.directURLs=true;

 await page.goto(base+'/?section=tahseel');
 const quote=page.locator('.quoteWorkspace');
 await quote.getByRole('heading',{name:'طلب الزبون'}).waitFor();
 await quote.getByPlaceholder('اسم الزبون',{exact:true}).fill('عرض اختبار');
 await quote.getByRole('tab',{name:'المواد',exact:true}).click();
 await quote.getByRole('heading',{name:'المواد وكلفتها'}).waitFor();
 await h.layout(page,'restricted-quote',quote);
 await page.goto(base+'/?section=warranty');
 await page.getByLabel('رابط أو رمز الضمان').fill(certificate);
 await page.getByRole('button',{name:'فحص الضمان',exact:true}).click();
 await page.getByRole('heading',{name:'شهادة ضمان الفاتورة'}).waitFor();
 await page.getByText(party,{exact:true}).waitFor();
 h.checks.permittedSections=true;

 await page.goto(base+'/?section=tahseel');
 await quote.waitFor();
 revoking=true;
 sql(`update profiles set permissions=permissions||'{"tahseel":false,"tahseelFull":false,"warranty":true}'::jsonb where id='${owner}';`);
 const refresh=page.waitForResponse(r=>r.url().includes('/rest/v1/profiles')&&r.ok());
 await page.evaluate(()=>window.dispatchEvent(new Event('focus')));
 await refresh;
 await quote.waitFor({state:'hidden'});
 await page.locator('.appMobileBar').getByRole('button',{name:'الأقسام'}).click();
 const reduced=page.getByRole('dialog',{name:'جميع الأقسام'});
 await reduced.getByRole('link',{name:/فحص ضمان/}).waitFor();
 assert.deepEqual(await sectionIds(reduced),['warranty']);
 assert.equal(fingerprint(),before,'read-only account flow changed a financial record');
 h.checks.activeRevocation=true;

 const basic=await h.open(limited,'/?section=tahseel');
 const basicQuote=basic.page.locator('.quoteWorkspace');
 const expenses=basicQuote.getByRole('tab',{name:'المصاريف',exact:true});
 await expenses.click();
 assert.equal(await expenses.getAttribute('aria-selected'),'true');
 assert.equal(await basicQuote.getByLabel('نسبة الربح',{exact:true}).count(),0,'fixed rate cannot be edited by the basic account');
 const crane=basicQuote.getByRole('textbox',{name:'كرين',exact:true});
 await crane.fill('42000');
 assert.equal(Number((await crane.inputValue()).replace(/,/g,'')),42000);
 h.checks.fixedRateExpenses=true;
 await h.finish();
 console.log('PASS restricted account, all six designs, search, inbox, denied direct URLs, quote, real warranty and active revocation');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
