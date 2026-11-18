// Run against the local installer browser database and its loopback PostgREST.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4113_installer_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3180';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4113/installer-browser';
const {db,ids,sql,rpc,createHarness}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4113_installer_browser');

const engineer=randomUUID(),peer=randomUUID(),baseId=Date.now()*10;
const job={ready:baseId+1,waiting:baseId+2,started:baseId+3,future:baseId+4,
 submitted:baseId+5,closed:baseId+6,peer:baseId+7,overdue:baseId+8};
const route='/?section=installations';
const material='لوح شمسي ٦٠٠ واط';
sql(`begin;
 insert into public.profiles(id,display_name,username,user_type,is_admin,active,permissions,phone) values
 ('${engineer}','مهندس الاختبار','qa_${engineer}','installer',false,true,'{}','07704113101'),
 ('${peer}','مهندس آخر','qa_${peer}','installer',false,true,'{}','07704113102');
 insert into public.products(id,code,name,qty,cost)values(${baseId},'I${baseId}','${material}',50,1000);
 insert into public.transactions(id,kind,total,subtotal,cost,profit,payment_mode,cash,fx_pricing,
  party_name,customer_phone,customer_address,created_by,cashbox_user_id,installer_id,install_date,install_time,
  installation_status,warehouse_status,installation_started_at,installation_completed_at,installation_closed_at)
 select id,'system',200000,200000,120000,80000,'credit',false,true,name,'07700000000','بغداد، شارع الاختبار',
 '${ids.owner}','${ids.owner}',installer::uuid,(now() at time zone 'Asia/Baghdad')::date+day_offset,slot::time,
 status,warehouse,case when status<>'pending' then now()-interval '3 hours' end,
 case when status in('completed','closed') then now()-interval '2 hours' end,case when status='closed' then now() end from(values
 (${job.ready},'جاهز للتنصيب','${engineer}',0,'08:00','pending','ready'),
 (${job.waiting},'بانتظار خروج المواد','${engineer}',0,'12:00','pending','pending'),
 (${job.started},'يجري التنصيب','${engineer}',-2,'08:00','in_progress','ready'),
 (${job.future},'موعد الغد','${engineer}',1,'08:00','pending','ready'),
 (${job.submitted},'ملف بانتظار المراجعة','${engineer}',-3,'08:00','completed','ready'),
 (${job.closed},'ملف مغلق','${engineer}',-5,'08:00','closed','ready'),
 (${job.peer},'مهمة تخص مهندساً آخر','${peer}',0,'08:00','pending','ready'),
 (${job.overdue},'موعد سابق مستحق','${engineer}',-1,'08:00','pending','ready')
 ) v(id,name,installer,day_offset,slot,status,warehouse);
 insert into public.transaction_items(transaction_id,product_id,product_name,qty,price,cost)
 values(${job.ready},${baseId},'${material}',3,0,1000);
 update public.products set qty=qty-3 where id=${baseId};
 update public.transactions set warehouse_status='ready',warehouse_prepared_at=now() where id=${job.ready};
 commit;`);
const h=await createHarness('installer-workflow');
const getJobs=()=>rpc(engineer,'solar_installation_jobs',{});
const card=(root,id)=>root.locator('[data-job-id="'+id+'"]');
async function matches(root,expected){
 const idsVisible=await root.locator('.workflowJob[data-job-id]').evaluateAll(nodes=>nodes.map(n=>Number(n.dataset.jobId)).sort((a,b)=>a-b));
 assert.deepEqual(idsVisible,expected.slice().sort((a,b)=>a-b));
}
async function layout(page,workspace,name){
 await h.layout(page,name,workspace);
 for(const width of [360,390,1366]){
  await page.setViewportSize({width,height:865});
  const clipped=await workspace.locator('button,input,textarea').evaluateAll(nodes=>nodes.filter(el=>{
   const b=el.getBoundingClientRect();
   return b.width>0 && (b.left<-1 || b.right>innerWidth+1);
  }).map(el=>el.textContent||el.getAttribute('aria-label')));
  assert.deepEqual(clipped,[],name+' clipped controls at '+width);
 }
 await page.setViewportSize({width:390,height:865});
}
try{
 const jobs=await getJobs();
 assert.equal(jobs.length,7);
 assert.ok(jobs.every(x=>x.installerId===engineer && x.canManage===false && !('sellingPrice' in x) && !('profit' in x) && !('cost' in x)));
 const owner=await h.open(engineer,route),p=owner.page;
 const panel=p.locator('[data-installer-workspace]');await panel.waitFor();
 const filter=key=>panel.locator('[data-agenda-filter="'+key+'"]');
 const ready=card(panel,job.ready);
 await ready.waitFor();
 await matches(panel,[job.ready,job.waiting,job.started,job.overdue]);
 await layout(p,panel,'installer-today');
 assert.equal(await panel.getByRole('button',{name:'اعتماد المصاريف وإغلاق الملف'}).count(),0);
 assert.equal(await panel.locator('.jobSalePrice,.approvalForm').count(),0);
 await filter('upcoming').click();await matches(panel,[job.future]);
 await filter('in_progress').click();await matches(panel,[job.started]);
 await filter('archive').click();await matches(panel,[job.submitted,job.closed]);
 await filter('all').click();await matches(panel,Object.values(job).filter(id=>id!==job.peer));
 const calendar=panel.getByRole('button',{name:/جدول مواعيدي/});await calendar.click();
 assert.equal(await panel.getByText('مهمة تخص مهندساً آخر',{exact:true}).count(),0);
 await calendar.click();
 await filter('today').click();
 const waiting=card(panel,job.waiting);
 assert.equal(await waiting.getByRole('button',{name:'بانتظار تجهيز المخزن'}).isEnabled(),false);
 const start=ready.getByRole('button',{name:'بدء التنصيب',exact:true});
 await start.waitFor();assert.equal(await start.isEnabled(),true);
 const materials=ready.getByText(material,{exact:true});
 if(!await materials.isVisible())await ready.getByText(/مواد التنصيب|مواد المنظومة|المواد/).first().click();
 await materials.waitFor();assert.match(await ready.innerText(),/3|٣/);
 await start.click();
 const form=ready.locator('.completionForm');
 await form.waitFor();
 assert.equal((await getJobs()).find(x=>Number(x.id)===job.ready).installationStatus,'in_progress');
 await layout(p,form,'installer-completion');
 const submit=form.getByRole('button',{name:'إكمال التنصيب وإرسال التقرير'});
 await submit.click();assert.equal((await getJobs()).find(x=>Number(x.id)===job.ready).installationStatus,'in_progress');
 const checks=form.getByRole('checkbox');assert.equal(await checks.count(),3);
 for(const box of await checks.all())await box.check();
 const notes='تمت مطابقة المواد وفحص تشغيل المنظومة وتسليمها للزبون.';
 await form.locator('textarea').fill(notes);
 await form.getByRole('button',{name:/إضافة مصروف/}).click();
 await form.getByLabel('بيان المصروف 1').fill('نقل المواد');
 await form.getByLabel('مبلغ المصروف 1').fill('١٬٢٣٤٫٥٠');
 const response=p.waitForResponse(r=>r.url().endsWith('/rpc/solar_installation_action')&&r.request().postDataJSON()?.action==='complete');
 await submit.click();assert.equal((await response).status(),204);
 await filter('archive').click();await card(panel,job.ready).waitFor();
 const done=(await getJobs()).find(x=>Number(x.id)===job.ready);
 assert.equal(done.installationStatus,'completed');assert.equal(done.installationReport.notes,notes);
 assert.equal(Number(done.installationReport.expenseTotal),1234.5);
 assert.equal(await panel.locator('.approvalForm').count(),0);
 const deep=await h.open(engineer,route+'&job='+job.ready);
 await card(deep.page.locator('[data-installer-workspace]'),job.ready).waitFor();
 const admin=await h.open('admin',route+'&job='+job.ready);
 await admin.page.locator('.workflowJob').filter({hasText:'جاهز للتنصيب'}).first().waitFor();
 assert.equal(await admin.page.locator('[data-installer-workspace]').count(),0);
 const office=admin.page.locator('.workflowJob').filter({hasText:'جاهز للتنصيب'}).first();
 await office.locator('.approvalForm').waitFor();assert.equal(await office.locator('.jobSalePrice').count(),1);
 const archived=(await rpc('admin','solar_installation_jobs',{})).find(x=>Number(x.id)===job.ready);
 assert.equal(archived.installationReport.notes,notes);assert.ok(archived.canManage);
 assert.equal((await rpc(engineer,'solar_installation_action',{job_id:job.ready,expected_revision:done.installationRevision,action:'close',payload:{amount:0}},403)).code,'42501');
 await h.finish();console.log('PASS installer workload, assigned dates, warehouse readiness, materials, actual start/report, desktop/mobile, and administrator review.');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
