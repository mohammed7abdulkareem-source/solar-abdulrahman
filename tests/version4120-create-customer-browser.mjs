// Real customer writes against a dedicated local database. No production calls.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

process.env.SOLAR_FIXTURE_DB ||= 'solar_v4120_customer_create_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3280';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3281';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4120/customer-create-browser';
const {db,sql,rpc,createHarness}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4120_customer_create_browser');
const household=Date.now(),creator=randomUUID(),office=randomUUID(),none=randomUUID();
const outsider=household+1,outName='زبون تجريبي مستقل '+household;
const made='زبون الإضافة التجريبي '+household,second='زبون الدليل التجريبي '+household;
const officeMade='زبون المكتب التجريبي '+household,officeRetry='زبون تأكيد تجريبي '+household;
const roles=[[creator,{customerCreate:true}],[office,{customerCreate:true,customers:true,sale:true,system:true}],[none,{}]];
const button=(page,name)=>page.getByRole('button',{name,exact:true});
const nameField=page=>page.getByRole('textbox',{name:'اسم الزبون',exact:true});
const directory=actor=>rpc(actor,'solar_customer_directory',{});
const selected=(rows,name)=>rows.find(item=>item.name===name);
const section=(page,label)=>page.getByRole('link',{name:label,exact:true}).or(button(page,label));
const openSection=(page,label)=>section(page,label).first().click();
const actionPanels=page=>page.locator('.customerWorkspace');
function seed(){
 for(const [key,permissions] of roles)sql(`insert into public.profiles(id,username,display_name,user_type,is_admin,active,phone,permissions)
 values('${key}','cc_${key}','موظف تجريبي','admin_staff',false,true,'07700000001','${JSON.stringify(permissions)}')`);
 sql(`insert into customers(id,name,owner_id,customer_type) values(${outsider},'${outName}','${office}','system')`);
}
async function create(page,name,type='system'){
 await nameField(page).fill(name);
 const typeField=page.getByLabel('نوع الزبون',{exact:true});
 await typeField.selectOption(type);
 assert.equal(await page.getByRole('textbox',{name:'رقم هاتف الزبون'}).inputValue(),'');
 const saved=page.waitForResponse(r=>r.request().method()==='POST'&&new URL(r.url()).pathname.endsWith('/rpc/solar_customer_save')&&r.request().postDataJSON().action==='create');
 await button(page,'إضافة الزبون').click();
 const response=await saved;
 assert.equal(response.status(),200);
 return response.json();
}
async function visibleSaved(page,name){
 const account=page.getByRole('heading',{name,exact:true});
 const row=button(page,'حساب '+name);
 await account.or(row).first().waitFor();
 const position=await row.isVisible()?'directory':'account';
 return {position,region:position==='directory'?row:account};
}
async function checkZero(actor,id,name,type){
 const record=await rpc(actor,'solar_customer_get',{customer_id:id});
 assert.equal(record.name,name);assert.equal(record.ownerId,actor);
 assert.equal(record.customerType,type);assert.equal(Number(record.balance),0);
 assert.ok(!record.phone);
 assert.equal(sql(`select count(*) from transactions where party_id=${id}`),'0');
 assert.equal(selected(await directory(actor),name).id,Number(id));
 return record;
}
const h=await createHarness('office-customer-create');
let releaseCatalog;
try{
 seed();
 let failPrefetch=true,failedDirectoryReads=0;
 const deniedFirstDirectory=async({call,route})=>{
  if(call.who!==creator||!failPrefetch||!call.path.endsWith('/rpc/solar_customer_directory'))return false;
  await route.fulfill({status:403,json:{code:'42501',message:'لا تملك صلاحية الزبائن'}});
  failedDirectoryReads++;return true;
 };
 h.setIntercept(deniedFirstDirectory);
 const minimal=(await h.open(creator)).page;
 await openSection(minimal,'إضافة زبون');await nameField(minimal).waitFor();
 await minimal.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
 assert.ok(!h.calls.some(call=>call.who===creator&&call.path.endsWith('/rpc/solar_customer_directory')),'blank creation form must not fetch the protected directory');
 assert.equal(await minimal.getByText(/لا تملك صلاحية الزبائن/).count(),0,'false permission warning on blank create form');
 await h.layout(minimal,'clean-blank-create-form',nameField(minimal));
 await nameField(minimal).fill(outName);
 await minimal.getByText('هذا الزبون مسجّل مسبقاً',{exact:true}).waitFor();
 assert.ok(await button(minimal,'إضافة الزبون').isDisabled());
 assert.equal(await button(minimal,'حساب '+outName).count(),0);
 assert.equal(await minimal.getByText(/لا تملك صلاحية الزبائن/).count(),0);
 failPrefetch=false;
 const first=await create(minimal,made);
 h.setIntercept(null);
 h.checks.noFalsePermissionWarningAtOpen={failedDirectoryReads};
 let shown=await visibleSaved(minimal,made);
 await h.layout(minimal,'created-zero-balance',shown.region);
 const account=await checkZero(creator,first.id,made,'system');
 if(shown.position==='directory')await button(minimal,'حساب '+made).click();
 await minimal.getByRole('heading',{name:made,exact:true}).waitFor();
 for(const action of ['تعديل اسم العميل','تعديل البيانات','حذف الزبون','تحويل الزبون'])
  assert.equal(await button(minimal,action).count(),0,action);
 assert.equal((await rpc(creator,'solar_customer_save',{action:'rename',request_id:randomUUID(),payload:{id:first.id,name:made+' جديد',token:account.token}},403)).code,'42501');
 assert.equal((await rpc(creator,'solar_customer_save',{action:'delete',request_id:randomUUID(),payload:{id:first.id,token:account.token}},403)).code,'42501');
 assert.equal((await rpc(creator,'solar_customer_get',{customer_id:outsider},403)).code,'42501');
 assert.ok(!selected(await directory(creator),outName));
 h.checks.createOnly={accessibleFromHome:true,blankPhone:true,zeroBalance:true,ownDirectory:true,foreignCustomerPrivate:true,noEditOrDelete:true};

 const directoryPage=(await h.open(creator,'/?section=customers')).page;
 await button(directoryPage,'زبون جديد').waitFor();
 await button(directoryPage,'تصفية العملاء').click();
 await directoryPage.getByLabel('تصفية رصيد الزبون',{exact:true}).selectOption('due');
 await button(directoryPage,'زبون جديد').click();
 const secondResult=await create(directoryPage,second,'wholesale');
 await visibleSaved(directoryPage,second);await checkZero(creator,secondResult.id,second,'wholesale');
 h.checks.addFromFilteredDirectory=true;

 let catalogRead;
 const waiting=new Promise(resolve=>{catalogRead=resolve;});
 const release=new Promise(resolve=>{releaseCatalog=resolve;});
 const isCatalog=call=>call.who===office&&call.path.endsWith('/rpc/solar_inventory')&&call.body?.action==='catalog';
 let delayed=0;
 h.setIntercept(async({call,route})=>{
  if(!isCatalog(call))return false;
  delayed++;catalogRead();await release;
  await route.fulfill({status:503,json:{code:'PGRST000',message:'synthetic catalogue unavailable'}});return true;
 });
 const regular=(await h.open(office,'/?section=customerCreate')).page;
 await Promise.race([waiting,new Promise((_,reject)=>{const timer=setTimeout(()=>reject(new Error('catalog request did not start')),6000);timer.unref();})]);
 await nameField(regular).waitFor({timeout:5000});
 assert.ok(!h.calls.some(call=>call.who===office&&call.path.endsWith('/rpc/solar_customer_directory')),'office blank form requested protected directory');
 assert.equal(await regular.getByText(/لا تملك صلاحية الزبائن/).count(),0);
 await h.layout(regular,'create-while-catalog-offline',actionPanels(regular).first());
 const officeReceipt=await create(regular,officeMade,'wholesale');
 const regularShown=await visibleSaved(regular,officeMade);await checkZero(office,officeReceipt.id,officeMade,'wholesale');
 if(regularShown.position==='directory')await button(regular,'حساب '+officeMade).click();
 await button(regular,'تعديل اسم العميل').waitFor();
 assert.equal(await button(regular,'تحويل الزبون').count(),0);
 releaseCatalog();releaseCatalog=null;assert.ok(delayed>0);
 h.setIntercept(null);
 h.checks.staffCanSaveDuringUnrelatedCatalogFailure=true;
 const staffHome=(await h.open(office)).page;
 await openSection(staffHome,'إضافة زبون');await nameField(staffHome).fill(officeRetry);
 let dropped=false;
 h.setIntercept(async({call,route,response})=>{
  if(!dropped&&call.who===office&&call.path.endsWith('/rpc/solar_customer_save')&&call.body.action==='create'){
   assert.equal(response.status(),200);dropped=true;await route.abort('internetdisconnected');return true;
  }return false;
 });
 await button(staffHome,'إضافة الزبون').click();
 await button(staffHome,'إعادة تأكيد الحفظ').click();
 await visibleSaved(staffHome,officeRetry);
 h.setIntercept(null);
 assert.ok(dropped);
 const saves=h.calls.filter(call=>call.path.endsWith('/rpc/solar_customer_save')&&call.body?.payload?.name===officeRetry);
 assert.equal(saves.length,2);assert.deepEqual(saves[0].body,saves[1].body);
 assert.equal(sql(`select count(*) from customers where name='${officeRetry}' and owner_id='${office}'`),'1');
 h.checks.lostSuccessResponseReplayedOnce=true;
 const limited=(await h.open(none,'/?section=customerCreate')).page;
 assert.equal(await nameField(limited).count(),0);
 assert.equal(await section(limited,'إضافة زبون').count(),0);
 assert.equal((await rpc(none,'solar_customer_save',{action:'create',request_id:randomUUID(),payload:{id:household+2,name:'زبون مرفوض '+household,customerType:'system'}},403)).code,'42501');
 h.checks.missingPermissionDenied=true;
 await h.finish();console.log('PASS customer creation with minimum permissions, office grants, zero balance and response loss');
}catch(error){await h.fail(error);throw error;}
finally{releaseCatalog?.();await h.close();}
