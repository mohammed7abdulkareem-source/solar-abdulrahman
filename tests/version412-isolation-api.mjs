// Read-only privacy regression against a disposable database and real local PostgREST.
// The fixture is created separately; this test never creates invoices or changes roles.
import assert from 'node:assert/strict';
import {mkdir,readFile,writeFile} from 'node:fs/promises';

process.env.SOLAR_FIXTURE_DB ||= 'solar_seller_scope_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3149';
const {api,db,sql,tokenFor,fingerprint}=await import('./version4-browser-support.mjs');
assert.match(api,/^http:\/\/127\.0\.0\.1:\d+$/);
assert.match(db,/^solar_[a-z0-9_]+_browser$/);
const dir=process.env.SOLAR_ARTIFACT_DIR||'/workspace/solar-review/v412/api';
await mkdir(dir,{recursive:true});
const ids=Object.fromEntries(['admin','owner','foreign','warehouse','installer','inactive'].map((name,index)=>[name,'00000000-0000-0000-0000-000000'+(412101+index)]));
const invoiceIds=[-412101,-412102,-412103,-412104,-412105,-412106],ownIds=[-412101,-412105],foreignInvoiceIds=[-412102,-412103,-412104,-412106];
const transactionIds=[...invoiceIds,-412107,-412108],ownTransactionIds=[...ownIds,-412107],foreignIds=[...foreignInvoiceIds,-412108];
const ownCustomer=-412101,foreignCustomer=-412102,calls=[],checks={};
const sorted=values=>values.map(Number).sort((a,b)=>a-b);
const sameIds=(actual,expected,label)=>assert.deepEqual(sorted(actual),sorted(expected),label);
const filters=params=>new URLSearchParams(params).toString();
const idFilter='in.('+transactionIds.join(',')+')';
const bookkeeping=()=>sql("select md5(jsonb_build_array((select jsonb_agg(to_jsonb(t)order by request_id)from solar_private.invoice_requests t),(select jsonb_agg(to_jsonb(t)order by request_id)from solar_private.invoice_attempt_cancellations t),(select jsonb_agg(to_jsonb(t)order by request_id)from solar_private.finance_requests t),(select jsonb_agg(to_jsonb(t)order by id)from solar_private.receipt_delete_requests t))::text)");
let fixture,before,metadataBefore;

async function request(who,path,{method='GET',body,headers={},status=200}={}){
 assert.ok(method==='GET'||method==='HEAD'||(method==='POST'&&path.startsWith('/rpc/')),'Only read endpoints are allowed');
 const response=await fetch(api+path,{method,headers:{...(who==='anon'?{}:{authorization:'Bearer '+tokenFor(ids[who]||who)}),...(body?{'content-type':'application/json'}:{}),...headers},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(20000)});
 const text=await response.text(),data=text?JSON.parse(text):null,allowed=Array.isArray(status)?status:[status];
 calls.push({who,path,method,request:body,status:response.status,contentRange:response.headers.get('content-range'),responseBytes:text.length});
 assert.ok(allowed.includes(response.status),`${who} ${method} ${path}: expected ${allowed}, got ${response.status}: ${text}`);
 return {data,response};
}
const rpc=async(who,name,body={},status=200)=>(await request(who,'/rpc/'+name,{method:'POST',body,status})).data;
async function denied(who,name,body){const result=await rpc(who,name,body,who==='anon'?[401,403]:403);assert.equal(result.code,'42501',name+' must fail authorization');return result;}
function noForeign(data,label){
 const serialized=JSON.stringify(data);
 assert.ok(!serialized.includes('عبدالرحمن اختبار V412'),label+' exposes the foreign seller name');
 for(const row of fixture.transactions.filter(t=>foreignIds.includes(t.id))){
  if(row.notes)assert.ok(!serialized.includes(row.notes),label+' exposes private invoice notes');
  for(const item of fixture.items.filter(i=>i.transaction_id===row.id))assert.ok(!serialized.includes(item.product_name),label+' exposes private invoice material');
 }
 function walk(value){
  if(!value||typeof value!=='object')return;
  for(const[key,item]of Object.entries(value)){
   if(/^(?:id|transaction_id|transactionId|invoice_id|invoiceId|movement_id|movementId|job_id|jobId|systemInvoiceId)$/.test(key))assert.ok(!foreignIds.some(id=>String(item).includes(String(id))),label+' exposes foreign invoice ID '+item);
   if(value.receiptRestricted&&/^(?:receiptNo|receipt_no|systemReceiptNo|system_receipt_no)$/.test(key))assert.ok(item==null,label+' exposes restricted receipt number '+item);
   if(item&&typeof item==='object')walk(item);
  }
 }
 walk(data);
}
function noFinancialFields(data,label){
 const forbidden=new Set(['total','subtotal','price','sourcePrice','source_price','cost','landedCost','landed_cost','cost_basis','costBasis','profit','expenses','invoiceAccount','invoice_account','accountAmount','account_amount']);
 function walk(value){if(!value||typeof value!=='object')return;for(const[key,item]of Object.entries(value)){assert.ok(!forbidden.has(key),label+' exposes '+key);walk(item);}}
 walk(data);
}
const receipt=id=>String(fixture.transactions.find(t=>t.id===id).receipt_no);
async function ownHistory(name,extra={}){
 const data=await rpc('owner',name,{...extra,search_text:''});
 sameIds(data.rows.map(r=>r.id),ownIds,name+' own rows');assert.equal(data.count,ownIds.length);noForeign(data,name);
 for(const id of foreignInvoiceIds){const search=await rpc('owner',name,{...extra,search_text:receipt(id)});assert.equal(search.count,0,name+' guessed receipt');assert.deepEqual(search.rows,[]);}
 const second=await rpc('owner',name,{...extra,page_offset:1});assert.equal(second.count,ownIds.length);assert.equal(second.rows.length,1);noForeign(second,name+' offset page');
 const later=await rpc('owner',name,{...extra,page_offset:30});assert.equal(later.count,ownIds.length);assert.deepEqual(later.rows,[]);
 return data;
}

try{
 fixture=JSON.parse(sql("select jsonb_build_object('transactions',(select jsonb_agg(to_jsonb(t)order by id)from transactions t where id between -412108 and -412101),'items',(select jsonb_agg(to_jsonb(i)order by id)from transaction_items i where transaction_id between -412106 and -412101),'requests',(select jsonb_agg(to_jsonb(r)order by request_id)from (select r.request_id,r.user_id,r.payload,r.result from solar_private.invoice_requests r join public.transactions t on t.id=(r.result->>'id')::bigint join public.profiles p on p.id=r.user_id where p.active and p.user_type not in('warehouse','installer') and t.created_by=r.user_id and p.id::text like '00000000-0000-0000-0000-%' order by r.request_id limit 2)r))"));
 assert.equal(fixture.transactions.length,transactionIds.length,'Seed the V4.12 privacy fixture before running');
 assert.ok(fixture.items.length>=invoiceIds.length,'Every fixture invoice needs material detail');
 for(const row of fixture.transactions)assert.equal(row.created_by,ids[ownTransactionIds.includes(row.id)?'owner':'foreign']);
 assert.equal(fixture.transactions.find(t=>t.id===-412104).cashbox_user_id,ids.owner,'The foreign-creator/own-cashbox case is required');
 for(const id of foreignIds)assert.ok(fixture.transactions.find(t=>t.id===id).notes,'Foreign invoices need unique private notes');
 before=fingerprint();metadataBefore=bookkeeping();

 // Raw table RLS: direct IDs, nested joins, predicates, HEAD counts, and pagination.
 const ownRaw=(await request('owner','/transactions?'+filters({select:'*',id:idFilter,order:'id'}))).data;
 sameIds(ownRaw.map(t=>t.id),ownTransactionIds,'Raw headers');noForeign(ownRaw,'Raw headers');
 const items=(await request('owner','/transaction_items?'+filters({select:'*',transaction_id:idFilter,order:'id'}))).data;
 sameIds(items.map(i=>i.id),fixture.items.filter(i=>ownIds.includes(i.transaction_id)).map(i=>i.id),'Raw item IDs');noForeign(items,'Raw items');
 const headers=(await request('owner','/transactions?'+filters({select:'*,transaction_items(*)',id:idFilter,order:'id'}))).data;
 sameIds(headers.map(t=>t.id),ownTransactionIds,'Embedded header rows');assert.ok(headers.filter(t=>ownIds.includes(t.id)).every(t=>t.transaction_items.length>0));noForeign(headers,'Embedded header/items');
 const joined=(await request('owner','/transaction_items?'+filters({select:'id,transaction_id,product_name,transactions!inner(id,created_by,party_name,total,notes)',transaction_id:idFilter,order:'id'}))).data;
 sameIds(joined.map(i=>i.id),items.map(i=>i.id),'Embedded parent join');noForeign(joined,'Embedded parent join');
 const cross=(await request('owner','/transactions?'+filters({select:'*',id:idFilter,created_by:'eq.'+ids.foreign}))).data;
 assert.deepEqual(cross,[],'Explicit foreign creator predicate');
 for(const id of foreignIds){
  assert.deepEqual((await request('owner','/transactions?'+filters({select:'*',id:'eq.'+id}))).data,[],'Known transaction ID');
  assert.deepEqual((await request('owner','/transaction_items?'+filters({select:'*',transaction_id:'eq.'+id}))).data,[],'Known transaction items');
 }
 const head=await request('owner','/transactions?'+filters({select:'id',id:idFilter}),{method:'HEAD',headers:{Prefer:'count=exact'}});
 assert.equal(head.response.headers.get('content-range')?.split('/')[1],String(ownTransactionIds.length),'HEAD count must be scoped');
 const itemHead=await request('owner','/transaction_items?'+filters({select:'id',transaction_id:idFilter}),{method:'HEAD',headers:{Prefer:'count=exact'}});
 assert.equal(itemHead.response.headers.get('content-range')?.split('/')[1],String(items.length),'Item HEAD count must be scoped');
 const collected=[];for(let offset=0;offset<=ownTransactionIds.length;offset++){
  const page=(await request('owner','/transactions?'+filters({select:'id,notes',id:idFilter,order:'id',offset:String(offset),limit:'1'}))).data;
  noForeign(page,'Raw page '+offset);collected.push(...page.map(t=>t.id));
 }sameIds(collected,ownTransactionIds,'All paginated visible IDs');
 const adminRaw=(await request('admin','/transactions?'+filters({select:'id,transaction_items(id)',id:idFilter}))).data;
 sameIds(adminRaw.map(t=>t.id),transactionIds,'Admin raw control');assert.ok(adminRaw.filter(t=>invoiceIds.includes(t.id)).every(t=>t.transaction_items.length>0));
 checks.rawHeadersItemsRelationsCountsPagination=true;

 // Both API generations must retain creator scope even with explicit owner hints.
 await ownHistory('solar_sales_history');await ownHistory('solar_sales_history_by_user',{owner_id:null});await ownHistory('solar_sales_history_by_user',{owner_id:ids.owner});
 await denied('owner','solar_sales_history_by_user',{owner_id:ids.foreign});
 const adminScoped=await rpc('admin','solar_sales_history_by_user',{owner_id:ids.foreign});sameIds(adminScoped.rows.map(t=>t.id),foreignInvoiceIds,'Admin selected seller');
 for(const name of['solar_sales_history','solar_sales_history_by_user'])for(const id of invoiceIds){const r=await rpc('admin',name,{...(name.endsWith('_by_user')?{owner_id:null}:{}),search_text:receipt(id)});assert.ok(r.rows.some(row=>row.id===id),'Admin exact receipt '+id);}
 for(const[name,args]of[['solar_sales_period',{}],['solar_sales_period_by_user',{owner_id:null}],['solar_sales_period_by_user',{owner_id:ids.owner}]]){
  const r=await rpc('owner',name,args);assert.equal(r.summary.invoiceCount,ownIds.length);noForeign(r,name);noFinancialFields(r,name);
  for(const id of foreignInvoiceIds){const found=await rpc('owner',name,{...args,search_text:receipt(id)});assert.equal(found.summary.invoiceCount,0);assert.deepEqual(found.rows,[]);}
 }
 await denied('owner','solar_sales_period_by_user',{owner_id:ids.foreign});
 const adminPeriod=await rpc('admin','solar_sales_period_by_user',{owner_id:ids.foreign});assert.equal(adminPeriod.summary.invoiceCount,foreignInvoiceIds.length);
 checks.currentLegacyHistoryAndPeriodScope=true;

 // Same customer, different invoice creators: row headers must be protected too.
 const account=await rpc('owner','solar_customer_get',{customer_id:ownCustomer});
 const statement=await rpc('owner','solar_customer_statement',{customer_id:ownCustomer});
 const adminAccount=await rpc('admin','solar_customer_get',{customer_id:ownCustomer});
 const adminStatement=await rpc('admin','solar_customer_statement',{customer_id:ownCustomer});
 const originalSnapshot=await readFile(dir+'/before-projection.json','utf8').then(JSON.parse).catch(error=>{if(error.code==='ENOENT')return null;throw error;});
 for(const[name,data]of[['customer_get',account],['customer_statement',statement]]){
  const admin=name==='customer_get'?adminAccount:adminStatement;
  noForeign(data,name);sameIds(data.rows.filter(r=>!r.receiptRestricted).map(r=>r.id),[-412101,-412107],name+' retains own sale/payment documents');
  const restricted=data.rows.filter(r=>r.receiptRestricted);
  assert.equal(restricted.length,3,name+' preserves three generic account effects');
  assert.deepEqual(restricted.map(r=>Number(r.effect)).sort((a,b)=>a-b),[-777777,7654321,9876543],name+' preserves exact foreign account effects');
  assert.equal(data.rows.length,admin.rows.length,name+' preserves complete ledger length');
  assert.equal(data.balance,admin.balance,name+' preserves full account balance');assert.equal(data.token,admin.token,name+' preserves full ledger token');
  if(originalSnapshot){assert.equal(data.balance,originalSnapshot['solar_'+name].balance,name+' pre-migration balance');assert.equal(data.token,originalSnapshot['solar_'+name].token,name+' pre-migration token');}
  for(const row of restricted){assert.ok(row.receiptNo==null,name+' redacts receipt number');assert.ok(!row.notes||!row.notes.includes('PRIVATE_'),name+' redacts original notes');}
 }
 for(const name of['solar_customer_get','solar_customer_statement'])await denied('owner',name,{customer_id:foreignCustomer});
 assert.ok(adminAccount.rows.some(r=>r.id===-412102),'Admin sees mixed-creator customer invoice');
 for(const[token,label]of[[account.token,'account'],[statement.token,'statement']]){
  const batch=await rpc('owner','solar_customer_invoice_report_batch',{customer_id:ownCustomer,invoice_ids:invoiceIds,expected_token:token});
  noForeign(batch,'Batch '+label);assert.ok(batch.rows.some(r=>r.id===-412101&&r.items.length>0),'Own invoice batch '+label);
 }
 const adminBatch=await rpc('admin','solar_customer_invoice_report_batch',{customer_id:ownCustomer,invoice_ids:invoiceIds,expected_token:adminAccount.token});
 assert.ok(adminBatch.rows.some(r=>r.id===-412102&&r.items.length>0),'Admin batch includes foreign creator');
 const documents=await rpc('owner','solar_customer_documents',{customer_id:ownCustomer,category:'all'});noForeign(documents,'Original documents');assert.ok(documents.rows.some(r=>r.movement.id===-412101));
 const ownDocument=await rpc('owner','solar_customer_movement',{customer_id:ownCustomer,movement_id:-412101});assert.equal(ownDocument.invoice.id,-412101);assert.ok(ownDocument.invoice.items.length>0);noForeign(ownDocument,'Original own invoice');
 for(const id of foreignIds)await denied('owner','solar_customer_movement',{customer_id:ownCustomer,movement_id:id});
 await denied('owner','solar_customer_documents',{customer_id:foreignCustomer,category:'all'});
 const adminDocument=await rpc('admin','solar_customer_movement',{customer_id:ownCustomer,movement_id:-412102});assert.equal(adminDocument.invoice.id,-412102);
 checks.customerHeadersItemsOriginalDocuments=true;

 // Read-only detail handlers must reject guessed foreign transaction IDs before exposing context.
 for(const id of foreignInvoiceIds){
  await denied('owner','solar_warranty_manage',{action:'get',payload:{id}});
  if(fixture.transactions.find(t=>t.id===id).kind==='sale')await denied('owner','solar_sale_preparation',{action:'get',invoice_id:id});
  await denied('owner','solar_sale_delete_preview',{invoice_id:id});
  await denied('owner','solar_receipt_delete_requests',{action:'context',payload:{invoiceId:id}});
 }
 const jobs=await rpc('owner','solar_installation_jobs');sameIds(jobs.map(r=>r.id),[-412105],'Own installation jobs');noForeign(jobs,'Installation details');
 assert.equal((await rpc('owner','solar_warranty_manage',{action:'get',payload:{id:-412101}})).id,-412101);
 assert.equal((await rpc('owner','solar_sale_preparation',{action:'get',invoice_id:-412101})).id,-412101);
 assert.ok(await rpc('admin','solar_receipt_delete_requests',{action:'context',payload:{invoiceId:-412102}}));
 assert.ok(fixture.requests?.length>=2,'Existing synthetic invoice request records are required for recovery checks');
 for(const attempt of fixture.requests){
  assert.notEqual(attempt.user_id,ids.owner,'Recovery control must belong to another synthetic fixture user');
  const resolved=await rpc(attempt.user_id,'solar_invoice_attempt_resolve',{request_id:attempt.request_id,payload:attempt.payload});assert.equal(resolved.state,'saved');assert.equal(resolved.invoice.id,Number(attempt.result.id));
  await denied('owner','solar_invoice_attempt_resolve',{request_id:attempt.request_id,payload:attempt.payload});
 }
 const ownAttempt=fixture.requests[0];
 checks.directDetailsAndExistingAttemptRecovery=true;

 // Normal seller warehouse permission does not grant another creator's documents.
 const warehouseId=fixture.transactions.find(t=>t.id===-412101).warehouse_id;assert.ok(warehouseId);
 for(const id of foreignInvoiceIds){
  const order=await rpc('owner','solar_inventory',{action:'orders',payload:{warehouseId,search:'@id:'+id,state:''}});assert.equal(order.count,0);assert.deepEqual(order.rows,[]);
  const legacy=await rpc('owner','solar_warehouse_orders',{search_text:'@id:'+id,state:''});assert.equal(legacy.count,0);assert.deepEqual(legacy.rows,[]);
 }
 const ownerStatuses=await rpc('owner','solar_warehouse_statuses',{invoice_ids:invoiceIds});sameIds(ownerStatuses.map(r=>r.id),ownIds,'Own warehouse statuses');
 for(const id of invoiceIds){
  const order=await rpc('warehouse','solar_inventory',{action:'orders',payload:{warehouseId,search:'@id:'+id,state:''}});
  assert.equal(order.count,1,'Dedicated warehouse authorized invoice '+id);assert.equal(order.rows[0].id,id);assert.ok(order.rows[0].items.length>0);noFinancialFields(order,'Dedicated warehouse quantity document');
 }
 checks.dedicatedWarehouseRetainsRedactedAccess=true;

 // Anonymous/inactive/operational identities cannot read the financial routes.
 for(const who of['warehouse','installer','inactive','anon']){
  for(const table of['transactions','transaction_items']){
   const response=await request(who,'/'+table+'?'+filters({select:'*',[table==='transactions'?'id':'transaction_id']:idFilter}),{status:who==='anon'?[200,401,403]:[200,403]});
   if(response.response.status===200)assert.deepEqual(response.data,[],who+' raw '+table);else assert.equal(response.data.code,'42501');
  }
  await denied(who,'solar_sales_history_by_user',{owner_id:null});
  await denied(who,'solar_sales_period_by_user',{owner_id:null});
  await denied(who,'solar_customer_get',{customer_id:ownCustomer});
  await denied(who,'solar_customer_statement',{customer_id:ownCustomer});
  await denied(who,'solar_customer_movement',{customer_id:ownCustomer,movement_id:-412101});
  await denied(who,'solar_customer_documents',{customer_id:ownCustomer});
  await denied(who,'solar_customer_invoice_report_batch',{customer_id:ownCustomer,invoice_ids:[-412101],expected_token:account.token});
  await denied(who,'solar_invoice_attempt_resolve',{request_id:ownAttempt.request_id,payload:ownAttempt.payload});
 }
 checks.anonymousInactiveOperationalRolesDenied=true;
 assert.equal(fingerprint(),before,'Read regressions changed financial state');assert.equal(bookkeeping(),metadataBefore,'Read regressions changed save/deletion bookkeeping');
 checks.noFinancialOrRequestWrites=true;
 await writeFile(dir+'/results.json',JSON.stringify({pass:true,db,api,checks,calls,financialFingerprint:before,bookkeepingFingerprint:metadataBefore},null,2));
 console.log('PASS V4.12 API isolation: raw headers/items/joins/counts, legacy and current history/period, mixed-creator customer reports, direct details/recovery, dedicated warehouse, role denials; financial and request fingerprints unchanged.');
}catch(error){
 await writeFile(dir+'/failure.json',JSON.stringify({pass:false,error:String(error),stack:error.stack,checks,calls,financialFingerprintBefore:before,financialFingerprintAfter:before?fingerprint():null},null,2));
 throw error;
}
