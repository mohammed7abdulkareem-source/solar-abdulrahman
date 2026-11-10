// Real compiled UI -> loopback PostgREST -> disposable PostgreSQL only.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createHarness,ids,rpc,sql,scalar,cash,fingerprint,base} from './version4-browser-support.mjs';
const h=await createHarness('direct-deletion-browser'),run=randomUUID().slice(0,8);
const deleted=id=>scalar('select count(*) from transactions where id='+id)===0;
const requests=id=>scalar('select count(*) from solar_private.receipt_delete_requests where invoice_id='+id);
const stock=id=>scalar('select qty from products where id='+id);
async function invoice(kind='sale',extra={}){
 const payload={kind,mode:'cash',partyId:kind==='system'?-400102:-400101,party:kind==='purchase'?'مورد اختبار V4':kind==='system'?'عميل منظومة الإصدار الرابع':'عميل جملة الإصدار الرابع',total:1000000,customerAddress:'عنوان الاختبار المحلي',installerId:ids.installer,notes:'v4-direct-'+run,items:[{id:-400105,qty:2,price:200000}],...extra};
 const saved=await rpc('owner','solar_invoice_save',{request_id:randomUUID(),payload});return JSON.parse(sql('select row_to_json(t) from transactions t where id='+saved.id));
}
async function context(row,who='owner'){return rpc(who,'solar_receipt_delete_requests',{action:'context',payload:{invoiceId:row.id}});}
async function prepared(row){const c=await rpc('owner','solar_sale_preparation',{action:'get',invoice_id:row.id});return rpc('owner','solar_sale_preparation',{action:'ready',invoice_id:row.id,expected_token:c.token,request_id:randomUUID()});}
async function saleCard(page,row){await page.goto(base+'/?section=salesHistory');await page.getByLabel('بحث الوصل أو الزبون').fill(String(row.receipt_no));await page.getByRole('button',{name:'بحث / تحديث',exact:true}).click();const card=page.getByRole('article',{name:(row.kind==='system'?'بيع منظومة':'بيع جملة')+' رقم '+row.receipt_no,exact:true});await card.waitFor();return card;}
async function purchaseCard(page,row){await page.goto(base+'/?section=purchase');await page.locator('.deskHistory > summary').click();await page.getByLabel('بحث الفواتير السابقة').fill(String(row.receipt_no));const card=page.locator('.historyItem').filter({has:page.locator('summary').filter({hasText:'فاتورة شراء رقم '+row.receipt_no})});await card.waitFor();return card;}
async function awaitDeleted(page,row){await page.waitForFunction(()=>document.body.innerText.includes('تم حذف الوصل وتصحيح أثره'));assert.ok(deleted(row.id));}
async function purchaseDelete(page,card){const [dialog]=await Promise.all([page.waitForEvent('dialog',{predicate:d=>d.type()==='alert'}),card.getByRole('button',{name:'حذف',exact:true}).click()]);return dialog.message();}
try{
 const normal=await invoice('sale',{expenses:40000}),system=await invoice('system',{mode:'credit',items:[{id:-400105,qty:1,price:0}]}),acted=await invoice('sale',{mode:'credit'});await prepared(acted);
 const purchase=await invoice('purchase',{mode:'credit',items:[{id:-400103,qty:10,price:10000}]}),laterSale=await invoice('sale',{items:[{id:-400103,qty:2,price:20000}]}),laterPurchase=await invoice('purchase',{items:[{id:-400103,qty:5,price:12000}]});await prepared(laterSale);
 const shortage=await invoice('purchase',{items:[{id:-400104,qty:2,price:10000}]}),shortSale=await invoice('sale',{items:[{id:-400104,qty:2,price:20000}]});await prepared(shortSale);
 const laterHash=()=>sql('select md5(jsonb_agg(jsonb_build_array(to_jsonb(t),(select jsonb_agg(to_jsonb(i) order by id) from transaction_items i where transaction_id=t.id)) order by t.id)::text) from transactions t where id in('+[laterSale.id,laterPurchase.id,shortSale.id].join(',')+')'),history=laterHash();
 const owner=await h.open('owner','/?section=salesHistory'),p=owner.page;h.setCurrent(p);
 // Preview is read-only; foreign/dedicated users cannot read or execute even with a leaked token.
 let initial=fingerprint(),c=await context(normal);assert.equal(c.directEligible,true);assert.equal(c.deletionMode,'direct');assert.equal(fingerprint(),initial);
 for(const who of['foreign','warehouse','installer']){await rpc(who,'solar_receipt_delete_requests',{action:'context',payload:{invoiceId:normal.id}},403);await rpc(who,'solar_receipt_delete_requests',{action:'delete_direct',request_id:randomUUID(),payload:{invoiceId:normal.id,expectedToken:c.token}},403);}assert.equal(fingerprint(),initial);h.checks.previewAndServerPermissions=true;
 // Lost successful acknowledgement must survive a navigation/reload and replay the same request.
 let drop=true;h.setIntercept(async({route,call,response})=>{if(drop&&call.body?.action==='delete_direct'&&call.body?.payload?.invoiceId===normal.id&&response.status()===200){drop=false;await route.abort('failed');return true;}return false;});
 let card=await saleCard(p,normal),cashBefore=cash(ids.owner),stockBefore=stock(-400105);await h.layout(p,'direct-sale',card);
 await card.getByRole('button',{name:'حذف الوصل',exact:true}).evaluate(b=>{b.click();b.click();});
 const recovery=p.getByRole('region',{name:'تأكيد الحذف السابق',exact:true});await recovery.getByRole('button',{name:'تأكيد الحذف السابق',exact:true}).waitFor();
 assert.ok(deleted(normal.id));assert.equal(cash(ids.owner),cashBefore-440000);assert.equal(stock(-400105),stockBefore+2);assert.equal(requests(normal.id),0);
 const afterDelete=fingerprint(),attempt=await p.evaluate(uid=>JSON.parse(localStorage.getItem('solar-receipt-deletion-attempt-v1:'+uid)),ids.owner);assert.equal(attempt.invoiceId,normal.id);assert.equal(attempt.action,'delete_direct');
 await p.reload();await recovery.getByRole('button',{name:'تأكيد الحذف السابق',exact:true}).click();await recovery.getByRole('status').waitFor();assert.equal(fingerprint(),afterDelete);assert.equal(await p.evaluate(uid=>localStorage.getItem('solar-receipt-deletion-attempt-v1:'+uid),ids.owner),null);
 const sent=h.calls.filter(x=>x.body?.action==='delete_direct'&&x.body?.payload?.invoiceId===normal.id);assert.equal(sent.length,2);assert.equal(sent[0].body.request_id,sent[1].body.request_id);assert.equal(sent[0].body.request_id,attempt.id);h.checks.directCashSaleRefundSingleExecutionAndPersistentReplay=true;
 // An untouched system is cancelled directly; the installation reservation is restored.
 card=await saleCard(p,system);c=await context(system);assert.equal(c.directEligible,true);stockBefore=stock(-400105);cashBefore=cash(ids.owner);await card.getByRole('button',{name:'حذف الوصل',exact:true}).click();await awaitDeleted(p,system);assert.equal(cash(ids.owner),cashBefore);assert.equal(requests(system.id),0);assert.equal(stock(-400105),stockBefore+1);h.checks.pristineSystemDirect=true;
 // Prepared sale still goes through the original approval and is never auto-deleted.
 c=await context(acted);assert.equal(c.directEligible,false);assert.equal(c.deletionMode,'approval');assert.ok(c.directBlockedReason);initial=fingerprint();card=await saleCard(p,acted);await card.getByRole('button',{name:'حذف الوصل',exact:true}).click();await p.getByRole('status').filter({hasText:'تم إرسال طلب الحذف للإدارة'}).waitFor();assert.equal(fingerprint(),initial);assert.equal(requests(acted.id),1);assert.ok(!deleted(acted.id));
 const admin=await h.open('admin','/?section=deletionRequests'),a=admin.page;await a.locator('.deletionRequestRow').filter({hasText:'بيع جملة #'+acted.receipt_no}).click();const panel=a.locator('.deletionReview');await panel.getByRole('button',{name:'موافقة وحذف الوصل',exact:true}).click();await a.locator('.workflowSuccess').filter({hasText:'تم الحذف بموافقة الإدارة'}).waitFor();assert.ok(deleted(acted.id));h.checks.preparedSaleStillRequiresApproval=true;
 // Later stock movement is retained while the purchase correction uses current available stock.
 h.setCurrent(p);card=await purchaseCard(p,purchase);c=await context(purchase);assert.equal(c.directEligible,true);assert.equal(c.blockedReason,null);assert.equal(stock(-400103),13);cashBefore=cash(ids.owner);assert.match(await purchaseDelete(p,card),/تم حذف الوصل وتصحيح أثره/);assert.ok(deleted(purchase.id));assert.equal(stock(-400103),3);assert.equal(cash(ids.owner),cashBefore);assert.equal(requests(purchase.id),0);assert.equal(laterHash(),history);assert.equal(scalar('select coalesce(sum(delta),0) from solar_private.supplier_fx_entries where supplier_id=-400101'),0);h.checks.purchaseAfterLaterMovementsDirectAndHistoryPreserved=true;
 card=await purchaseCard(p,shortage);initial=fingerprint();assert.match(await purchaseDelete(p,card),/المتاح غير المحجوز/);assert.equal(fingerprint(),initial);assert.ok(!deleted(shortage.id));assert.equal(requests(shortage.id),0);await h.layout(p,'shortage-blocked',card);h.checks.insufficientStockNoWrites=true;
 assert.equal(laterHash(),history);await h.finish();console.log('PASS V4 direct deletion UI/API/DB: owner cash/system/purchase, later stock history, real approval fallback, permissions, shortage, persistent lost-ack replay and responsive layouts');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
