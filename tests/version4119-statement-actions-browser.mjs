import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
process.env.SOLAR_FIXTURE_DB||='solar_v4118_returned_tab_browser';
process.env.SOLAR_FIXTURE_API||='http://127.0.0.1:3259';
process.env.SOLAR_APP_URL||='http://127.0.0.1:3272';
process.env.SOLAR_ARTIFACT_DIR||='/workspace/solar-review/v4119/statement-actions-browser';
const {createHarness,sql,rpc,ids}=await import('./version4-browser-support.mjs');
const owner=randomUUID(),customerId=Date.now(),product=customerId+1,name='إجراءات العميل '+customerId;
const permissions={sale:true,customers:true,customerStatement:true,customerPayment:true,salesDeleteOwn:true,deletionRequests:true};
sql(`begin;
 insert into profiles(id,display_name,phone,user_type,permissions) values('${owner}','مسؤول اختبار الوصولات','079${String(customerId).slice(-8)}','admin_staff','${JSON.stringify(permissions)}');
 insert into solar_private.warehouse_access(user_id,warehouse_ids) values('${owner}',array[1]::bigint[]) on conflict(user_id) do update set warehouse_ids=excluded.warehouse_ids;
 insert into customers(id,name,customer_type,owner_id) values(${customerId},'${name}','wholesale','${owner}');
 insert into products(id,code,name,qty,cost) values(${product},'ACC-${customerId}','مادة إجراءات الحساب',10,1000);
 insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(1,${product},10) on conflict(warehouse_id,product_id) do update set qty=10;
commit;`);
const sale=actor=>rpc(actor,'solar_invoice_save',{request_id:randomUUID(),payload:{kind:'sale',mode:'credit',warehouseId:1,party:name,saleCustomerId:customerId,items:[{id:product,qty:1,price:5000}]}});
const own=await sale(owner);await sale(ids.admin);
const state=await rpc(owner,'solar_customer_payment_context',{customer_id:customerId});
const payment=await rpc(owner,'solar_customer_payment_save',{request_id:randomUUID(),payload:{customerId,invoiceId:null,amount:1000,mode:'payment',notes:'',expectedToken:state.token}});
const button=(page,label)=>page.getByRole('button',{name:label,exact:true});
const h=await createHarness('statement-actions-browser');
async function openAccount(actor){
 const {page}=await h.open(actor,'/?section=customerStatement');
 await page.getByRole('combobox',{name:'بحث عميل الكشف'}).fill(name);
 await page.getByRole('option',{name:new RegExp(name)}).click();
 await page.getByRole('heading',{name,exact:true}).waitFor();return page;
}
try{
 const page=await openAccount(ids.admin),controls=page.getByRole('region',{name:'إجراءات الحساب'});
 await controls.waitFor();
 for(const width of [360,390,1366]){
  await page.setViewportSize({width,height:800});await page.evaluate(()=>scrollTo(0,0));
  for(const label of ['تعديل اسم العميل','تحويل الزبون','تعديل وحذف الوصولات']){
   const action=button(controls,label);assert.equal(await action.count(),1);
   const rect=await action.boundingBox();assert.ok(rect&&rect.height>=44&&rect.x>=0&&rect.y>=0&&rect.y+rect.height<720&&rect.x+rect.width<=width);
  }
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
  await page.screenshot({path:h.dir+'/controls-'+width+'.png',animations:'disabled'});
 }
 await button(controls,'تعديل وحذف الوصولات').click();const panel=page.getByRole('region',{name:'إدارة وصولات العميل'});
 assert.equal(await panel.getByRole('article').count(),3);await button(panel,'تسديدات').click();assert.equal(await panel.getByRole('article').count(),1);
 assert.equal(await button(panel,'حذف وصل التسديد').count(),1);await button(panel,'تعديل وصل التسديد').click();await page.getByLabel('مبلغ تعديل التسديد',{exact:true}).waitFor();
 const ownerPage=await openAccount(owner);assert.equal(await button(ownerPage,'تحويل الزبون').count(),0);await button(ownerPage,'تعديل وحذف الوصولات').click();
 const ownersPanel=ownerPage.getByRole('region',{name:'إدارة وصولات العميل'});assert.equal(await ownersPanel.getByRole('article').count(),2);
 await button(ownersPanel,'مبيعات').click();assert.equal(await ownersPanel.getByRole('article').count(),1);
 await ownersPanel.getByRole('searchbox').fill('#'+String(own.receiptNo).replace(/\d/g,d=>'٠١٢٣٤٥٦٧٨٩'[d]));assert.equal(await button(ownersPanel,'تعديل وصل البيع').count(),1);
 await button(ownersPanel,'تعديل وصل البيع').click();await ownerPage.getByLabel('ملاحظات الفاتورة').waitFor();
 sql(`update profiles set permissions='{"customerStatement":true}' where id='${owner}'`);const limited=await openAccount(owner);assert.equal(await limited.getByRole('region',{name:'إجراءات الحساب'}).count(),0);assert.equal(await button(limited,'حذف وصل التسديد').count(),0);
 assert.ok(payment.id);Object.assign(h.checks,{viewportWidths:[360,390,1366],adminCanManageSalesAndPayments:true,ownerOnlyOwnReceipts:true,statementOnlyReadAccess:true});await h.finish();console.log('PASS visible statement controls at 360, 390, 1366; sale and payment editors open from dedicated lists; restricted accounts and receipts excluded.');
}catch(err){await h.fail(err);console.error(err);process.exitCode=1;}finally{await h.close();}
