// Admin checklist and permission wizard use the same per-person policy.
// The Edge gateway forwards to the actual wizard SQL in the isolated fixture.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
process.env.SOLAR_FIXTURE_DB||='solar_v4125_pricing_basis_browser';
process.env.SOLAR_FIXTURE_API||='http://127.0.0.1:3330';
process.env.SOLAR_APP_URL||='http://127.0.0.1:3331';
process.env.SOLAR_ARTIFACT_DIR||='/workspace/solar-review/v4125/admin-basis-browser';
const {base,db,createHarness,rpc,sql,ids}=await import('./version4-browser-support.mjs');
assert.match(db,/^solar_v4125_pricing_basis(?:_final)?_browser$/);
const adminId=ids.admin,tag=randomUUID().slice(0,8),target=randomUUID(),manager=randomUUID();
const targetName='مندوب تجربة '+tag;
for(const [id,name,permissions] of [[target,targetName,{system:true,profit:true}],[manager,'مسؤول التسعير '+tag,{wholesalePricingManage:true}]]){
 sql("insert into public.profiles(id,username,display_name,phone,active,is_admin,user_type,permissions) values('"+id+"','ab_"+id.slice(0,8)+"','"+name+"','07700000001',true,false,'admin_staff','"+JSON.stringify(permissions)+"'::jsonb)");
}
const userState=()=>rpc('admin','solar_profit_basis_users',{action:'state'});
const toSQL=value=>"'"+String(value).replaceAll("'","''")+"'";
const h=await createHarness('profit-basis-users');
try{
 const {page,ctx}=await h.open('admin','/?section=wholesalePricing');
 const panel=page.locator('details.wpBasisPanel');
 const checkbox=panel.getByRole('checkbox',{name:'أساس الربح بسعر الجملة — '+targetName,exact:true});
 async function expand(){
  if(!(await panel.evaluate(el=>el.open)))await panel.locator('summary').click();
  const search=panel.getByRole('textbox',{name:'بحث في مستخدمي أساس الربح'});
  await panel.locator('fieldset').waitFor();
  if(await search.count())await search.fill(targetName);
  await checkbox.waitFor();
 }
 await expand();
 assert.equal(await checkbox.isChecked(),false);
 await checkbox.check();
 let dropResponse=true;
 h.setIntercept(async({route,call})=>{
  if(call.path.endsWith('/solar_profit_basis_users')&&call.body?.action==='save'&&dropResponse){
   assert.equal(call.status,200);dropResponse=false;await route.abort('failed');return true;
  }
  return false;
 });
 await panel.getByRole('button',{name:'حفظ أساس الربح',exact:true}).click();
 await panel.getByRole('button',{name:'تأكيد الحفظ السابق',exact:true}).waitFor();
 await page.reload();await expand();
 await panel.getByRole('button',{name:'تأكيد الحفظ السابق',exact:true}).click();
 await panel.getByText('تم حفظ أساس الربح للمستخدمين.').waitFor();
 assert.equal(await checkbox.isChecked(),true);
 const attempted=h.calls.filter(c=>c.path.endsWith('/solar_profit_basis_users')&&c.body?.action==='save');
 assert.equal(attempted.length,2);assert.deepEqual(attempted[0].body,attempted[1].body);
 assert.deepEqual(attempted[0].body.payload.changes,[{id:target,enabled:true}]);
 await h.layout(page,'admin-selects-profit-basis',panel);
 // A different admin (simulated via independent request) edits another user after the original state was loaded.
 await checkbox.uncheck();
 let state=await userState();
 await rpc('admin','solar_profit_basis_users',{action:'save',request_id:randomUUID(),payload:{token:state.token,changes:[{id:manager,enabled:true}]}});
 h.setIntercept(async({route,call,response})=>{
  if(call.path.endsWith('/solar_profit_basis_users')&&call.body?.action==='save'&&call.status===409){await route.fulfill({response});return true;}
  return false;
 });
 await panel.getByRole('button',{name:'حفظ أساس الربح',exact:true}).click();
 await panel.getByRole('button',{name:'تحميل الإعدادات الحالية'}).click();
 await panel.locator('fieldset:not(:disabled)').waitFor();
 assert.equal(await checkbox.isChecked(),true);
 h.setIntercept(null);
 await ctx.route('**/functions/v1/solar-admin-users',async route=>{
  const body=route.request().postDataJSON();
  const action=body.action==='list'?'directory':body.action;
  assert.ok(['directory','finalize'].includes(action));
  const {request_id,...payload}=body;delete payload.action;
  const result=JSON.parse(sql('select public.solar_admin_user_wizard('+toSQL(adminId)+','+toSQL(action)+','+(request_id?toSQL(request_id):'null')+','+toSQL(JSON.stringify(payload))+'::jsonb)'));
  await route.fulfill({status:200,json:{ok:true,...result}});
 });
 await page.goto(base+'/?section=users');
 const userRow=page.locator('[data-user-id="'+target+'"]');await userRow.waitFor();
 await userRow.getByRole('button',{name:/تعديل/}).click();
 await page.getByRole('button',{name:'حفظ البيانات والمتابعة'}).click();
 const wizardBasis=page.locator('input[data-permission="profitUsesWholesalePrice"]');
 await wizardBasis.waitFor();assert.equal(await wizardBasis.isChecked(),true);
 await wizardBasis.uncheck();
 await h.layout(page,'wizard-profit-basis',page.locator('.uaProfitBasis'));
 await page.getByRole('button',{name:'مراجعة المخازن'}).click();
 await page.getByRole('button',{name:'مراجعة الحساب'}).click();
 assert.equal(await page.getByText('الكلفة الفعلية',{exact:true}).count(),1);
 await page.getByRole('button',{name:'حفظ إعدادات المستخدم'}).click();
 await userRow.waitFor();
 state=await userState();assert.equal(state.users.find(u=>u.id===target).enabled,false);
 assert.equal(state.users.find(u=>u.id===manager).enabled,true);
 await page.goto(base+'/?section=wholesalePricing');await expand();assert.equal(await checkbox.isChecked(),false);
 const user=(await h.open(manager,'/?section=wholesalePricing')).page;
 await user.getByRole('region',{name:'إدارة أسعار بيع الجملة'}).waitFor();
 assert.equal(await user.locator('details.wpBasisPanel').count(),0);
 assert.equal(h.calls.filter(c=>c.who===manager&&c.path.endsWith('/solar_profit_basis_users')).length,0);
 h.checks.accountBasis={sparseUpdate:true,retrySameRequest:true,conflictProtected:true,wizardSynced:true,pricingManagerCannotSelectUsers:true};
 await h.finish();console.log('Profit basis administration browser checks passed.');
}catch(err){await h.fail(err);throw err;}finally{await h.close();}
