// Run against a disposable database with the V4 browser accounts and the profit-target migration.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4113_profit_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3178';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4113/browser';
const {createHarness,db,sql,scalar,rpc,fingerprint,base}=await import('./version4-browser-support.mjs');
assert.ok(['solar_v4113_profit_browser','solar_v4113_final_browser'].includes(db));
const h=await createHarness('profit-target');
const target=randomUUID(),control=randomUUID();
const retained=id=>scalar("select solar_private.retained_profit('"+id+"'::uuid)");
const count=()=>scalar('select count(*) from solar_private.profit_balance_adjustments');
const overview=id=>rpc('admin','solar_profit_workspace',{action:'overview',payload:{ownerId:id}});
const otherBooks=()=>sql(`select md5(jsonb_build_array(
 (select jsonb_agg(to_jsonb(s) order by id) from solar_private.profit_settlements s),
 (select jsonb_agg(to_jsonb(c) order by owner_id,source_key) from solar_private.profit_checkpoints c),
 (select jsonb_agg(to_jsonb(o) order by invoice_id) from solar_private.invoice_profit_owners o)
)::text)`);
const cash=id=>scalar("select solar_private.cash_balance('"+id+"'::uuid)");
const region=p=>p.getByRole('region',{name:'تعديل رصيد الأرباح خارج البرنامج',exact:true});
const review=p=>p.getByRole('region',{name:'معاينة تعديل رصيد الأرباح',exact:true});
const formButton=(p,name)=>region(p).getByRole('button',{name,exact:true});
const targetInput=p=>region(p).getByLabel('رصيد الأرباح الجديد',{exact:true});
async function waitBalance(p,value,testId='external-profit-balance'){
 const expected=value.toLocaleString('en-US',{maximumFractionDigits:2});
 await p.waitForFunction(({testId,expected})=>document.querySelector('[data-testid="'+testId+'"]')?.textContent===expected,{testId,expected});
}
async function validPreview(p,previous,targetAmount,delta){
 const values=await review(p).locator('dd bdi').allTextContents();
 assert.deepEqual(values,[previous,targetAmount,delta]);
 assert.match(await review(p).innerText(),/مستخدم تسوية تجريبية/);
}
async function checkLayout(p,label,element){
 for(const [width,height] of [[360,780],[390,844],[1366,850]]){
  await p.setViewportSize({width,height});
  await element.scrollIntoViewIfNeeded();
  assert.equal(await region(p).evaluate(el=>getComputedStyle(el).direction),'rtl');
  assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'overflow at '+width);
  const buttons=await region(p).getByRole('button').evaluateAll(nodes=>nodes.map(n=>n.getBoundingClientRect().toJSON()).filter(box=>box.width));
  assert.ok(buttons.every(box=>box.left>=-1&&box.right<=width+1),'action extends past viewport at '+width);
  await p.screenshot({path:h.dir+'/'+label+'-'+width+'.png',animations:'disabled'});
 }
 await p.setViewportSize({width:390,height:844});
}
try{
 const seed=await readFile(new URL('./version4113-profit-target-browser-fixture.sql',import.meta.url),'utf8');
 sql(['\\set target_id '+target,'\\set control_id '+control,seed].join('\n'));
 const before=fingerprint(),booksBefore=otherBooks(),cashBefore=cash(target),countBefore=count();
 assert.equal(retained(target),-100000);assert.equal(retained(control),3125.75);
 const admin=await h.open('admin','/?section=profit'),p=admin.page;
 await p.getByRole('button',{name:/تسويات المستخدمين/}).click();
 const owner=region(p).getByLabel('مستخدم كشف التسوية',{exact:true});
 await owner.selectOption(target);
 await waitBalance(p,-100000);
 const note=region(p).getByLabel('ملاحظة تعديل الرصيد',{exact:true});
 const preview=formButton(p,'معاينة تعديل الرصيد'),confirm=formButton(p,'تأكيد تعديل الرصيد');
 assert.equal(await preview.isEnabled(),false);
 await formButton(p,'تصفير الرصيد').click();
 assert.equal(await targetInput(p).inputValue(),'0');
 assert.equal(retained(target),-100000);
 await note.fill('اختبار تسوية خارجية إلى الصفر');
 await preview.click();
 await validPreview(p,'-100,000','0','+100,000');
 await checkLayout(p,'zero-review',review(p));
 await targetInput(p).fill('-999.99');
 assert.equal(await review(p).count(),0);
 assert.equal(await confirm.count(),0);
 assert.equal(count(),countBefore);
 await formButton(p,'تصفير الرصيد').click();
 await preview.click();await confirm.click();await waitBalance(p,0);
 assert.equal(retained(target),0);assert.equal(count(),countBefore+1);
 await p.waitForLoadState('networkidle');
 await targetInput(p).fill('−١٢٬٣٤٥٫٦٧');
 assert.equal(await targetInput(p).inputValue(),'−١٢٬٣٤٥٫٦٧');
 await note.fill('تسوية تجريبية برصيد سالب');
 assert.equal(await targetInput(p).inputValue(),'−١٢٬٣٤٥٫٦٧');
 await preview.click();await validPreview(p,'0','-12,345.67','-12,345.67');
 // Simulate the lost acknowledgement of an already committed operation.
 let lostResponse=false;
 h.setIntercept(async({route,call,response})=>{
  if(!lostResponse&&call.path.endsWith('/solar_profit_workspace')&&call.body?.action==='external_adjust'&&response.status()===200){
   lostResponse=true;await route.abort('connectionreset');return true;
  }
  return false;
 });
 await confirm.click();
 const retry=formButton(p,'إعادة تأكيد العملية');
 await p.getByText('تعذّر تأكيد نتيجة الحفظ. أعد تأكيد العملية بنفس البيانات.',{exact:true}).waitFor();
 assert.ok(lostResponse);assert.ok(await retry.isEnabled());
 assert.equal(retained(target),-12345.67);
 await p.reload();await p.getByRole('button',{name:/تسويات المستخدمين/}).click();
 await retry.waitFor();
 const retryResult=p.waitForResponse(response=>response.url().endsWith('/rpc/solar_profit_workspace')
  &&response.request().postDataJSON()?.action==='external_adjust');
 await retry.click();assert.ok((await retryResult).ok());
 await retry.waitFor({state:'hidden'});await waitBalance(p,-12345.67);
 const saveCalls=h.calls.filter(call=>call.body?.action==='external_adjust');
 assert.equal(saveCalls.length,3);
 assert.deepEqual(saveCalls[1].body,saveCalls[2].body);
 assert.equal(count(),countBefore+2);
 const state=await overview(target),history=state.externalAdjustments;
 assert.deepEqual(history.map(row=>[row.before,row.after,row.delta].map(Number)),[[0,-12345.67,-12345.67],[-100000,0,100000]]);
 assert.ok(history.every(row=>row.ownerId===target&&row.createdAt&&row.actorName));
 const disclosure=region(p).locator('.externalProfitHistory');
 await disclosure.locator('summary').click();
 assert.equal(await disclosure.locator('article').count(),2);
 for(const record of history){
  const item=disclosure.locator('article').filter({hasText:record.note});
  assert.ok(await item.isVisible());assert.ok((await item.innerText()).includes(record.actorName));
 }
 await checkLayout(p,'saved-history',disclosure);
 await owner.selectOption(control);await waitBalance(p,3125.75);
 assert.equal(await region(p).locator('.externalProfitHistory').count(),0);
 await p.goto(base+'/?section=cash&cashView=profits');
 await p.getByRole('tab',{name:'التسويات',exact:true}).click();
 await region(p).getByLabel('مستخدم كشف التسوية',{exact:true}).selectOption(target);
 await waitBalance(p,-12345.67);
 assert.ok(await formButton(p,'تصفير الرصيد').isEnabled());
 h.checks.cashSettlementsCanSelectTarget=true;
 const {page:employee}=await h.open(target,'/?section=profit');
 await waitBalance(employee,-12345.67,'staff-profit-current-balance');
 assert.equal(await region(employee).count(),0);
 assert.equal(await employee.getByRole('button',{name:'تأكيد تعديل الرصيد'}).count(),0);
 const personalDetails=employee.locator('summary[aria-label="تفاصيل تسوية الأرباح الخارجية"]');
 assert.equal(await personalDetails.count(),2);
 const ownEntry=personalDetails.filter({hasText:'-12,345.67'});
 await ownEntry.click();
 const employeeAudit=employee.locator('.profitMovement[open] .profitExternalAudit');
 await employeeAudit.waitFor();assert.deepEqual(await employeeAudit.locator('dd bdi').allTextContents(),['0','-12,345.67','-12,345.67']);
 assert.ok((await employeeAudit.innerText()).includes(history[0].note));
 assert.equal(retained(control),3125.75);assert.equal(cash(target),cashBefore);
 assert.equal(fingerprint(),before);assert.equal(otherBooks(),booksBefore);
 h.checks.adminPersonalAdjustment={initial:-100000,zero:0,final:-12345.67,otherOwner:3125.75,auditEntries:2};
 h.checks.uncertainRetryAfterReloadUsesSameRequest=true;
 h.checks.staffCanReadOwnBalanceAndAuditWithoutAdjustmentForm=true;
 h.checks.financialDocumentsAndCashUnchanged=true;
 await h.finish();console.log('PASS real admin adjustment, negative and zero, persisted retry, audit, mobile/desktop, staff scope, and unchanged financial ledgers.');
}catch(error){await h.fail(error);throw error}finally{await h.close()}
