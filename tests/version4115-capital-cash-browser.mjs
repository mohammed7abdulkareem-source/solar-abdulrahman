// Local PostgREST and actual Chromium PDF renderer. Only synthetic accounts are funded here.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4115_capital_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3220';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3221';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4115/capital-browser';
const {db,ids,sql,rpc,createHarness,fingerprint}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4115_capital_browser');
const suffix=randomUUID().slice(0,8),oldNote='حركة تاريخية '+suffix;
const names={sender:'القاصة المرسلة',recipient:'القاصة المستلمة',foreign:'قاصة الوصل الآخر',foreignRecipient:'مستلم الوصل الآخر',zero:'قاصة مسددة بالكامل'};
const people=Object.fromEntries(Object.keys(names).map(k=>[k,{id:randomUUID(),name:names[k]+' '+suffix}]));
const {sender,recipient,foreign,foreignRecipient,zero}=people;
const pending=randomUUID(),unrelated=randomUUID(),accepted=randomUUID(),rejected=randomUUID(),cancelled=randomUUID(),paidOff=randomUUID();
const as=id=>"select set_config('request.jwt.claim.sub','"+id+"',true);";
const fund=(holder,currency,amount,rate=1)=>"select public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId','"+holder.id+"','mode','deposit','currency','"+currency+"','amount',"+amount+",'rate',"+rate+",'note','"+oldNote+"'));";
const send=(receipt,to,amount)=>"select public.solar_cash_transfer_send('"+receipt+"','"+to.id+"',"+amount+",0,'','"+oldNote+"');";
const decide=(receipt,status)=>"select public.solar_cash_transfer_decide('"+receipt+"','"+status+"');";
const permissions='{"cash":true,"cashTransferSend":true,"financeReceive":true,"capital":true}';
sql(`begin;
 insert into profiles(id,display_name,username,is_admin,user_type,active,phone,permissions) values
 ${Object.values(people).map(p=>"('"+p.id+"','"+p.name+"','capital_"+p.id+"',false,'admin_staff',true,'07704115123','"+permissions+"')").join(',')};
 ${as(ids.admin)}
 ${fund(sender,'IQD',15000)} ${fund(zero,'IQD',2500)} ${fund(foreign,'IQD',1000)}
 ${fund(recipient,'USD',100.25,1500)} ${fund(recipient,'USD',23.5,1650)}
 ${as(sender.id)} ${send(pending,recipient,4000)} ${send(accepted,recipient,1000)}
 ${send(rejected,recipient,113)} ${send(cancelled,recipient,73)} ${decide(cancelled,'cancelled')}
 ${as(recipient.id)} ${decide(rejected,'rejected')} ${decide(accepted,'accepted')}
 ${as(zero.id)} ${send(paidOff,recipient,2500)}
 ${as(recipient.id)} ${decide(paidOff,'accepted')}
 ${as(foreign.id)} ${send(unrelated,foreignRecipient,777)}
 update profiles set permissions='{"capital":true}' where id in ('${sender.id}','${recipient.id}');
 update profiles set permissions='{}' where id='${zero.id}';
 commit;`);

const h=await createHarness('capital-current-cash');
const state=uid=>rpc(uid,'solar_capital_current_snapshot',{});
const owners=cash=>cash.allocations.filter(r=>r.kind==='owner');
const rowFor=(cash,p)=>owners(cash).find(r=>r.ownerId===p.id);
const numbers=r=>[r.iqd,r.usd,r.usdBook];
const transferIds=cash=>cash.pendingHandovers.map(r=>r.id);
try{
 const before=fingerprint();
 const [adminData,senderData,recipientData]=await Promise.all([ids.admin,sender.id,recipient.id].map(state));
 const company=adminData.cash;
 assert.ok(!Object.hasOwn(company,'rows'),'snapshot sent the historical movements');
 assert.deepEqual(numbers(rowFor(company,sender)),[10000,0,0]);
 assert.deepEqual(numbers(rowFor(company,recipient)),[3500,123.75,189150]);
 assert.deepEqual(numbers(rowFor(company,foreign)),[223,0,0]);
 assert.equal(rowFor(company,zero),undefined,'zero balance appeared because of historical transactions');
 assert.equal(rowFor(company,foreignRecipient),undefined,'pending recipient was prematurely credited');
 assert.ok(owners(company).every(r=>r.iqd!==0||r.usd!==0||r.usdBook!==0));
 for(const id of [pending,unrelated])assert.ok(transferIds(company).includes(id));
 for(const id of [accepted,rejected,cancelled,paidOff])assert.ok(!transferIds(company).includes(id));
 for(const own of [senderData,recipientData])assert.deepEqual(transferIds(own.cash),[pending]);
 assert.deepEqual(owners(senderData.cash).map(r=>r.ownerId),[sender.id]);
 assert.deepEqual(owners(recipientData.cash).map(r=>r.ownerId),[recipient.id]);
 assert.equal(company.pendingHandovers.find(r=>r.id===pending).amount,4000);
 assert.deepEqual(company.pendingHandovers.filter(r=>r.id===pending).map(r=>[r.senderName,r.recipientName]),[[sender.name,recipient.name]]);
 for(const key of ['iqd','usd','usdBook']){
  const total=company.allocations.reduce((sum,r)=>sum+Number(r[key]),0);
  assert.equal(Math.round(total*100),Math.round(company[key]*100),'historical book/current reconciliation '+key);
 }
 await rpc(zero.id,'solar_capital_current_snapshot',{},403);
 h.checks.truthAndScope=true;

 const number=text=>Number(text.replace('د.ع','').replace(/[^\d.\-]/g,''));
 async function openReport(page,button,title,label){
  const [preview]=await Promise.all([page.waitForEvent('popup'),page.getByRole('button',{name:button,exact:true}).click()]);
  await preview.locator('.pdfPage img').first().waitFor({timeout:120000});
  assert.ok((await preview.title()).startsWith(title+' —'),title);
  const document=await page.evaluate(title=>{
   const docs=window.__documentHtmls.map(html=>new DOMParser().parseFromString(html,'text/html'));
   const doc=docs.reverse().find(d=>d.title===title);
   if(!doc)throw Error('No rendered source for '+title);
   const tables=[...doc.querySelectorAll('table[data-pdf-paginate]')].map(t=>({
    headings:[...t.querySelectorAll('thead th')].map(c=>c.textContent.trim()),
    rows:[...t.querySelectorAll('tbody tr')].map(r=>[...r.cells].map(c=>c.textContent.trim()))
   }));
   const metrics=Object.fromEntries([...doc.querySelectorAll('.reportMetric')].map(m=>[m.querySelector('span').textContent,m.querySelector('strong').textContent]));
   return {tables,metrics,text:doc.body.textContent};
  },title);
  assert.ok(!document.text.includes(oldNote),'financial history appeared in the current report');
  assert.ok(!document.text.includes(zero.name),'a settled zero-balance holder appeared in the report');
  if(label){
   await h.layout(preview,label,preview.locator('.pdfPage').first());
   const pendingDownload=preview.waitForEvent('download');
   await preview.locator('#pdfDownload').click();
   const download=await pendingDownload;
   await download.saveAs(h.dir+'/'+label+'.pdf');
   const bytes=await readFile(h.dir+'/'+label+'.pdf');
   assert.equal(bytes.subarray(0,5).toString(),'%PDF-');
   h.checks[label+'Pages']=await preview.locator('.pdfPage').count();
  }
  await preview.close();h.setCurrent(page);return document;
 }
 const iqd='تفاصيل الصندوق بالدينار',usd='تفاصيل قاصة الدولار بالكلفة';
 const {page}=await h.open(ids.admin,'/?section=capital');
 const workspace=page.locator('.capitalWorkspace');
 await workspace.getByRole('button',{name:iqd}).waitFor();
 const shownAmount=name=>workspace.getByRole('button',{name,exact:true}).locator('.capitalAmount bdi').innerText().then(number);
 assert.equal(await shownAmount(iqd),company.iqd);
 assert.equal(await shownAmount(usd),company.usdBook);
 await h.layout(page,'current-capital',workspace);
 const dinars=await openReport(page,iqd,'كشف الصندوق','company-iqd-cashboxes');
 assert.match(dinars.text,/مبالغ قيد الاستلام/);
 const [balances,handovers]=dinars.tables;
 assert.equal(dinars.tables.length,2);
 assert.deepEqual(balances.headings,['صاحب القاصة','الرصيد الحالي · د.ع']);
 assert.deepEqual(handovers.headings,['من المستخدم','إلى المستخدم','المبلغ · د.ع']);
 const ownersByName=new Map(balances.rows.map(([name,amount])=>[name,number(amount)]));
 assert.equal(ownersByName.get(sender.name),10000);
 assert.equal(ownersByName.get(recipient.name),3500);
 assert.equal(ownersByName.get(foreign.name),223);
 assert.equal(ownersByName.has(foreignRecipient.name),false);
 assert.ok(balances.rows.every(([,amount])=>number(amount)!==0));
 assert.deepEqual(handovers.rows.filter(row=>row[0]===sender.name).map(([from,to,amount])=>[from,to,number(amount)]),[[sender.name,recipient.name,4000]]);
 assert.deepEqual(handovers.rows.filter(row=>row[0]===foreign.name).map(([from,to,amount])=>[from,to,number(amount)]),[[foreign.name,foreignRecipient.name,777]]);
 const available=owners(company).reduce((sum,r)=>sum+r.iqd,0);
 assert.ok(Math.abs(number(dinars.metrics['المتاح في قاصات المستخدمين'])-available)<0.01);
 assert.equal(number(dinars.metrics['الرصيد قيد الاستلام']),company.allocations.find(r=>r.kind==='transit').iqd);

 const dollars=await openReport(page,usd,'كشف قاصة الدولار','company-usd-cashboxes');
 assert.equal(dollars.tables.length,1,'IQD transfers leaked into the USD section');
 assert.ok(!dollars.text.includes(sender.name));
 const usdRows=dollars.tables[0].rows,usdHolding=usdRows.find(r=>r[0]===recipient.name);
 assert.deepEqual(usdHolding.slice(1).map(number),[123.75,189150]);
 assert.equal(number(dollars.metrics['القيمة الدفترية بالدينار']),company.usdBook);
 assert.ok(!dollars.text.includes('مبالغ قيد الاستلام'));
 h.checks.companyCurrentBalances=true;

 const {page:ownPage}=await h.open(sender.id,'/?section=capital');
 await ownPage.locator('.capitalScopeNote').waitFor();
 assert.equal(await ownPage.getByRole('button',{name:usd}).count(),0);
 const own=await openReport(ownPage,iqd,'كشف الصندوق','own-iqd-cashboxes');
 assert.deepEqual(own.tables[0].rows.map(([name,amount])=>[name,number(amount)]),[[sender.name,10000]]);
 assert.deepEqual(own.tables[1].rows.map(([from,to,amount])=>[from,to,number(amount)]),[[sender.name,recipient.name,4000]]);
 assert.ok(!own.text.includes(foreign.name)&&!own.text.includes(foreignRecipient.name));
 assert.deepEqual(Object.keys(own.metrics),['المتاح في قاصات المستخدمين']);
 assert.equal(number(own.metrics['المتاح في قاصات المستخدمين']),10000);
 const {page:receiving}=await h.open(recipient.id,'/?section=capital');
 await receiving.locator('.capitalScopeNote').waitFor();
 const received=await openReport(receiving,iqd,'كشف الصندوق');
 assert.deepEqual(received.tables[0].rows.map(([name,amount])=>[name,number(amount)]),[[recipient.name,3500]]);
 assert.deepEqual(received.tables[1].rows.map(([from,to,amount])=>[from,to,number(amount)]),[[sender.name,recipient.name,4000]]);
 h.checks.outgoingAndIncomingRemainSeparate=true;
 assert.equal(h.calls.some(c=>c.path.endsWith('/solar_capital_snapshot')),false,'current screen accessed the old cash movement payload');
 assert.equal(fingerprint(),before,'reading current cash reports mutated financial records');
 await h.finish();
 console.log('PASS current capital, real company/own cashbox reports, native USD and book IQD, pending parties, PDF download and responsive layouts');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
