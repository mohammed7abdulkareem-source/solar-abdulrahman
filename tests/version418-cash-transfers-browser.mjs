// V4.1.8 compiled UI + real loopback API/database. Production financial traffic is blocked.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v418_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3163';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v418/cash-transfers-browser';
const {rpc,sql,cash,fingerprint,createHarness,base}=await import('./version4-browser-support.mjs');
const uid=n=>'00000000-0000-0000-0000-00000041850'+n;
const u={admin:uid(1),sender:uid(2),recipient:uid(3),other:uid(4),otherRecipient:uid(5),source:uid(6),zero:uid(7),warehouse:uid(8),inactive:uid(9)};
const transfer=n=>'00000000-0000-0000-0000-00000041860'+n;
const names=JSON.parse(sql("select jsonb_object_agg(id,display_name)from profiles where id between '"+uid(1)+"'and'"+uid(9)+"'"));
const money=s=>Number((String(s).match(/[−-]?\d[\d,]*(?:\.\d+)?/)?.[0]||'NaN').replaceAll(',','').replace('−','-'));
const profit=id=>Number(sql("select solar_private.retained_profit('"+id+"')"));
const wallet=id=>JSON.parse(sql("select solar_private.usd_wallet('"+id+"')"));
const state=(actor,payload={})=>rpc(actor,'solar_cash_workspace',{payload});
const overview=actor=>rpc(actor,'solar_cash_transfer_overview',{});
const rows=()=>JSON.parse(sql("select jsonb_agg(to_jsonb(t)order by id)from solar_private.cash_transfers t where sender_id between '"+uid(1)+"'and'"+uid(9)+"'"));
const row=id=>rows().find(r=>r.id===id);
const financialHash=()=>fingerprint()+sql("select md5(coalesce(jsonb_agg(to_jsonb(t)order by id)::text,''))from solar_private.cash_transfers t");
const untouchedHash=()=>sql("select md5(jsonb_build_array((select jsonb_agg(to_jsonb(t)order by id)from transaction_items t),(select jsonb_agg(to_jsonb(t)order by id)from products t),(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),(select jsonb_agg(to_jsonb(t)order by id)from solar_private.supplier_fx_entries t))::text)");
const path=(view='home',id='')=>'/?section=cash&cashView='+view+(id?'&cashTransfer='+id:'');
const h=await createHarness('cash-transfers-browser');
const calls=(suffix)=>h.calls.filter(c=>c.path.endsWith('/'+suffix));
async function deny(actor,name,payload){assert.equal((await rpc(actor,name,payload,403)).code,'42501');}
async function waitSource(p,expected,currency='IQD'){
 await p.waitForFunction(({expected,currency})=>{const el=document.querySelector('[data-testid="cash-handover-source-balance"]');return el&&el.dataset.currency===currency&&Number(el.textContent.replace(/[^\d.-]/g,''))===expected;},{expected,currency});
}
async function directForm(p,currency='IQD'){
 await p.goto(base+path('handover'));const form=p.getByRole('region',{name:'تسليم مباشر لمستخدم',exact:true});
 await form.getByLabel('القاصة الدافعة للتسليم',{exact:true}).selectOption(u.source);
 await form.getByLabel('المستخدم المستلم للتسليم',{exact:true}).selectOption(u.zero);
 await form.getByLabel('عملة التسليم المباشر',{exact:true}).selectOption(currency);
 await waitSource(p,currency==='IQD'?1250000:250.5,currency);
 await form.getByRole('button',{name:'كامل مبلغ القاصة',exact:true}).click();
 await p.waitForFunction(expected=>{const el=document.querySelector('[aria-label="مبلغ التسليم المباشر"]');return el&&Number(el.value.replace(/[^\d.-]/g,''))===expected;},currency==='IQD'?1250000:250.5);
 await form.getByLabel('بيان التسليم المباشر',{exact:true}).fill('تسليم مباشر '+currency+' V418');
 assert.equal(money(await form.getByLabel('مبلغ التسليم المباشر',{exact:true}).inputValue()),currency==='IQD'?1250000:250.5);
 const before=financialHash();await form.getByRole('button',{name:'معاينة التسليم',exact:true}).click();
 await form.getByRole('button',{name:'تأكيد التسليم وإضافة المبلغ لقاصته',exact:true}).waitFor();assert.equal(financialHash(),before);
 return form;
}

try{
 const initial=financialHash(),untouched=untouchedHash();
 const aState=await state(u.admin),sState=await state(u.sender),aOverview=await overview(u.admin),sOverview=await overview(u.sender);
 // Pending summary and its rows are from the same authorized server snapshot.
 assert.equal(aOverview.rows.filter(r=>r.status==='pending').length,4);
 assert.deepEqual(sOverview.rows.filter(r=>r.status==='pending').map(r=>r.id).sort(),[transfer(1),transfer(2),transfer(3)].sort());
 assert.equal(sOverview.rows.some(r=>r.id===transfer(4)),false);
 assert.equal(sState.owners.length,1);assert.equal(sState.owners[0].id,u.sender);
 assert.equal(aState.summary.transit,1235387890);
 assert.equal(aState.summary.pendingIQD,1235387890);assert.equal(aState.summary.pendingCount,4);
 assert.equal(sState.summary.pendingIQD,1235087890);assert.equal(sState.summary.pendingCount,3);
 for(const snapshot of[aState,sState]){
  assert.equal(snapshot.pendingTransfers.reduce((n,r)=>n+r.amount,0),snapshot.summary.pendingIQD);
  assert.equal(snapshot.pendingTransfers.length,snapshot.summary.pendingCount);
  for(const item of snapshot.pendingTransfers){assert.deepEqual(Object.keys(item).sort(),['id','sender_id','recipient_id','senderName','recipientName','amount','currency','created_at','status'].sort());assert.equal(item.currency,'IQD');assert.equal(item.status,'pending');assert.equal(item.senderName,names[item.sender_id]);assert.equal(item.recipientName,names[item.recipient_id]);}
  assert.equal(snapshot.owners.reduce((n,r)=>n+r.IQD,0),snapshot.summary.availableIQD);
  assert.ok(Math.abs(snapshot.owners.reduce((n,r)=>n+r.USD,0)-snapshot.summary.availableUSD)<1e-8);
 }
 assert.deepEqual(sState.pendingTransfers.map(r=>r.id).sort(),[transfer(1),transfer(2),transfer(3)].sort());
 const scoped=await state(u.admin,{ownerId:u.otherRecipient,from:'2099-01-01',to:'2099-01-02',query:'no-ledger-match'});
 assert.deepEqual(scoped.pendingTransfers.map(r=>r.id).sort(),[transfer(2),transfer(4)].sort());assert.equal(scoped.summary.pendingIQD,420000);
 for(const forbidden of[u.warehouse,u.inactive]){assert.equal(aOverview.managers.some(m=>m.id===forbidden),false);await deny(u.sender,'solar_cash_transfer_send',{request_id:randomUUID(),recipient:forbidden,send_amount:1,expense_amount:0,note:'مستلم غير مخول V418'});} 
 assert.equal(cash(u.sender),765227110);assert.equal(cash(u.recipient),51000);assert.equal(profit(u.sender),-35000);
 for(const decision of['accepted','rejected'])await deny(u.admin,'solar_cash_transfer_decide',{request_id:transfer(1),decision});
 await deny(u.otherRecipient,'solar_cash_transfer_decide',{request_id:transfer(1),decision:'cancelled'});
 await deny(u.sender,'solar_cash_reconcile',{action:'context',payload:{ownerId:u.sender}});
 await deny(u.sender,'solar_cash_save',{request_id:randomUUID(),payload:{mode:'capital_withdraw',ownerId:u.sender,currency:'IQD',amount:1,note:'محاولة غير مخولة V418'}});
 assert.equal(financialHash(),initial);h.checks.initialPendingPrivacyBalancesAndV417Guards=true;

 // Both roles see explicit from/to pairs and open that exact transfer.
 const admin=await h.open(u.admin,path()),a=admin.page;await a.waitForLoadState('networkidle');
 let pending=a.getByRole('region',{name:'التحويلات المعلقة',exact:true});await pending.getByTestId('cash-pending-iqd').waitFor();
 assert.equal(money(await pending.getByTestId('cash-pending-iqd').innerText()),aState.summary.pendingIQD);
 await pending.getByRole('button',{name:/عرض بقية التحويلات/}).click();await pending.locator('[data-transfer-id]').nth(3).waitFor();
 assert.deepEqual((await pending.locator('[data-transfer-id]').evaluateAll(els=>els.map(el=>el.dataset.transferId))).sort(),aState.pendingTransfers.map(r=>r.id).sort());
 for(const item of aState.pendingTransfers){const card=pending.locator('[data-transfer-id="'+item.id+'"]');assert.ok((await card.innerText()).includes(item.senderName));assert.ok((await card.innerText()).includes(item.recipientName));assert.equal(money(await card.locator('.cfPendingFacts bdi').innerText()),item.amount);}
 assert.equal(money(await a.getByTestId('cash-iqd').innerText()),aState.summary.availableIQD);
 assert.ok((await pending.locator('.cfPendingParties b').evaluateAll(els=>els.every(el=>parseFloat(getComputedStyle(el).fontSize)>=14&&el.scrollWidth<=el.clientWidth+1))),'pending names remain readable and wrap without clipping');
 await h.layout(a,'admin-pending-overview',pending);await a.evaluate(()=>scrollTo(0,0));await a.screenshot({path:h.dir+'/admin-home-top-390.png'});
 // A mismatched snapshot must never leave a stale, apparently confirmed total.
 let corrupted=false;h.setIntercept(async({route,call,response})=>{if(!corrupted&&call.who===u.admin&&call.path.endsWith('/solar_cash_workspace')&&response.ok()){corrupted=true;const data=await response.json();data.summary.pendingIQD+=1;call.expectedFailure='Local pending total mismatch';await route.fulfill({status:200,json:data});return true;}return false;});
 await a.getByRole('button',{name:'تحديث الصندوق',exact:true}).click();await pending.getByRole('alert').filter({hasText:'تعذر تأكيد التحويلات'}).waitFor();assert.equal(await pending.getByTestId('cash-pending-iqd').count(),0);h.setIntercept(null);
 await pending.getByRole('button',{name:'إعادة التحديث',exact:true}).click();await pending.getByTestId('cash-pending-iqd').waitFor();assert.equal(money(await pending.getByTestId('cash-pending-iqd').innerText()),aState.summary.pendingIQD);
 h.checks.inconsistentPendingSnapshotHiddenUntilConfirmedRetry=true;
 await pending.locator('[data-transfer-id="'+transfer(4)+'"]').click();await a.locator('#transfer-'+transfer(4)+'[data-selected="true"]').waitFor();
 assert.equal(new URL(a.url()).searchParams.get('cashTransfer'),transfer(4));
 const adminForeign=a.locator('#transfer-'+transfer(4));assert.equal(await adminForeign.getByRole('button',{name:/استلام المبلغ|إلغاء الطلب|رفض وإرجاع/}).count(),0);
 await h.layout(a,'admin-exact-pending-transfer',adminForeign);
 const sender=await h.open(u.sender,path()),s=sender.page;await s.waitForLoadState('networkidle');pending=s.getByRole('region',{name:'التحويلات المعلقة',exact:true});await pending.getByTestId('cash-pending-iqd').waitFor();
 assert.equal(money(await pending.getByTestId('cash-pending-iqd').innerText()),sState.summary.pendingIQD);await pending.locator('[data-transfer-id]').nth(2).waitFor();
 assert.deepEqual((await pending.locator('[data-transfer-id]').evaluateAll(els=>els.map(el=>el.dataset.transferId))).sort(),sState.pendingTransfers.map(r=>r.id).sort());
 assert.equal(await pending.locator('[data-transfer-id="'+transfer(4)+'"]').count(),0);await h.layout(s,'staff-pending-overview',pending);
 await pending.locator('[data-transfer-id="'+transfer(3)+'"]').click();await s.locator('#transfer-'+transfer(3)+'[data-selected="true"]').waitFor();
 assert.equal(new URL(s.url()).searchParams.get('cashTransfer'),transfer(3));
 await s.goto(base+path('transfers',transfer(4)));await s.getByRole('tab',{name:'السجل',exact:true}).waitFor();await s.getByTestId('cash-transfer-balance').waitFor();assert.equal(await s.locator('#transfer-'+transfer(4)).count(),0);
 await s.goto(base+'/?section=cash&cashView=reconcile');await s.getByRole('alert').filter({hasText:'غير متاح ضمن صلاحياتك'}).waitFor();assert.equal(await s.getByLabel('قاصة التسوية',{exact:true}).count(),0);
 const receiveOnly=await h.open(u.source,path('transfers')),receivePage=receiveOnly.page;await receivePage.waitForLoadState('networkidle');
 const restoredKey='solar-cash-record-attempt-v1:'+u.source+':transfer-send',restoredAttempt={id:randomUUID(),payload:{recipient:u.recipient,send_amount:100,expense_amount:0,expense_note:'',note:'محاولة قديمة بعد إلغاء صلاحية الإرسال V418'}};
 await receivePage.evaluate(({key,value})=>localStorage.setItem(key,JSON.stringify(value)),{key:restoredKey,value:restoredAttempt});const sendBefore=calls('solar_cash_transfer_send').length;await receivePage.reload();await receivePage.getByRole('region',{name:'طلبات الاستلام',exact:true}).waitFor();
 assert.equal(await receivePage.getByRole('tab',{name:'إرسال',exact:true}).count(),0);assert.equal(await receivePage.getByRole('button',{name:'تأكيد طلب التسليم السابق',exact:true}).count(),0);assert.deepEqual(await receivePage.evaluate(key=>JSON.parse(localStorage.getItem(key)),restoredKey),restoredAttempt);assert.equal(calls('solar_cash_transfer_send').length,sendBefore);
 h.checks.receiveOnlyRolePreservesOldSendAttemptWithoutReplaying=true;
 assert.equal(financialHash(),initial);h.checks.pendingFromToExactNavigationOwnPrivacyAndNoReadWrites=true;
 const recipient=await h.open(u.recipient,path('transfers',transfer(1))),r=recipient.page;
 h.setCurrent(r);await r.locator('#transfer-'+transfer(1)).waitFor();await h.layout(r,'recipient-pending-transfer',r.locator('#transfer-'+transfer(1)));

 // Real recipient acceptance and sender cancellation retain pre-transfer expenses.
 await r.locator('#transfer-'+transfer(1)).getByRole('button',{name:'استلام المبلغ',exact:true}).click();
 await r.locator('#transfer-'+transfer(1)).getByRole('button',{name:'تأكيد الاستلام',exact:true}).click();
 await r.getByText('تم استلام المبلغ وإضافته إلى قاصتك.',{exact:true}).waitFor();
 assert.equal(row(transfer(1)).status,'accepted');assert.equal(cash(u.recipient),1234618890);assert.equal(cash(u.sender),765227110);assert.equal(profit(u.sender),-35000);
 const accepted=financialHash();await rpc(u.recipient,'solar_cash_transfer_decide',{request_id:transfer(1),decision:'accepted'},204);assert.equal(financialHash(),accepted);
 h.setCurrent(s);await s.goto(base+path('transfers',transfer(2)));await s.locator('#transfer-'+transfer(2)).getByRole('button',{name:'إلغاء الطلب',exact:true}).click();
 await s.locator('#transfer-'+transfer(2)).getByRole('button',{name:'تأكيد إلغاء الطلب',exact:true}).click();
 await s.getByText(/أعيد مبلغ التحويل إلى قاصة .*المصروف السابق يبقى مسجّلًا/).waitFor();assert.equal(cash(u.sender),765347110);assert.equal(profit(u.sender),-35000);assert.equal(row(transfer(2)).status,'cancelled');
 await s.goto(base+path('transfers',transfer(3)));await s.locator('#transfer-'+transfer(3)).getByRole('button',{name:'استلام المبلغ',exact:true}).click();
 await s.locator('#transfer-'+transfer(3)).getByRole('button',{name:'تأكيد الاستلام',exact:true}).click();
 await s.getByText('تم استلام المبلغ وإضافته إلى قاصتك.',{exact:true}).waitFor();assert.equal(cash(u.sender),765747110);
 h.checks.recipientAcceptanceSenderCancellationAndExpenseRetention=true;

 // Full balance rereads the current source, excludes the optional expense, and
 // only commits after review. A lost acknowledgement reuses the stored request.
 await s.goto(base+path('transfers'));await s.getByRole('tab',{name:'إرسال',exact:true}).click();
 const send=s.getByRole('region',{name:'إرسال واستلام الأموال',exact:true});
 await send.getByLabel('مستلم القاصة',{exact:true}).selectOption(u.recipient);
 await send.getByRole('button',{name:/مصروف قبل الإرسال/}).click();
 await send.getByLabel('مصروف قبل التسليم',{exact:true}).fill('12345');
 await send.getByLabel('بيان مصروف التسليم',{exact:true}).fill('مصروف التحويل الكامل V418');
 await send.getByLabel('ملاحظة التسليم',{exact:true}).fill('تحويل كامل بعد مراجعة V418');
 await rpc(u.admin,'solar_cash_save',{request_id:randomUUID(),payload:{ownerId:u.sender,mode:'deposit',currency:'IQD',amount:89,note:'رصيد جديد قبل كامل المبلغ V418'}});
 const freshCash=cash(u.sender),sendAmount=freshCash-12345;
 await send.getByRole('button',{name:/^كامل المبلغ المتاح/}).click();
 await s.waitForFunction(expected=>{const el=document.querySelector('[aria-label="مبلغ تسليم القاصة"]');return el&&Number(el.value.replace(/[^\d.-]/g,''))===expected;},sendAmount);
 assert.equal(money(await send.getByLabel('مبلغ تسليم القاصة',{exact:true}).inputValue()),sendAmount);
 const beforeReview=financialHash();await send.getByRole('button',{name:'مراجعة التحويل',exact:true}).click();
 await send.getByRole('button',{name:'تأكيد إرسال المبلغ',exact:true}).waitFor();assert.equal(financialHash(),beforeReview);
 await h.layout(s,'sender-transfer-review',send);
 let lostSend=false;h.setIntercept(async({route,call,response})=>{if(!lostSend&&call.path.endsWith('/solar_cash_transfer_send')&&response.ok()){lostSend=true;call.expectedFailure='Local committed transfer response intentionally lost';await route.abort('failed');return true;}return false;});
 await send.getByRole('button',{name:'تأكيد إرسال المبلغ',exact:true}).evaluate(el=>{el.click();el.click();});
 await send.getByRole('button',{name:'تأكيد طلب التسليم السابق',exact:true}).waitFor();
 assert.equal(cash(u.sender),0);assert.equal(profit(u.sender),-47345);assert.equal(cash(u.recipient),1234618890);
 const committedSend=calls('solar_cash_transfer_send').filter(c=>c.body?.note==='تحويل كامل بعد مراجعة V418');assert.equal(committedSend.length,1);
 const attempt=committedSend[0].body;assert.equal(row(attempt.request_id).status,'pending');assert.equal(row(attempt.request_id).amount,sendAmount);
 const afterSend=financialHash();await s.reload();await s.getByRole('button',{name:'تأكيد طلب التسليم السابق',exact:true}).click();
 await s.getByText(/تم إرسال المبلغ إلى .*بانتظار تأكيد الاستلام/).waitFor();h.setIntercept(null);assert.equal(financialHash(),afterSend);
 const sendCalls=calls('solar_cash_transfer_send').filter(c=>c.body?.note==='تحويل كامل بعد مراجعة V418');assert.equal(sendCalls.length,2);assert.deepEqual(sendCalls[0].body,sendCalls[1].body);
 assert.equal((await rpc(u.sender,'solar_cash_transfer_send',{...attempt,send_amount:sendAmount-1},409)).code,'PT409');assert.equal(financialHash(),afterSend);
 await s.goto(base+path('transfers',attempt.request_id));await s.locator('#transfer-'+attempt.request_id).getByRole('button',{name:'إلغاء الطلب',exact:true}).click();await s.locator('#transfer-'+attempt.request_id).getByRole('button',{name:'تأكيد إلغاء الطلب',exact:true}).click();
 await s.getByText(/أعيد مبلغ التحويل إلى قاصة .*المصروف السابق يبقى مسجّلًا/).waitFor();assert.equal(cash(u.sender),sendAmount);assert.equal(profit(u.sender),-47345);
 assert.equal(Number(sql("select count(*)from solar_cash_entries where entry_type='handover_expense'and transfer_id='"+attempt.request_id+"'and delta=-12345 and notes='مصروف التحويل الكامل V418'")),1);
 h.checks.fullAmountFreshReviewRepeatedClickLostAcknowledgementAndCancel=true;

 // Direct administrator handover remains immediate, independent of pending transfers.
 h.setCurrent(a);let form=await directForm(a);await h.layout(a,'direct-handover-preview',form);
 const pendingBefore=rows().filter(r=>r.status==='pending').length;
 await form.getByRole('button',{name:'تأكيد التسليم وإضافة المبلغ لقاصته',exact:true}).evaluate(el=>{el.click();el.click();});
 await form.getByText('تم تسليم المبلغ وإضافته إلى قاصة المستلم.',{exact:true}).waitFor();
 assert.equal(cash(u.source),0);assert.equal(cash(u.zero),1250000);assert.equal(Number(wallet(u.source).amount),250.5);
 assert.equal(rows().filter(r=>r.status==='pending').length,pendingBefore);
 const directCalls=calls('solar_cash_record').filter(c=>c.body?.action==='transfer'&&c.body?.payload?.note==='تسليم مباشر IQD V418');assert.equal(directCalls.length,1);
 const html=await h.report(a,admin.ctx,form.locator('.reportExport'),'direct-handover-iqd');
 assert.ok(html.includes(names[u.source])&&html.includes(names[u.zero]));assert.ok(html.includes('1,250,000'));
 form=await directForm(a,'USD');let lost=false;
 h.setIntercept(async({route,call,response})=>{if(!lost&&call.path.endsWith('/solar_cash_record')&&call.body?.action==='transfer'&&call.body?.payload?.currency==='USD'&&response.ok()){lost=true;call.expectedFailure='Local committed response intentionally lost';await route.abort('failed');return true;}return false;});
 await form.getByRole('button',{name:'تأكيد التسليم وإضافة المبلغ لقاصته',exact:true}).click();await form.getByRole('button',{name:'تأكيد طلب التسليم السابق',exact:true}).waitFor();
 assert.equal(Number(wallet(u.source).amount),0);assert.equal(Number(wallet(u.zero).amount),250.5);assert.equal(await form.getByTestId('cash-handover-source-balance').count(),0);
 await a.reload();form=a.getByRole('region',{name:'تسليم مباشر لمستخدم',exact:true});await form.getByRole('button',{name:'تأكيد طلب التسليم السابق',exact:true}).click();
 await form.getByText('تم تسليم المبلغ وإضافته إلى قاصة المستلم.',{exact:true}).waitFor();h.setIntercept(null);
 const dollarCalls=calls('solar_cash_record').filter(c=>c.body?.action==='transfer'&&c.body?.payload?.note==='تسليم مباشر USD V418');assert.equal(dollarCalls.length,2);assert.equal(dollarCalls[0].body.request_id,dollarCalls[1].body.request_id);
 assert.equal(Number(wallet(u.zero).amount),250.5);assert.equal(Number(wallet(u.zero).book),415830);assert.equal(Number(wallet(u.source).book),0);assert.equal(cash(u.zero),1250000);assert.equal(cash(u.admin),5000000);assert.equal(Number(wallet(u.admin).amount),123.45);assert.equal(profit(u.source),0);assert.equal(profit(u.zero),0);
 h.checks.directHandoverCurrenciesPDFAndLostResponseRetryPreserved=true;
 assert.equal(untouchedHash(),untouched);h.checks.stockInvoiceItemsAndSuppliersUntouched=true;
 await h.finish();console.log('PASS V4.1.8 cash overview and transfer design, real local API/database accounting, privacy and retries.');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
