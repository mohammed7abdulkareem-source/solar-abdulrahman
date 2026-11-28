import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createHarness,rpc,sql} from './version4-browser-support.mjs';

const [admin,sender,recipient,other]=Array.from({length:4},()=>randomUUID());
const senderName='هند سلمان التجريبية',recipientName='رائد حازم التجريبي';
sql(`insert into profiles(id,display_name,phone,active,is_admin,user_type,permissions) values
 ('${admin}','مشرف الصندوق التجريبي','07700000001',true,true,'admin','{}'),
 ('${sender}','${senderName}','07700000002',true,false,'admin_staff','{"cash":true,"cashTransferSend":true,"cashDeposit":true}'),
 ('${recipient}','${recipientName}','07700000003',true,false,'admin_staff','{"cash":true,"financeReceive":true,"cashDeposit":true}'),
 ('${other}','قاصة أخرى للاختبار','07700000004',true,false,'admin_staff','{"cash":true}');`);
const {rate}=await rpc(admin,'solar_exchange_rate_get',{});
async function deposit(owner,currency,amount,note){
 return rpc(admin,'solar_cash_save',{request_id:randomUUID(),payload:{ownerId:owner,currency,amount,mode:'deposit',rate,note}});
}
await deposit(sender,'IQD',2000000,'تمويل حساب المرسل');
await deposit(recipient,'IQD',900000,'رصيد افتتاح تجريبي');
await deposit(recipient,'USD',17.25,'إيداع دولار مستقل');
await deposit(other,'IQD',725000,'قاصة مختلفة عن المستلم');
const id=randomUUID();
await rpc(sender,'solar_cash_transfer_send',{request_id:id,recipient,send_amount:1500000,expense_amount:0,expense_note:'',note:'مقابل تسليم المبلغ'});
await rpc(recipient,'solar_cash_transfer_decide',{request_id:id,decision:'accepted'},204);
const read=(who,options={})=>rpc(who,'solar_cash_workspace',{payload:{limit:50,...options}});
const movement=(rows,kind)=>rows.find(r=>r.kind===kind);
const recipientList=await read(recipient);
const incoming=movement(recipientList.rows,'transfer_in');
assert.ok(incoming,'confirmed incoming transfer present');
assert.equal(Number(incoming.ownerBalance),2400000);
assert.equal(incoming.transfer.sender,senderName);assert.equal(incoming.transfer.recipient,recipientName);assert.equal(incoming.transfer.decidedBy,recipientName);
assert.equal(Number(recipientList.rows.find(r=>r.currency==='USD').ownerBalance),17.25);
const filtered=await read(recipient,{direction:'in',currency:'IQD',limit:1});
assert.equal(filtered.rows[0].id,incoming.id);assert.equal(Number(filtered.rows[0].ownerBalance),2400000);
assert.equal(Number((await read(recipient,{direction:'in',currency:'IQD',limit:1,offset:1})).rows[0].ownerBalance),900000);
const senderList=await read(sender);
const outgoing=movement(senderList.rows,'transfer_out');
assert.equal(Number(outgoing.ownerBalance),500000);assert.equal(outgoing.transfer.recipient,recipientName);
const adminList=await read(admin,{ownerId:null});
assert.equal(Number(adminList.rows.find(r=>r.id===incoming.id).ownerBalance),2400000);
const detail=await rpc(recipient,'solar_cash_movement_detail',{movement_id:incoming.id});
assert.equal(Number(detail.ownerBalance),2400000);assert.equal(detail.transfer.sender,senderName);
assert.ok(!(await read(other)).rows.some(r=>r.id===incoming.id));

const h=await createHarness('cash-movement-clarity');
try{
 const {page}=await h.open(recipient,'/?section=cash&cashView=ledger');
 const card=page.locator('.cfMovement').filter({hasText:senderName}).filter({hasText:'1,500,000'});
 await card.waitFor();
 assert.match(await card.innerText(),/اعتمد الاستلام/);
 assert.ok((await card.innerText()).includes(recipientName));
 assert.match(await card.locator('.cfRowAfter').innerText(),/2,400,000/);
 assert.match(await card.locator('.cfMovementMoney').innerText(),/1,500,000/);
 assert.match(await page.locator('.cfMovement').filter({hasText:'17.25'}).locator('.cfRowAfter').innerText(),/17\.25/);
 const row=page.locator('.cfDesktopLedger tr').filter({hasText:senderName}).filter({hasText:'1,500,000'});
 for(const width of [360,390,1366]){
  await page.setViewportSize({width,height:920});
  const item=width<700?card:row;
  await item.scrollIntoViewIfNeeded();
  assert.match(await item.innerText(),/2,400,000/);
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
  await page.screenshot({path:h.dir+'/cash-movements-'+width+'.png',animations:'disabled'});
 }
 await page.setViewportSize({width:390,height:920});
 await page.getByRole('textbox',{name:'بحث حركات الصندوق'}).fill(senderName);
 await page.locator('.cfMovement').filter({hasText:'17.25'}).waitFor({state:'hidden'});
 await card.waitFor();
 assert.match(await card.locator('.cfRowAfter').innerText(),/2,400,000/);
 await card.click();
 const panel=page.locator('.cashMovementPanel');
 await panel.getByText(senderName,{exact:true}).first().waitFor();
 assert.match(await panel.innerText(),/2,400,000/);
 await h.layout(page,'cash-transfer-detail',panel);
 const office=await h.open(admin,'/?section=cash&cashView=ledger');
 const allCard=office.page.locator('.cfMovement').filter({hasText:senderName}).filter({hasText:'1,500,000'}).filter({hasText:'2,400,000'}).first();
 await allCard.waitFor();
 assert.ok((await allCard.innerText()).includes(recipientName));
 const separate=await h.open(other,'/?section=cash&cashView=ledger');
 await separate.page.locator('.cfMovement').filter({hasText:'725,000'}).waitFor();
 assert.equal(await separate.page.getByText(senderName,{exact:true}).count(),0);
 h.checks.postedTransferBalance=2400000;h.checks.foreignBoxExcluded=true;
 await h.finish();
 console.log('Cash movement list, owner balances, transfer parties and mobile/desktop detail passed.');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
