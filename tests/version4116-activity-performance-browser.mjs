// Real posted data, selected administrator view, Chromium-rendered PDF. Local fixture only.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4116_activity_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3224';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3223';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4116/activity-browser';
const {db,ids,sql,rpc,createHarness,fingerprint}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4116_activity_browser');
const owner=randomUUID(),other=randomUUID(),suffix=owner.slice(0,8),id=Date.now()*10;
const display='رنا '+suffix,privateName='مبيعات مستخدم آخر '+suffix;
const days=['2025-04-01','2025-04-02','2025-04-03','2025-04-04'];
sql(`begin;
 insert into profiles(id,display_name,username,phone,is_admin,user_type,active,permissions) values
 ('${owner}','${display}','activity_${suffix}','07704116001',false,'admin_staff',true,'{"sale":true}'),
 ('${other}','${privateName}','activity_${other}','07704116002',false,'admin_staff',true,'{}');
 insert into transactions(id,kind,total,subtotal,cost,profit,expenses,expenses_on_customer,
  created_at,created_by,cashbox_user_id,installation_status,installation_closed_at,cash,fx_pricing,payment_mode)
 select ${id}+seq,kind,sales,sales,sales-gain,gain,0,case when kind='sale' then false end,posted::timestamptz,actor::uuid,actor::uuid,
  case when kind='system' then status else 'none' end,
  case when status='closed' then posted::timestamptz end,false,true,'credit'
 from (values
  (1,'sale',1200,300,'2025-04-01 20:59:59+00','${owner}',null),
  (2,'sale',800,-80,'2025-04-01 21:00:00+00','${owner}',null),
  (3,'system',3000,500,'2025-04-02 10:00+00','${owner}','pending'),
  (4,'system',1100,220,'2025-04-04 10:00+00','${owner}','closed'),
  (5,'sale',2345678,123456,'2025-04-02 09:00+00','${other}',null)
 ) sources(seq,kind,sales,gain,posted,actor,status);
 insert into solar_private.profit_settlements(id,owner_id,date_from,date_to,snapshot,profit,status,created_at,decided_at,decided_by,share,receipt)
 values(gen_random_uuid(),'${owner}','2025-03-01','2025-03-31','[]',300,'approved',
 '2025-04-01 10:00Z','2025-04-02 12:00Z','${ids.admin}',90,'{}');
 commit;`);
const h=await createHarness('activity-performance');
const activity=(from,to)=>rpc('admin','solar_user_activity',{payload:{ownerId:owner,from,to}});
const expected={
 '2025-04-01':{salesIQD:1200,companyProfitIQD:300,invoiceCount:1},
 '2025-04-02':{salesIQD:3800,companyProfitIQD:-80,invoiceCount:2},
 '2025-04-03':{salesIQD:0,companyProfitIQD:0,invoiceCount:0},
 '2025-04-04':{salesIQD:1100,companyProfitIQD:220,invoiceCount:1}
};
function expectSeries(data,range){
 const perf=data.performance;
 assert.equal(perf.granularity,'day');
 assert.deepEqual(perf.series.map(row=>row.start),range);
 assert.deepEqual(perf.series.map(row=>row.end),range);
 for(const r of perf.series){
  for(const [key,amount] of Object.entries(expected[r.start]))assert.equal(r[key],amount,key+' '+r.start);
 }
 assert.equal(perf.series.reduce((s,r)=>s+r.salesIQD,0),data.sales.totalIQD);
 return perf;
}
async function rangeFilter(page,details,from,to){
 const match=page.waitForResponse(r=>r.url().endsWith('/rpc/solar_user_activity')&&r.request().postDataJSON()?.payload?.ownerId===owner&&r.request().postDataJSON()?.payload?.from===from&&r.request().postDataJSON()?.payload?.to===to);
 await details.getByLabel('من تاريخ النشاط').fill(from);
 await details.getByLabel('إلى تاريخ النشاط').fill(to);
 await details.getByRole('button',{name:'تطبيق الفترة',exact:true}).click();
 const response=await match;assert.ok(response.ok());return response.json();
}
const num=text=>Number(text.replace('د.ع','').replace(/[,%\s\u066a\u200e\u200f]/g,'').replace(/\u2212/g,'-'));
async function checkScreen(performance,totals){
 for(const [k,value] of Object.entries(totals)){
  const badge=performance.locator('[data-performance-metric="'+k+'"]');
  await badge.waitFor({state:'attached'});const val=badge.locator('bdi');
  const text=await val.count()?await val.first().textContent():await badge.textContent();
  if(value===null)assert.match(text,/غير محتسب/);else assert.equal(num(text),value,k+' shown as '+text);
 }
}
try{
 const baseline=fingerprint();
 const full=await activity(days[0],days[3]);
 const perf=expectSeries(full,days);
 assert.deepEqual([perf.eligibleSalesIQD,perf.companyProfitIQD,perf.approvedShareIQD,perf.approvedShareCount],[3100,440,90,1]);
 assert.ok(Math.abs(perf.marginPercent-100*440/3100)<0.01);
 await rpc(owner,'solar_user_activity',{payload:{ownerId:owner}},403);
 const {page,ctx}=await h.open('admin','/?section=userActivity');
 await page.getByRole('button',{name:'عرض نشاط '+display,exact:true}).click();
 const details=page.getByRole('region',{name:'نشاط المستخدم',exact:true});
 const area=details.locator('.activityPerformance');
 const report=details.getByRole('region',{name:'تقرير نشاط المستخدم'});
 expectSeries(await rangeFilter(page,details,days[0],days[3]),days);
 const totals={salesIQD:6100,invoiceCount:4,companyProfitIQD:440,approvedShareIQD:90,approvedShareCount:1,approvedSharePercent:30,approvedShareBaseIQD:300,averageInvoiceIQD:1525,eligibleSalesIQD:3100,marginPercent:14.19};
 await checkScreen(area,totals);
 const chart=area.locator('[data-performance-chart]');
 await area.getByRole('button',{name:'ربح الشركة',exact:true}).click();
 assert.equal(await chart.getAttribute('data-series'),'companyProfitIQD');
 await area.getByRole('button',{name:'المبيعات',exact:true}).click();
 assert.equal(await chart.getAttribute('data-series'),'salesIQD');
 const table=area.locator('.activitySeriesTable');
 await table.locator('summary').click();
 for(const day of days){
  const row=table.locator('tr[data-start="'+day+'"][data-end="'+day+'"]');
  for(const [key,value] of Object.entries(expected[day]))assert.equal(num(await row.locator('[data-column="'+key+'"]').innerText()),value,day+' '+key);
 }
 await h.layout(page,'signed-financial-chart',chart);
 await table.locator('summary').click();
 h.checks.dailyChartAndKpis=true;

 async function inspectExport(label,range,expectedTotals){
  const html=await h.report(page,ctx,report,label);
  const doc=await page.evaluate(html=>{
   const doc=new DOMParser().parseFromString(html,'text/html'),region=doc.querySelector('.activityReportDocument');
   if(!region)throw Error('The PDF did not use the activity document');
   return {text:doc.body.textContent,charts:[...region.querySelectorAll('[data-activity-chart]')].map(el=>el.dataset.activityChart),
    metrics:Object.fromEntries([...region.querySelectorAll('.reportMetric')].map(el=>[el.querySelector('span').textContent,el.querySelector('strong').textContent])),
    timeline:[...region.querySelectorAll('table')].flatMap(table=>[...table.tBodies[0].rows].filter(r=>/^\d{4}-\d\d-\d\d/.test(r.cells[0].textContent)).map(row=>[...row.cells].map(c=>c.textContent.trim())))};
  },html);
  assert.deepEqual(doc.charts,['salesIQD','companyProfitIQD']);
  assert.ok(doc.text.includes(display)&&!doc.text.includes(privateName));
  assert.equal(num(doc.metrics['إجمالي المبيعات']),expectedTotals.salesIQD);
  assert.equal(num(doc.metrics['ربح الشركة من فواتير المستخدم']),expectedTotals.companyProfitIQD);
  assert.equal(num(doc.metrics['حصة المستخدم المعتمدة بالتسويات']),expectedTotals.approvedShareIQD);
  assert.deepEqual(doc.timeline.map(row=>row[0]),range);
  for(const [day,count,sales,profit] of doc.timeline){
   assert.deepEqual([num(count),num(sales),num(profit)],[expected[day].invoiceCount,expected[day].salesIQD,expected[day].companyProfitIQD],day+' exported chart table');
  }
  return doc;
 }
 // Editing draft dates must not change a report until the period is applied.
 await details.getByLabel('من تاريخ النشاط').fill(days[1]);
 await details.getByLabel('إلى تاريخ النشاط').fill(days[1]);
 await inspectExport('four-day-activity',days,totals);
 await page.evaluate(()=>{
  const open=window.open.bind(window);
  window.open=(...args)=>{
   const popup=open(...args);
   if(popup)popup.print=()=>{window.__activityAutoPrint=(window.__activityAutoPrint||0)+1;};
   return popup;
  };
 });
 const printing=page.waitForEvent('popup');
 await report.getByRole('button',{name:'طباعة',exact:true}).click();
 const printed=await printing;
 await printed.locator('.pdfPage img').first().waitFor();
 await page.waitForFunction(()=>window.__activityAutoPrint===1);
 await printed.close();
 h.checks.nativePrint=true;

 let release,seen;
 const waiting=new Promise(resolve=>{seen=resolve;}),hold=new Promise(resolve=>{release=resolve;});
 h.setIntercept(async({route,call,response})=>{
  if(!call.path.endsWith('/solar_user_activity')||call.body?.payload?.from!==days[1])return false;
  seen();await hold;await route.fulfill({response});return true;
 });
 const loading=rangeFilter(page,details,days[1],days[1]);
 await waiting;
 try{
  assert.equal(await report.getByRole('button',{name:'مشاركة',exact:true}).isVisible(),false,'old report was still actionable during period change');
  assert.equal(await area.isVisible(),false,'old chart remained visible during period change');
 }finally{release();}
 expectSeries(await loading,[days[1]]);h.setIntercept(null);
 const negative={salesIQD:3800,invoiceCount:2,companyProfitIQD:-80,approvedShareIQD:90,approvedShareCount:1,approvedSharePercent:30,approvedShareBaseIQD:300,averageInvoiceIQD:1900,eligibleSalesIQD:800,marginPercent:-10};
 await checkScreen(area,negative);
 await area.getByRole('button',{name:'ربح الشركة',exact:true}).click();
 assert.ok(await chart.locator('.negative').count()>0,'a loss was charted as positive');
 await page.setViewportSize({width:1366,height:920});
 await inspectExport('negative-day-activity',[days[1]],negative);
 expectSeries(await rangeFilter(page,details,days[2],days[2]),[days[2]]);
 await checkScreen(area,{salesIQD:0,invoiceCount:0,companyProfitIQD:0,approvedShareIQD:0,approvedShareCount:0,approvedSharePercent:null,eligibleSalesIQD:0,marginPercent:null});
 assert.equal(await chart.count(),0,'empty period still showed the previous chart');
 const monthly=await rangeFilter(page,details,'2025-01-01','2025-04-30');
 assert.equal(monthly.performance.granularity,'month');
 assert.equal(monthly.performance.series.length,4);
 await area.getByRole('button',{name:'ربح الشركة',exact:true}).waitFor();
 await table.locator('summary').click();
 const april=table.locator('tr[data-start="2025-04-01"][data-end="2025-04-30"]');
 assert.equal(num(await april.locator('[data-column="companyProfitIQD"]').innerText()),440);
 assert.equal(num(await april.locator('[data-column="salesIQD"]').innerText()),6100);
 h.checks.periodSwitchExportAndEmptyDay=true;
 const roster=await rpc('admin','solar_user_activity',{payload:{}});
 const fieldUser=roster.users.find(u=>u.userType==='warehouse'&&u.active);
 assert.ok(fieldUser,'local fixture needs a warehouse operator');
 await details.getByRole('button',{name:'رجوع إلى دليل المستخدمين',exact:true}).click();
 await page.getByRole('button',{name:'عرض نشاط '+fieldUser.name,exact:true}).click();
 await report.getByRole('button',{name:'حفظ PDF',exact:true}).waitFor();
 const fieldHtml=await h.report(page,ctx,report,'warehouse-activity');
 const fieldText=await page.evaluate(h=>new DOMParser().parseFromString(h,'text/html').body.textContent,fieldHtml);
 assert.ok(fieldText.includes(fieldUser.name)&&fieldText.includes('نشاط المخزن خلال الفترة'));
 assert.ok(!fieldText.includes(display),'second user inherited the previous export');
 h.checks.secondOwnerOperationsReport=true;
 assert.equal(fingerprint(),baseline,'display/print/share mutated financial records');
 await h.finish();
 console.log('PASS real activity KPIs, signed profit chart and table, Baghdad dates, period changes, actual PDF preview/download/print and share');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
