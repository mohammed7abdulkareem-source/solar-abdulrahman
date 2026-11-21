// Exercise the engineer and office-review flow using a shared, isolated PostgREST database.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

process.env.SOLAR_FIXTURE_DB ||= 'solar_v4123_installation_report_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3310';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3311';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4123/release-browser';
const {db,sql,scalar,cash,rpc,createHarness,ids}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4123_installation_report_browser');
const sample=Date.now(),party='زبون مراجعة التنصيب '+sample;
const original=randomUUID(),reviewer=randomUUID(),engineer=randomUUID(),peer=randomUUID(),otherOffice=randomUUID();
const engineerName='صفاء الاختبار '+sample,reviewerName='مسؤول مراجعة الاختبار '+sample;
const report='اختُبرت المنظومة وسُلّمت مع الملحقات.';
const reason='أضف نتيجة فحص التخزين إلى التقرير.';
const corrected=report+' اشتغل التخزين بعد فصل التغذية.';
const chargeNote='بيان مالي داخلي للتسوية';
const jobs=who=>rpc(who,'solar_installation_jobs',{});
const button=(p,name)=>p.getByRole('button',{name,exact:true});
const noticeCount=(who,id,event)=>scalar("select count(*) from public.solar_notifications where user_id='"+who+"' and job_id="+id+" and event='"+event+"'");
const revision=id=>scalar('select installation_revision from public.transactions where id='+id);
const action=(who,id,action,payload,expected=204,version=revision(id))=>rpc(who,'solar_installation_action',{job_id:id,expected_revision:version,action,payload},expected);
const beforeMoney=(id)=>sql("select coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]') from solar_cash_entries e where job_id="+id);
const jobFrom=async(who,id)=>(await jobs(who)).find(row=>Number(row.id)===id);
const status=async(who,id)=> (await jobFrom(who,id))?.installationStatus;
async function seed(){
 const common={sale:true,system:true,installations:true,customerStatement:true,customers:true,cash:true};
 for(const [id,name,role] of [[original,'البائع الأصلي '+sample,'admin_staff'],[reviewer,reviewerName,'admin_staff'],
  [engineer,engineerName,'installer'],[peer,'مهندس آخر '+sample,'installer'],[otherOffice,'مسؤول آخر '+sample,'admin_staff']]){
  const perms=role==='installer'?{installations:true}:common;
  sql(`insert into public.profiles(id,username,display_name,active,is_admin,phone,user_type,permissions)
  values('${id}','fixture_${id}','${name}',true,false,'07700000000','${role}','${JSON.stringify(perms)}'::jsonb)`);
 }
 sql(`begin;insert into public.customers(id,name,owner_id,customer_type) values(${sample},'${party}','${original}','system');
 insert into public.products(id,code,name,category,qty,cost) values(${sample},'REPORT-${sample}','مادة للتنصيب','ألواح',5,90000);
 insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(1,${sample},5) on conflict(warehouse_id,product_id) do update set qty=excluded.qty;commit;`);
 const create=await rpc(original,'solar_invoice_save',{request_id:randomUUID(),payload:{kind:'system',mode:'credit',partyId:sample,party,
  total:270000,warehouseId:1,installerId:engineer,customerAddress:'عنوان تجريبي للتركيب',items:[{id:sample,qty:1,price:0}]}});
 const id=Number(create.id);
 sql("update transactions set warehouse_status='ready' where id="+id);
 const record=await rpc('admin','solar_customer_get',{customer_id:sample});
 const list=await rpc('admin','solar_customer_transfer_receipts',{customer_id:sample});
 await rpc('admin','solar_customer_save',{action:'transfer_owner',request_id:randomUUID(),payload:{id:sample,ownerId:reviewer,token:record.token,receiptToken:list.receiptToken,receiptIds:[id]}});
 return {id,receiptNo:scalar('select receipt_no from transactions where id='+id)};
}
async function fillReport(task,text){
 const form=task.getByRole('form',{name:'تقرير إنجاز التنصيب'});
 if(!await form.isVisible())await task.getByRole('button',{name:/تقرير الإنجاز/}).click();
 await form.waitFor();
 for(const box of await form.getByRole('checkbox').all())await box.check();
 await form.getByRole('textbox',{name:/ملخص التنفيذ/}).fill(text);
 if(!await form.getByLabel('مبلغ المصروف 1').count())await form.getByRole('button',{name:/إضافة مصروف/}).click();
 await form.getByLabel('بيان المصروف 1').fill('أجور نقل المواد');
 await form.getByLabel('مبلغ المصروف 1').fill('18000');
 await button(form,'إكمال التنصيب وإرسال التقرير').click();
}
async function clickLatestNotification(page,who,id,event){
 const title=sql("select title from solar_notifications where user_id='"+who+"' and job_id="+id+" and event='"+event+"' order by created_at desc,id desc limit 1");
 assert.ok(title);
 await button(page,'فتح الإشعارات').click();
 const modal=page.getByRole('dialog',{name:'الإشعارات'});
 await modal.locator('.notificationList').getByRole('button').filter({hasText:title}).first().click();
 await modal.waitFor({state:'hidden'});
}
const h=await createHarness('installation-engineer-admin-review');
try{
 const {id,receiptNo}=await seed();
 const initialMoney=beforeMoney(id),cashBefore=[cash(original),cash(reviewer),cash(engineer)];
 await action(reviewer,id,'close',{amount:15000},409);
 assert.equal(cash(reviewer),cashBefore[1]);
 const eng=(await h.open(engineer,'/?section=installations')).page;
 const panel=eng.locator('[data-installer-workspace]'),task=panel.locator('[data-job-id="'+id+'"]');
 await task.waitFor();
 const handoff=scope=>scope.getByRole('region',{name:'متابعة الوصل بين المهندس والمسؤول'});
 await handoff(task).waitFor();
 assert.match(await handoff(task).innerText(),new RegExp(reviewerName));
 assert.match(await handoff(task).innerText(),new RegExp(engineerName));
 await button(task,'بدء التنصيب').click();
 await task.locator('.completionForm').waitFor();
 assert.equal(await status(engineer,id),'in_progress');
 await action(reviewer,id,'close',{amount:15000},409);
 await fillReport(task,report);
 await panel.locator('[data-job-id="'+id+'"][data-job-status="completed"]').waitFor();
 assert.match(await handoff(task).innerText(),new RegExp(reviewerName));
 assert.equal(beforeMoney(id),initialMoney);
 assert.equal(noticeCount(reviewer,id,'completed'),1);
 assert.equal(noticeCount(original,id,'completed'),0);
 assert.equal(noticeCount(otherOffice,id,'completed'),0);
 await action(reviewer,id,'return_report',{notes:'\t\n  '},400);
 assert.equal(await status(engineer,id),'completed');
 const submitted=await jobFrom(reviewer,id);
 assert.equal(submitted.installationReport.notes,report);
 assert.equal(submitted.installationReport.submittedBy,engineer);
 assert.equal(submitted.canReturnReport,true);
 assert.equal(submitted.installationReview.status,'submitted');
 await panel.locator('[data-agenda-filter="completed"]').click();
 await task.waitFor();
 await h.layout(eng,'engineer-waiting-for-review',handoff(task));
 assert.equal(await jobFrom(peer,id),undefined);
 assert.equal(await jobFrom(otherOffice,id),undefined);
 assert.equal(await jobFrom(original,id),undefined);
 await action(peer,id,'complete',{notes:'غير مسموح'},403);
 await action(otherOffice,id,'return_report',{notes:reason},403);
 await action(engineer,id,'close',{amount:18000},403);
 const desk=(await h.open(reviewer,'/')).page;
 await clickLatestNotification(desk,reviewer,id,'completed');
 const card=desk.locator('.workflowJob').filter({has:desk.getByText('ملف #'+receiptNo,{exact:true})});
 await card.waitFor();
 const officeReady=desk.getByRole('group',{name:'ملخص حالات التنصيب'}).getByRole('button',{name:/بانتظار المراجعة/});
 await officeReady.click();
 await card.waitFor();
 assert.match(await handoff(card).innerText(),new RegExp(engineerName));
 assert.ok((await card.innerText()).includes(report));
 await card.getByText('إرجاع التقرير للتعديل',{exact:true}).click();
 const returnReason=card.getByLabel('سبب إعادة التقرير للمهندس');
 await returnReason.fill(reason);
 await button(card,'إعادة التقرير للمهندس').click();
 await card.locator('[data-handoff-state="returned"]').waitFor();
 assert.ok((await handoff(card).innerText()).includes(reason));
 await officeReady.click();
 await card.waitFor({state:'hidden'});
 assert.equal(await status(engineer,id),'in_progress');
 const returned=await jobFrom(engineer,id);
 assert.equal(returned.installationReview.notes,reason);
 assert.equal(returned.installationReview.status,'returned');
 assert.equal(returned.installationReview.actorId,reviewer);
 assert.equal(beforeMoney(id),initialMoney);
 await clickLatestNotification(eng,engineer,id,'installation_updated');
 await task.waitFor();
 await handoff(task).getByText(reason,{exact:false}).waitFor();
 const correct=task.getByRole('button',{name:'تصحيح تقرير الإنجاز',exact:true});
 await correct.click();
 assert.equal(await task.getByRole('textbox',{name:/ملخص التنفيذ/}).inputValue(),report);
 assert.equal((await task.getByLabel('مبلغ المصروف 1').inputValue()).replaceAll(',',''),'18000');
 await fillReport(task,corrected);
 await panel.locator('[data-job-id="'+id+'"][data-job-status="completed"]').waitFor();
 assert.equal(noticeCount(reviewer,id,'completed'),2);
 // The previous notice targeted this exact file. Leave it hidden and open the new notice for the same ID.
 await desk.getByLabel('بحث بالتنصيبات').fill('غير موجود في هذه القائمة');
 await card.waitFor({state:'hidden'});
 await clickLatestNotification(desk,reviewer,id,'completed');
 await card.waitFor();
 await card.getByText(corrected,{exact:true}).waitFor();
 await h.layout(desk,'office-reviewing-engineer-report',handoff(card));
 const priorPaymentRevision=revision(id);
 await card.getByLabel('المصاريف النهائية للمنظومة',{exact:true}).fill('15000');
 const officeNote=card.getByRole('textbox',{name:/ملاحظات الاعتماد/});
 await officeNote.fill(chargeNote);
 await clickLatestNotification(desk,reviewer,id,'completed');
 assert.equal(await officeNote.inputValue(),chargeNote);
 assert.equal((await card.getByLabel('المصاريف النهائية للمنظومة',{exact:true}).inputValue()).replaceAll(',',''),'15000');
 await button(card,'اعتماد المصاريف وإغلاق الملف').click();
 await desk.locator('.installationActionToast').getByText('تم الغلق',{exact:true}).waitFor();
 assert.equal(await status(reviewer,id),'closed');
 await action(reviewer,id,'close',{amount:15000},409,priorPaymentRevision);
 assert.deepEqual([cash(original),cash(reviewer),cash(engineer)],[cashBefore[0],cashBefore[1]-15000,cashBefore[2]]);
 await panel.locator('[data-agenda-filter="upcoming"]').click();
 await task.waitFor({state:'hidden'});
 await clickLatestNotification(eng,engineer,id,'installation_updated');
 await panel.locator('[data-job-id="'+id+'"][data-job-status="closed"]').waitFor();
 await handoff(task).waitFor();
 const approved=await jobFrom(engineer,id);
 assert.equal(approved.installationReview.status,'approved');
 assert.equal(approved.installationReview.actorId,reviewer);
 assert.equal(approved.installationReport.notes,corrected);
 assert.ok(!JSON.stringify(approved).includes(chargeNote));
 for(const key of ['sellingPrice','installationPaidExpenses','cost','profit','installationExpenses'])assert.ok(!(key in approved));
 assert.equal(await button(task,'اعتماد المصاريف وإغلاق الملف').count(),0);
 await h.layout(eng,'engineer-approved-outcome',handoff(task));
 h.checks.reviewCycle={submittedByAssignedEngineer:true,correctRecipientAfterTransfer:true,sameReceiptOpenedFromBothInboxes:true,returnReasonVisible:true,
  engineerCorrectedSameReport:true,repeatedNoticeForSameIdReselectsJob:true,financeUntouchedDuringSubmissionAndReturn:true,onlyFinalApprovalPosted:15000,oldSellerAndPeersExcluded:true,financialReviewPrivate:true};
 // An office user without review permission may sell a system, but an admin must review its report.
 const fallbackInvoice=await rpc(reviewer,'solar_invoice_save',{request_id:randomUUID(),payload:{kind:'system',mode:'credit',partyId:sample,party,
  total:200000,warehouseId:1,installerId:engineer,customerAddress:'عنوان تجريبي للتركيب',items:[{id:sample,qty:1,price:0}]}});
 const fallback=Number(fallbackInvoice.id);
 sql("update public.transactions set warehouse_status='ready' where id="+fallback);
 sql("update public.profiles set permissions=permissions-'installations' where id='"+reviewer+"'");
 await action(engineer,fallback,'start',{});
 await action(engineer,fallback,'complete',{checks:{materials:true,tested:true,handover:true},notes:report,expenses:[]});
 const reassigned=await jobFrom(engineer,fallback);
 assert.equal(reassigned.reviewerIsAdminTeam,true);
 assert.equal(noticeCount(ids.admin,fallback,'completed'),1);
 assert.equal(noticeCount(reviewer,fallback,'completed'),0);
 assert.equal(noticeCount(otherOffice,fallback,'completed'),0);
 await action(reviewer,fallback,'close',{amount:0},403);
 await action(ids.admin,fallback,'close',{amount:0});
 assert.equal((await jobFrom(engineer,fallback)).installationReview.actorId,ids.admin);
 h.checks.fallbackReview={reviewPermissionRequired:true,notifiedAdmin:true,noOtherOfficeRecipient:true,adminCanDecide:true};
 await h.finish();
 console.log('PASS assigned engineer submission → named responsible user review → returned report → corrected submission → approval notification and exact expense');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
