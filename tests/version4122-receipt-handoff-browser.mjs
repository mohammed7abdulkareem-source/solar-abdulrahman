// Real browser, authenticated PostgREST requests and accounting assertions in a disposable database.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

process.env.SOLAR_FIXTURE_DB ||= 'solar_v4122_installation_handoff_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3300';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3301';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4122/release-browser';
const {api,db,ids,cash,scalar,sql,rpc,tokenFor,createHarness}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4122_installation_handoff_browser');
const partyId=Date.now(),productId=partyId+1;
const party='عميل تسليم المنظومات '+partyId;
const a=randomUUID(),b=randomUUID(),c=randomUUID();
const button=(page,name)=>page.getByRole('button',{name,exact:true});
const check=(dialog,r)=>dialog.getByRole('checkbox',{name:'نقل وصل #'+r.receiptNo,exact:true});
const request=()=>randomUUID();
const own=(id)=>sql('select owner_id from customers where id='+id);
const getRecord=()=>rpc(ids.admin,'solar_customer_get',{customer_id:partyId});
const getChoices=(who=ids.admin)=>rpc(who,'solar_customer_transfer_receipts',{customer_id:partyId});
const jobs=who=>rpc(who,'solar_installation_jobs',{});
const revision=id=>scalar('select installation_revision from transactions where id='+Number(id));
const act=(who,id,action,payload={},expected=204,version=revision(id))=>rpc(who,'solar_installation_action',{job_id:id,expected_revision:version,action,payload},expected);
const payout=(uid,id)=>scalar("select coalesce(-sum(delta),0) from solar_cash_entries where owner_id='"+uid+"' and job_id="+Number(id));
const recordProfit=id=>scalar('select profit from transactions where id='+Number(id));
function snapshot(){
 return sql(`with t as (select * from public.transactions where party_id=${partyId}) select jsonb_build_array(
 (select jsonb_agg(to_jsonb(t) order by t.id) from t),
 (select jsonb_agg(to_jsonb(i) order by i.id) from public.transaction_items i join t on t.id=i.transaction_id),
 (select jsonb_agg(to_jsonb(l) order by l.transaction_id) from public.cash_ledger l join t on t.id=l.transaction_id),
 (select jsonb_agg(to_jsonb(e) order by e.id) from public.solar_cash_entries e join t on t.id=e.job_id),
 (select to_jsonb(p) from public.products p where p.id=${productId}),
 (select jsonb_agg(to_jsonb(s) order by s.warehouse_id) from solar_private.warehouse_stocks s where s.product_id=${productId})
 )`);
}
async function seed(){
 const permissions={sale:true,system:true,customers:true,systemPayment:true,installations:true,customerStatement:true,cash:true,wholesaleFreePricing:true};
 for(const [id,label] of [[a,'الأصلي'],[b,'المستلم'],[c,'الخارجي']]){
  sql(`insert into public.profiles(id,username,display_name,user_type,is_admin,active,phone,permissions)
   values('${id}','u_${id}','المسؤول ${label} ${partyId}','admin_staff',false,true,'07700000000','${JSON.stringify(permissions)}'::jsonb)`);
 }
 sql(`begin;
 insert into customers(id,name,customer_type,owner_id) values(${partyId},'${party}','system','${a}');
 insert into products(id,code,name,category,qty,cost) values(${productId},'HAND-${productId}','مادة اختبار التسليم','ألواح',20,100000);
 insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(1,${productId},20) on conflict(warehouse_id,product_id) do update set qty=excluded.qty;
 commit;`);
 const docs=[];
 for(const total of [550000,650000,750000]){
  const data=await rpc(a,'solar_invoice_save',{request_id:request(),payload:{kind:'system',mode:'credit',partyId,party,total,customerAddress:'موقع الاختبار',installerId:ids.installer,warehouseId:1,items:[{id:productId,qty:1,price:0}]}});
  docs.push({id:Number(data.id),receiptNo:scalar('select receipt_no from transactions where id='+Number(data.id))});
 }
 // Place all three real invoices at the same ready-for-installation stage.
 sql('update public.transactions set warehouse_status=\'ready\' where id in ('+docs.map(r=>r.id).join(',')+')');
 await act(a,docs[0].id,'close',{amount:40000,notes:'نفقة قبل التحويل'});
 return docs;
}
async function choose(account,receipt,disabled){
 await button(account,'تحويل الزبون').click();
 const dialog=account.getByRole('dialog',{name:'تحويل الزبون'});
 await dialog.getByRole('combobox',{name:/المسؤول الجديد/}).selectOption(b);
 const target=check(dialog,receipt);
 await target.waitFor();
 assert.equal(await target.isChecked(),false);
 if(disabled)assert.equal(await check(dialog,disabled).isDisabled(),true);
 await target.check();
 assert.equal(await dialog.getByRole('checkbox',{checked:true}).count(),1);
 return dialog;
}
async function saveChoice(account,dialog,receipt){
 await button(dialog,'مراجعة التحويل').click();
 const confirm=button(dialog,'تأكيد تحويل الزبون');
 assert.match(await dialog.innerText(),new RegExp(String(receipt.receiptNo)));
 await confirm.click();
 await dialog.waitFor({state:'hidden'});
 await account.getByRole('status').filter({hasText:/تم تحويل|تم إسناد/}).first().waitFor();
}
async function listByResponsibility(person,docs,expected){
 const rows=await jobs(person);
 assert.deepEqual(docs.map(d=>!!rows.find(r=>Number(r.id)===d.id&&r.canManage)),expected);
 return rows;
}
const financialCheck=(who,expected)=>assert.equal(cash(who),expected);
const h=await createHarness('selected-receipt-handoff');
try{
 const docs=await seed();
 const [closed,open,unselected]=docs;
 const firstSnapshot=snapshot();
 const balances=[a,b].map(cash);
 const choices=await getChoices();
 assert.equal(choices.receipts.length,3);
 assert.ok(choices.receipts.every(r=>r.ownerId===a));
 const old=await getRecord();
 await rpc(a,'solar_customer_transfer_receipts',{customer_id:partyId},403);
 await rpc(c,'solar_customer_save',{action:'transfer_owner',request_id:request(),payload:{id:partyId,ownerId:b,token:old.token,receiptToken:choices.receiptToken,receiptIds:[open.id]}},403);
 const admin=(await h.open('admin','/?section=customerStatement')).page;
 await admin.getByRole('combobox',{name:'بحث عميل الكشف'}).fill(party);
 await admin.getByRole('option',{name:new RegExp(party)}).click();
 await admin.getByRole('heading',{name:party,exact:true}).waitFor();
 let dialog=await choose(admin,closed);
 await h.layout(admin,'admin-receipt-selection',check(dialog,closed));
 await saveChoice(admin,dialog,closed);
 assert.equal(own(partyId),b);
 assert.equal(snapshot(),firstSnapshot);
 assert.deepEqual([a,b].map(cash),balances);
 const first=h.calls.find(x=>x.path.endsWith('/solar_customer_save')&&x.body?.action==='transfer_owner').body;
 assert.deepEqual(first.payload.receiptIds.map(Number),[closed.id]);
 await rpc('admin','solar_customer_save',first);
 assert.equal(snapshot(),firstSnapshot);
 await rpc('admin','solar_customer_save',{...first,request_id:request(),payload:{...first.payload,receiptIds:[open.id]}},409);
 await listByResponsibility(b,docs,[true,false,false]);
 await listByResponsibility(a,docs,[false,true,true]);
 dialog=await choose(admin,open,closed);
 assert.equal(await check(dialog,unselected).isChecked(),false);
 await saveChoice(admin,dialog,open);
 assert.equal(snapshot(),firstSnapshot);
 assert.deepEqual([a,b].map(cash),balances);
 const assigned=(await getChoices()).receipts;
 assert.deepEqual(docs.map(d=>assigned.find(r=>Number(r.id)===d.id).ownerId),[b,b,a]);
 assert.equal(scalar('select count(*) from solar_private.customer_receipt_responsibility where customer_id='+partyId),2);
 h.checks.transfer={oneOfThree:true,existingCustomerAdditionalReceipt:true,historicalTransactionsAndCashUnchanged:true,exactRetry:true,staleDifferentRequestDenied:true};
 const recipientStatement=await rpc(b,'solar_customer_statement',{customer_id:partyId});
 assert.deepEqual(recipientStatement.rows.filter(r=>!r.receiptRestricted).map(r=>Number(r.id)).sort(),[closed.id,open.id].sort());
 assert.ok(recipientStatement.rows.filter(r=>!r.receiptRestricted).every(r=>r.assignedReceipt&&r.canFollowInstallation&&!r.canEditReceipt&&!r.canDeleteReceipt));
 const hidden=recipientStatement.rows.filter(r=>r.receiptRestricted);
 assert.equal(hidden.length,1);assert.equal(hidden[0].receiptNo,undefined);
 assert.equal(Number(hidden[0].effect),750000);
 const currentDocs=await rpc(b,'solar_customer_documents',{customer_id:partyId,category:'invoices'});
 assert.equal(currentDocs.count,2);
 const history=(user,flag)=>rpc(user,'solar_sales_history_by_user',{owner_id:user,search_text:party,sale_kind:'system',date_from:null,date_to:null,job_status:'',page_offset:0,include_assigned:flag});
 const operationalRows=(await history(b,true)).rows;
 assert.deepEqual(operationalRows.map(r=>Number(r.id)).sort(),[open.id,closed.id].sort());
 assert.ok(operationalRows.every(r=>r.assignedReceipt&&r.operationalOwnerId===b&&r.created_by===a&&r.cost===undefined&&r.profit===undefined));
 assert.equal((await history(b,false)).rows.length,0);
 assert.equal((await history(c,true)).rows.length,0);
 assert.equal((await history(a,false)).rows.length,3);
 h.checks.archiveAndStatement={assignedDocuments:currentDocs.count,financialPeriodSalesRemainWithOriginalSeller:true,delegatedArchiveCostAndProfitRedacted:true,statementFollowAllowed:true};
 const endUser=(await h.open(b,'/?section=customerStatement')).page;
 await endUser.getByRole('combobox',{name:'بحث عميل الكشف'}).fill(party);
 await endUser.getByRole('option',{name:new RegExp(party)}).click();
 await endUser.getByRole('heading',{name:party,exact:true}).waitFor();
 assert.equal(await button(endUser,'تحويل الزبون').count(),0);
 await listByResponsibility(b,docs,[true,true,false]);
 await listByResponsibility(a,docs,[false,false,true]);
 await listByResponsibility(c,docs,[false,false,false]);
 await act(a,closed.id,'reopen',{},403);
 await act(b,unselected.id,'close',{amount:10000},403);
 await act(c,open.id,'close',{amount:10000},403);
 const actions=endUser.getByRole('group',{name:'إجراءات وصل البيع #'+open.receiptNo,exact:true});
 await button(actions.first(),'فتح ملف التنصيب').click();
 await endUser.locator('.workflowJob').filter({has:endUser.getByText('ملف #'+open.receiptNo,{exact:true})}).waitFor();
 h.checks.followFromCustomerAccount=true;
 const archive=(await h.open(b,'/?section=salesHistory')).page;
 const archiveCard=archive.locator('.saleHistoryCard').filter({hasText:party}).first();
 await archiveCard.waitFor();
 await button(archiveCard,'متابعة ملف التنصيب').click();
 await archive.locator('.workflowJob').filter({hasText:party}).first().waitFor();
 h.checks.followFromSalesArchive=true;
 const employee=(await h.open(b,'/?section=installations')).page;
 await button(employee,'الكل').click();
 await employee.getByLabel('بحث بالتنصيبات').fill(party);
 const card=doc=>employee.locator('.workflowJob').filter({has:employee.getByText('ملف #'+doc.receiptNo,{exact:true})});
 const paid=card(closed),fresh=card(open);
 await paid.waitFor();await fresh.waitFor();
 assert.equal(await card(unselected).count(),0);
 await button(paid,'إعادة فتح للمراجعة').click();
 const amount=paid.getByLabel('المصاريف النهائية للمنظومة',{exact:true});
 await amount.waitFor();await amount.fill('65000');
 const priorRev=revision(closed.id);
 await h.layout(employee,'receiving-user-expense',amount);
 await button(paid,'اعتماد المصاريف وإغلاق الملف').click();
 await button(paid,'إعادة فتح للمراجعة').waitFor();
 assert.equal(payout(a,closed.id),40000);
 assert.equal(payout(b,closed.id),25000);
 financialCheck(a,balances[0]);financialCheck(b,balances[1]-25000);
 assert.equal(recordProfit(closed.id),550000-100000-65000);
 await act(b,closed.id,'close',{amount:65000},409,priorRev);
 financialCheck(b,balances[1]-25000);
 const freshAmount=fresh.getByLabel('المصاريف النهائية للمنظومة',{exact:true});
 await freshAmount.fill('30000');
 await button(fresh,'اعتماد المصاريف وإغلاق الملف').click();
 await button(fresh,'إعادة فتح للمراجعة').waitFor();
 assert.equal(payout(b,open.id),30000);
 assert.equal(payout(a,open.id),0);
 financialCheck(a,balances[0]);financialCheck(b,balances[1]-55000);
 assert.equal(recordProfit(open.id),650000-100000-30000);
 assert.equal(recordProfit(unselected.id),750000-100000);
 assert.equal(scalar("select count(*) from public.transactions where party_id="+partyId+" and created_by='"+a+"'"),3);
 h.checks.receivingUser={oldApprovalRetained:40000,newExpenseDifference:25000,firstApproval:30000,cashAndProfitVerified:true,staleClosePreventsDuplicateCharge:true,unselectedAndOtherEmployeeDenied:true};
 // Two administrators have the same receipt preview and submit two different decisions.
 const beforeRace=snapshot();
 const latest=await getRecord(),list=await getChoices();
 const write=ownerId=>fetch(api+'/rpc/solar_customer_save',{method:'POST',
  headers:{authorization:'Bearer '+tokenFor(ids.admin),'content-type':'application/json'},
  body:JSON.stringify({action:'transfer_owner',request_id:request(),payload:{
   id:partyId,ownerId,token:latest.token,receiptToken:list.receiptToken,receiptIds:[unselected.id]
  }})
 });
 const simultaneous=await Promise.all([write(b),write(c)]);
 assert.deepEqual(simultaneous.map(r=>r.status).sort(),[200,409]);
 const winner=simultaneous[0].status===200?b:c;
 assert.equal(own(partyId),winner);
 assert.equal((await getChoices()).receipts.find(r=>Number(r.id)===unselected.id).ownerId,winner);
 assert.equal(snapshot(),beforeRace);
 h.checks.competingSelections={accepted:1,stale:1,assignmentAndAccountAgree:true};
 await h.finish();
 console.log('PASS receipt selection, follow-up assignment, receiving user expenses and close, cash journals, profits and access boundaries');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
