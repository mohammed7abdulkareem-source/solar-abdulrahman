// Compiled app -> isolated PostgREST with the real pg-safeupdate library loaded.
// Fixture and both V4.1.1 migrations must already be applied to this local DB.
process.env.SOLAR_FIXTURE_DB||='solar_v411_browser';
process.env.SOLAR_FIXTURE_API||='http://127.0.0.1:3147';
process.env.SOLAR_APP_URL||='http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR||='/workspace/solar-review/v411/configuration-browser';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
const {createHarness,rpc,sql,scalar,fingerprint}=await import('./version4-browser-support.mjs');
const h=await createHarness('version411-configuration');
const uid=n=>'00000000-0000-0000-0000-000000410'+String(n).padStart(3,'0');
const ids={admin:uid(101),owner:uid(102),seller:uid(103),manager:uid(106)};
const state=()=>rpc(ids.manager,'solar_wholesale_pricing',{action:'state'});
const noticeHash=()=>sql("select md5(coalesce(jsonb_agg(to_jsonb(n)order by id),'[]')::text) from solar_notifications n");
const configCalls=()=>h.calls.filter(c=>c.path.endsWith('/solar_wholesale_pricing')&&c.body?.action==='configure');
const allWrites=()=>h.calls.filter(c=>c.path.endsWith('/solar_wholesale_pricing')&&c.body?.action!=='state');
const noticeIds=()=>JSON.parse(sql("select coalesce(jsonb_agg(id),'[]') from solar_notifications"));
let dropNextConfiguration=false;
h.setIntercept(async({route,call,response})=>{
 if(dropNextConfiguration&&call.body?.action==='configure'&&response.status()===200){dropNextConfiguration=false;call.deliveredStatus=503;await route.fulfill({status:503,json:{code:'PGRST000',message:'Isolated committed configuration response unavailable'}});return true;}
 if(response.status()>=400)h.errors.push({path:call.path,status:response.status(),body:await response.text()});
 await route.fulfill({response,headers:{...response.headers(),'access-control-allow-origin':'*','access-control-expose-headers':'content-range,range-unit,preference-applied'}});return true;
});
async function configure(enabled,mode,userIds=[]){const current=await state();return rpc(ids.manager,'solar_wholesale_pricing',{action:'configure',request_id:randomUUID(),payload:{enabled,mode,userIds,expectedRevision:current.revision}});}
function assertSingleRevisionAndNotices(before,after,previousIds){
 assert.equal(after.revision,before.revision+1);
 const newRows=JSON.parse(sql("select coalesce(jsonb_agg(to_jsonb(n)),'[]') from solar_notifications n")).filter(n=>!previousIds.includes(n.id));
 assert.ok(newRows.length>0);assert.equal(new Set(newRows.map(n=>n.user_id)).size,newRows.length);
}
try{
 const preload=sql("select setconfig::text from pg_db_role_setting s join pg_database d on d.oid=s.setdatabase join pg_roles r on r.oid=s.setrole where d.datname=current_database() and r.rolname='solar_rpc_fixture'");assert.match(preload,/session_preload_libraries=safeupdate/);
 const repro=JSON.parse(await readFile('/workspace/solar-review/v411/safeupdate-reproduction.json','utf8'));assert.equal(repro.code,'21000');assert.equal(repro.noFinancialOrPolicyWrites,true);h.checks.realSafeupdateProductionFailureReproducedAndFixed=true;
 const recoveryOnly=process.env.SOLAR_CONFIGURATION_RECOVERY_ONLY==='1';
 const baseline=await state();if(!recoveryOnly){assert.equal(baseline.scopeConfigured,false);assert.equal(baseline.enabled,true);assert.equal(baseline.scopeMode,'all');}
 const {page:m}=await h.open(ids.manager,'/?section=wholesalePricing');
 const panel=m.getByRole('region',{name:'إعدادات إلزام أسعار الجملة',exact:true}),on=panel.getByRole('switch',{name:'تشغيل الإلزام',exact:true}),all=panel.getByRole('checkbox',{name:'تحديد جميع المستخدمين',exact:true}),save=panel.getByRole('button',{name:'حفظ إعدادات الإلزام',exact:true}),owner=panel.getByRole('checkbox',{name:'تطبيق الأسعار على — مسؤول مشتريات 4.1',exact:true}),seller=panel.getByRole('checkbox',{name:'تطبيق الأسعار على — بائع المخزن المسموح 4.1',exact:true});
 const success=()=>m.locator('.wpSuccess').filter({hasText:'تم تأكيد حفظ إعدادات الإلزام'}).waitFor(),retry=m.getByRole('button',{name:'تأكيد حفظ أسعار الجملة السابق',exact:true});
 await on.waitFor();assert.equal(await save.count(),1);assert.equal(await panel.getByRole('radio').count(),0);assert.equal(await m.getByRole('button',{name:'حفظ نطاق تطبيق أسعار الجملة',exact:true}).count(),0);assert.equal(await m.getByRole('button',{name:/^(تشغيل|إيقاف) الأسعار الإلزامية$/}).count(),0);
 const beforeMoney=fingerprint();
 if(!recoveryOnly){
 const beforeNotices=noticeIds();await on.uncheck();await all.uncheck();assert.equal(allWrites().length,0);assert.equal((await state()).scopeConfigured,false);assert.equal(await save.isDisabled(),false);
 await save.evaluate(button=>{button.click();button.click();});await success();let current=await state();assert.equal(current.scopeConfigured,true);assert.equal(current.scopeMode,'selected');assert.equal(current.enabled,false);assert.deepEqual(current.selectedUserIds,[]);assertSingleRevisionAndNotices(baseline,current,beforeNotices);assert.equal(configCalls().length,1);assert.equal(fingerprint(),beforeMoney);h.checks.firstEmptyDisabledConfigurationOneRequestAndNotification=true;
 await on.check();assert.equal(await save.isDisabled(),true);assert.match(await panel.innerText(),/اختر مستخدماً واحداً على الأقل/);assert.equal(configCalls().length,1);await owner.check();assert.equal(await all.evaluate(el=>el.indeterminate),true);assert.equal(await save.isDisabled(),false);
 const beforeLost=current,noticesBeforeLost=noticeIds();dropNextConfiguration=true;await save.evaluate(button=>{button.click();button.click();});await retry.waitFor();const committed=await state(),committedNotices=noticeHash(),attempt=await m.evaluate(id=>JSON.parse(sessionStorage.getItem('solar-wholesale-pricing-attempt-v1:'+id)),ids.manager);assert.equal(attempt.action,'configure');assert.deepEqual(attempt.payload.userIds,[ids.owner]);assert.equal(attempt.payload.enabled,true);assert.equal(configCalls().length,2);assertSingleRevisionAndNotices(beforeLost,committed,noticesBeforeLost);assert.equal(await on.isDisabled(),true);await m.reload();await retry.click();await success();assert.equal((await state()).revision,committed.revision);assert.equal(noticeHash(),committedNotices);assert.equal(configCalls().length,3);assert.deepEqual(configCalls()[1].body,configCalls()[2].body);assert.equal(scalar("select count(*) from solar_private.finance_requests where request_id='"+attempt.id+"'"),1);assert.equal(scalar("select count(*) from solar_private.wholesale_pricing_audit where request_id='"+attempt.id+"'"),1);assert.equal(fingerprint(),beforeMoney);h.checks.emptyEnabledRejectedAndPersistentSameIdRecoveryExactlyOnce=true;
 await on.uncheck();const beforeOff=await state(),offIds=noticeIds();assert.equal(beforeOff.enabled,true);await save.click();await success();current=await state();assert.equal(current.enabled,false);assert.deepEqual(current.selectedUserIds,[ids.owner]);assert.equal(await owner.isChecked(),true);assertSingleRevisionAndNotices(beforeOff,current,offIds);h.checks.globalOffRetainsIndividualSelection=true;
 await all.check();await on.check();assert.equal((await state()).enabled,false);const beforeAll=current,allIds=noticeIds();await save.click();await success();current=await state();assert.equal(current.enabled,true);assert.equal(current.scopeMode,'all');assert.deepEqual(current.selectedUserIds,[]);assertSingleRevisionAndNotices(beforeAll,current,allIds);assert.equal(await owner.isChecked(),true);assert.equal(await seller.isChecked(),true);
 await seller.uncheck();assert.equal(await all.isChecked(),false);assert.equal(await all.evaluate(el=>el.indeterminate),true);const beforeSubset=current;await save.click();await success();current=await state();assert.equal(current.scopeMode,'selected');assert.ok(!current.selectedUserIds.includes(ids.seller));assert.ok(current.selectedUserIds.includes(ids.owner));assert.equal(current.revision,beforeSubset.revision+1);h.checks.selectAllAndIndividualChecklistUseOneAtomicSave=true;
 // Catalog saves remain independent and do not erase an unsaved configuration.
 await on.uncheck();await m.getByLabel('البحث في أسعار بيع الجملة',{exact:true}).fill('V410-12');const row=current.products.find(p=>p.id===-410112);assert.ok(row);const price=m.getByLabel('سعر البيع الأدنى — '+row.name,{exact:true});await price.fill(String(Number(row.minPrice)+1));await m.getByRole('button',{name:'حفظ الأسعار',exact:true}).click();await m.locator('.wpSuccess').filter({hasText:/تم تحديث أسعار/}).waitFor();assert.equal(await on.isChecked(),false);assert.equal((await state()).enabled,true);assert.equal(await save.isDisabled(),false);await panel.getByRole('button',{name:'إلغاء التعديل',exact:true}).click();assert.equal(await on.isChecked(),true);h.checks.productSavePreservesUncommittedConfiguration=true;
 }
 // Old app versions may have committed a scope/toggle and lost the reply. Exact
 // replay must clear the attempt without undoing a newer combined configuration.
 for(const action of ['scope','toggle']){
  let fresh=await state();const oldAttempt={id:randomUUID(),action,payload:action==='scope'?{mode:'selected',userIds:[ids.owner],expectedRevision:fresh.revision}:{enabled:true,expectedRevision:fresh.revision}};
  if(action==='toggle'&&fresh.enabled){await configure(false,'selected',[ids.seller]);fresh=await state();oldAttempt.payload.expectedRevision=fresh.revision;}
  await rpc(ids.manager,'solar_wholesale_pricing',{action,request_id:oldAttempt.id,payload:oldAttempt.payload});const latest=await configure(false,'selected',[ids.seller]),noticeBeforeRetry=noticeHash();
  await m.evaluate(({id,attempt})=>sessionStorage.setItem('solar-wholesale-pricing-attempt-v1:'+id,JSON.stringify(attempt)),{id:ids.manager,attempt:oldAttempt});await m.reload();await retry.waitFor();assert.equal(await on.isDisabled(),true);const priorCalls=allWrites().length;await retry.click();await m.locator('.wpSuccess').waitFor();assert.equal(allWrites().length,priorCalls+1);assert.deepEqual(allWrites().at(-1).body,{action,request_id:oldAttempt.id,payload:oldAttempt.payload});const after=await state();assert.equal(after.revision,latest.revision);assert.equal(after.enabled,false);assert.deepEqual(after.selectedUserIds,[ids.seller]);assert.equal(noticeHash(),noticeBeforeRetry);assert.equal(await on.isChecked(),false);assert.equal(await seller.isChecked(),true);assert.equal(await owner.isChecked(),false);if(action==='toggle'){assert.match(await m.locator('.wpSuccess').innerText(),/متوقف|إيقاف/);assert.doesNotMatch(await m.locator('.wpSuccess').innerText(),/تم تشغيل/);}assert.equal(await m.evaluate(id=>sessionStorage.getItem('solar-wholesale-pricing-attempt-v1:'+id),ids.manager),null);
 }
 h.checks.oldPendingScopeAndToggleReplayFreshStateWithoutReversion=true;
 // Save a compact representative final screen, including the current user list.
 await owner.check();await on.check();await save.click();await success();await m.getByLabel('البحث في أسعار بيع الجملة',{exact:true}).fill('PRIVATE-CODE-V411');if(await m.getByLabel('البحث في مستخدمي تسعير الجملة',{exact:true}).count())await m.getByLabel('البحث في مستخدمي تسعير الجملة',{exact:true}).fill('4.1');await h.layout(m,'unified-pricing-configuration',panel);assert.equal(fingerprint(),beforeMoney);h.checks.noHistoricalFinancialWrites=true;
 await h.finish();console.log('PASS V4.1.1 real-safeupdate configuration, one atomic save, single notices, retained selection, persistent retries, old-client recovery and responsive checklist');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
