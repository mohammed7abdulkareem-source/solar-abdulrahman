// Focused read regression for foreign-created payments credited to own cashbox.
process.env.SOLAR_FIXTURE_DB||='solar_seller_scope_browser';
process.env.SOLAR_FIXTURE_API||='http://127.0.0.1:3149';
import assert from 'node:assert/strict';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
const {api,tokenFor,rpc,fingerprint,sql}=await import('./version4-browser-support.mjs');
const owner='00000000-0000-0000-0000-000000412111',financeOwner='00000000-0000-0000-0000-000000412901',admin='00000000-0000-0000-0000-000000412101';
const dir='/workspace/solar-review/v412/payment-creator',baseline=process.env.SOLAR_RECORD_PAYMENT_BASELINE==='1',calls=[];await mkdir(dir,{recursive:true});
async function get(who,path,body){const response=await fetch(api+path,{method:body?'POST':'GET',headers:{authorization:'Bearer '+tokenFor(who),'content-type':'application/json'},body:body?JSON.stringify(body):undefined});const data=await response.json();calls.push({path,status:response.status});return{status:response.status,data};}
const before=fingerprint(),cash=await rpc(owner,'solar_cash_workspace',{payload:{ownerId:owner}}),profit=await rpc(financeOwner,'solar_profit_workspace',{action:'overview',payload:{}});
const rows=await get(owner,'/transactions?select=id,receipt_no,party_name,notes,total,created_by&cashbox_user_id=eq.'+owner),supplier=await get(owner,'/rpc/solar_supplier_payment_get',{payment_id:-412111});
const foreignEntries=await get(financeOwner,'/solar_cash_entries?select=id,notes,job_id,deleted_job_id&id=in.(00000000-0000-0000-0000-000000412911,00000000-0000-0000-0000-000000412912)');
try{
 assert.equal(cash.summary.IQD,333331);assert.equal(cash.summary.USD,0);assert.equal(cash.count,5);assert.equal(cash.rows.filter(row=>row.receiptRestricted).length,3);assert.doesNotMatch(JSON.stringify(cash),/FOREIGN_PAYMENT_PRIVATE_V412/);assert.equal(profit.available,102);
 if(baseline){assert.equal(rows.status,200);assert.equal(rows.data.filter(row=>[-412109,-412110,-412111].includes(row.id)).length,3);assert.equal(supplier.status,200);assert.match(supplier.data.notes,/FOREIGN_PAYMENT_PRIVATE_V412_SUPPLIER/);assert.equal(foreignEntries.data.length,2);}
 else{
  assert.equal(rows.status,200);assert.deepEqual(rows.data.map(row=>row.id).sort((a,b)=>a-b),[-412113,-412112]);assert.equal(supplier.status,403);assert.equal(supplier.data.code,'42501');assert.equal(foreignEntries.status,200);assert.deepEqual(foreignEntries.data,[]);
  const own=await get(owner,'/rpc/solar_supplier_payment_get',{payment_id:-412113});assert.equal(own.status,200);assert.match(own.data.notes,/OWN_PAYMENT_V412_SUPPLIER/);const all=await get(admin,'/transactions?select=id&id=in.(-412109,-412110,-412111,-412112,-412113)');assert.equal(all.status,200);assert.equal(all.data.length,5);
  const adminSupplier=await get(admin,'/rpc/solar_supplier_payment_get',{payment_id:-412111});assert.equal(adminSupplier.status,200);assert.equal(adminSupplier.data.id,-412111);
  const allowedTransfer=await get(financeOwner,'/solar_cash_entries?select=id,notes&id=eq.00000000-0000-0000-0000-000000412913');assert.equal(allowedTransfer.status,200);assert.equal(allowedTransfer.data.length,1);assert.equal(allowedTransfer.data[0].notes,'Authorized transfer note');
  const snapshot=JSON.parse(await readFile(dir+'/before-read-policy.json','utf8'));assert.deepEqual(cash.summary,snapshot.cashSummary);assert.equal(profit.available,snapshot.profitAvailable);assert.equal(sql("select solar_private.cash_balance('"+financeOwner+"')"),'940');
 }
 assert.equal(fingerprint(),before);await writeFile(dir+(baseline?'/before-read-policy.json':'/results.json'),JSON.stringify({pass:true,baseline,foreignPaymentHeaderCount:rows.data.filter(row=>[-412109,-412110,-412111].includes(row.id)).length,supplierStatus:supplier.status,foreignJobEntryCount:foreignEntries.data.length,cashSummary:cash.summary,profitAvailable:profit.available,financialFingerprint:before,financialUnchanged:true,calls},null,2));console.log(baseline?'CONFIRMED local payment/header and foreign-job entry disclosures without writes':'PASS foreign payment creator and linked cash-entry read isolation, own/admin/transfer positive controls and unchanged balances');
}catch(error){await writeFile(dir+'/failure.json',JSON.stringify({error:String(error),stack:error.stack,calls},null,2));throw error;}
