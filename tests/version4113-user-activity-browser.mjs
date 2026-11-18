// Uses the disposable V4/V415/V419 browser accounts and posted fixture receipts.
import assert from 'node:assert/strict';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4113_final_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3179';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4113/activity-browser';
const {createHarness,db,sql,rpc,fingerprint}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4113_final_browser');
const h=await createHarness('user-activity');
const id=suffix=>'00000000-0000-0000-0000-000000'+suffix;
const office=id('419502'),warehouse=id('415503'),installer=id('419505'),inactive=id('413107');
const activity=payload=>rpc('admin','solar_user_activity',{payload});
const route='/?section=userActivity';
const labels={office:'المكتب',warehouse:'المخزن',installer:'التنصيب'};
const role=user=>['installer','warehouse'].includes(user.userType)?user.userType:'office';
const metric=(region,key)=>region.locator('[data-activity-metric="'+key+'"]');
const dateOnly=query=>sql("select to_char(("+query+"),'YYYY-MM-DD')");
const checkButton=(scope,label)=>scope.getByRole('button',{name:label,exact:true});
async function checkMetrics(region,response,keys){
 for(const key of keys){
  const amount=key.split('.').reduce((obj,field)=>obj?.[field],response);
  assert.notEqual(amount,null,key);assert.notEqual(amount,undefined,key);
  const number=metric(region,key);
  await number.waitFor();
  const shown=await number.evaluate(el=>(el.querySelector('bdi')||el).textContent.replaceAll(',',''));
  assert.notEqual(shown,'',key);
  assert.equal(Number(shown),Number(amount),key);
 }
}
async function setDateRange(page,region,owner,day){
 const action=page.waitForResponse(res=>res.url().endsWith('/rpc/solar_user_activity')
  &&res.request().postDataJSON()?.payload?.ownerId===owner
  &&res.request().postDataJSON()?.payload?.to===day);
 await region.getByLabel('من تاريخ النشاط').fill(day);
 await region.getByLabel('إلى تاريخ النشاط').fill(day);
 await checkButton(region,'تطبيق الفترة').click();
 const response=await action;assert.ok(response.ok());
 return await response.json();
}
async function responsive(page,region,name){
 assert.equal(await region.evaluate(el=>getComputedStyle(el).direction),'rtl');
 await h.layout(page,name,region.locator('h1'));
 const actions=region.getByRole('button');
 for(const width of [360,390,1366]){
  await page.setViewportSize({width,height:850});
  const outside=await actions.evaluateAll(els=>els.filter(el=>el.getBoundingClientRect().width>0)
   .filter(el=>{const r=el.getBoundingClientRect();return r.left < -1 || r.right>innerWidth+1;}).map(el=>el.textContent));
  assert.deepEqual(outside,[],name+' buttons outside viewport at '+width);
 }
 await page.setViewportSize({width:390,height:850});
}
try{
 const before=fingerprint(),roster=(await activity({})).users;
 const expected=JSON.parse(sql('select jsonb_agg(id order by id) from public.profiles where not coalesce(is_admin,false)'));
 assert.deepEqual(roster.map(row=>row.id).sort(),expected);
 const byId=actor=>{const user=roster.find(row=>row.id===actor);assert.ok(user,actor);return user;};
 assert.equal(byId(inactive).active,false);
 const admin=await h.open('admin','/'),p=admin.page;
 await p.getByLabel('البحث في الأقسام').waitFor();
 const settingsButton=p.locator('.workspaceHomeTabs').getByRole('button',{name:'الإعدادات',exact:true});
 if(await settingsButton.count())await settingsButton.click();
 const tile=p.locator('main a[href="/?section=userActivity"]').first();await tile.click();
 const directory=p.getByRole('region',{name:'دليل نشاط المستخدمين',exact:true});
 const details=p.getByRole('region',{name:'نشاط المستخدم',exact:true});
 const cards=directory.getByRole('button',{name:/^عرض نشاط /});
 const search=directory.getByLabel('بحث المستخدمين');
 const firstCard=cards.first();
 await firstCard.waitFor();
 assert.equal(await cards.count(),expected.length);
 await responsive(p,directory,'staff-directory');
 for(const [kind,label] of Object.entries(labels)){
  await checkButton(directory,label).click();
  assert.equal(await cards.count(),roster.filter(user=>role(user)===kind).length);
 }
 await checkButton(directory,'الكل').click();
 await search.fill(byId(inactive).username);
 assert.equal(await cards.count(),1);assert.match(await firstCard.innerText(),/غير نشط/);
 const selectUser=async(actor,kind)=>{
  await search.fill('');await checkButton(directory,labels[kind]).click();
  const user=byId(actor);
  await search.fill(user.username||user.name);
  const item=checkButton(directory,'عرض نشاط '+user.name);
  await item.click();await details.getByRole('heading',{name:user.name,exact:true}).waitFor();
 };
 await selectUser(office,'office');
 const all=await activity({ownerId:office});
 const sales=JSON.parse(sql("select jsonb_build_object('totalIQD',sum(total),'wholesaleIQD',sum(total) filter (where kind='sale'),'systemIQD',sum(total) filter (where kind='system'),'count',count(*)) from transactions where kind in ('sale','system') and created_by='"+office+"'"));
 for(const [key,value] of Object.entries(sales))assert.equal(Number(all.sales[key]),Number(value),key+' vs posted receipts');
 assert.ok(sales.count>0&&sales.wholesaleIQD>0&&sales.systemIQD>0);
 const keys=['sales.count','sales.totalIQD','sales.wholesaleIQD','sales.systemIQD','profit.earnedIQD','profit.remainingIQD','debts.dueIQD','debts.creditIQD','cash.IQD','cash.USD','collections.count','collections.IQD','collections.USD','handovers.outgoing.IQD','handovers.incoming.IQD','handovers.pendingOutgoing.IQD','expenses.personalProfitIQD','expenses.cash.IQD'];
 await checkMetrics(details,all,keys);await responsive(p,details,'office-finance');
 const soldOn=dateOnly("select min(created_at at time zone 'Asia/Baghdad') from transactions where kind='sale' and created_by='"+office+"'");
 const previous=dateOnly("date '"+soldOn+"' - 1");
 const earlier=await setDateRange(p,details,office,previous);
 assert.equal(earlier.sales.count,0);assert.equal(earlier.profit.remainingIQD,all.profit.remainingIQD);
 assert.deepEqual(earlier.cash,all.cash);await checkMetrics(details,earlier,keys);
 const soldDay=await setDateRange(p,details,office,soldOn);
 assert.equal(soldDay.sales.count,sales.count);await checkMetrics(details,soldDay,keys);
 await checkButton(details,'آخر الحركات').click();
 assert.ok((await details.locator('.activityRows li').count())>0);
 await checkButton(details,'مراجعة الحساب').click();
 const counted=details.getByLabel('المبلغ المعدود فعلياً');
 const currency=details.getByLabel('عملة الجرد');
 assert.deepEqual(soldDay.review.book,soldDay.cash);
 for(const code of ['IQD','USD']){
  await currency.selectOption(code);
  const actual=Number(soldDay.review.book[code]),count=Math.max(0,actual)+100;
  await counted.fill(String(count));
  const result=details.locator('.activityCountResult');
  await result.waitFor();assert.match(await result.innerText(),/أكثر من المسجّل/);
  assert.equal(Number((await result.locator('bdi').innerText()).replaceAll(',','')),count-actual);
  if(actual>=0){await counted.fill(String(actual));assert.match(await result.innerText(),/مطابق/);}
 }
 assert.equal(await details.locator('.activityReviewTotals dd').last().innerText(),String(soldDay.review.differenceCount));
 await h.layout(p,'office-account-review',details.locator('.activityTabs'));
 await checkButton(details,'رجوع إلى دليل المستخدمين').click();
 for(const [userId,kind,field] of [[warehouse,'warehouse','prepared'],[installer,'installer','closed']]){
  await selectUser(userId,kind);
  const data=await activity({ownerId:userId});
  assert.ok(data.operations[kind][field]>0,kind+' posted operation');
  await checkMetrics(details,data,['operations.'+kind+'.'+field]);
  const records=details.locator('.activityRows li');
  await records.first().waitFor();
  assert.ok((await records.allInnerTexts()).some(text=>text.includes('#')),'operation receipt number');
  await responsive(p,details,kind+'-operations');
  await checkButton(details,'الملخص المالي').click();
  await checkMetrics(details,data,['cash.IQD','cash.USD','sales.totalIQD']);
  await checkButton(details,'رجوع إلى دليل المستخدمين').click();
 }
 for(const actor of [office,id('419504'),installer]){
  await rpc(actor,'solar_user_activity',{payload:{ownerId:office}},403);
  const {page}=await h.open(actor,route);
  await page.waitForLoadState('networkidle');
  assert.equal(await page.locator('.userActivity').count(),0);
  assert.equal(await page.locator('a[href="/?section=userActivity"]').count(),0);
  assert.equal(h.calls.filter(call=>call.who===actor&&call.path.endsWith('/solar_user_activity')).length,0);
 }
 assert.equal(fingerprint(),before);
 h.checks.directory={users:expected.length,excludesAdministrators:true,includesInactive:true};
 h.checks.officeSales={...sales,baghdadDate:soldOn,previousDate:previous};
 h.checks.operationRoles=['warehouse','installer'];h.checks.staffAccessDenied=true;
 h.checks.cashCountPreview=['IQD','USD'];
 h.checks.financialStateUnchanged=true;
 await h.finish();console.log('PASS admin-only activity from Settings, user roles, signed finance metrics, Baghdad dates, operations, read-only access and responsive RTL.');
}catch(error){await h.fail(error);throw error}finally{await h.close()}
