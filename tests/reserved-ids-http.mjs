// Local-only integration against PostgREST 14, not a mocked RPC transport.
import assert from 'node:assert/strict';
import {createHmac,randomUUID} from 'node:crypto';
const base=process.env.SOLAR_RPC_TEST_URL||'http://127.0.0.1:3045';
assert.match(base,/^http:\/\/(127\.0\.0\.1|localhost):\d+$/);
const uid='00000000-0000-0000-0000-000000003490',secret='solar-local-test-only-signing-secret-347';
const enc=x=>Buffer.from(JSON.stringify(x)).toString('base64url');
const header=enc({alg:'HS256',typ:'JWT'}),claims=enc({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600}),signature=createHmac('sha256',secret).update(header+'.'+claims).digest('base64url'),token=header+'.'+claims+'.'+signature;
async function rpc(name,payload){const start=Date.now();const r=await fetch(base+'/rpc/'+name,{method:'POST',headers:{'content-type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify(payload),signal:AbortSignal.timeout(5000)});return {status:r.status,data:await r.json(),ms:Date.now()-start};}
const context=await rpc('solar_system_payment_context',{customer_id:-349001});assert.equal(context.status,200,JSON.stringify(context));
const request_id=randomUUID(),payload={customerId:-349001,invoiceId:null,amount:3707000,mode:'payment',notes:'HTTP fixture',expectedToken:context.data.token};
const saved=await rpc('solar_system_payment_save',{request_id,payload});assert.equal(saved.status,200,JSON.stringify(saved));assert.equal(saved.data.id,1792246234855194);assert.equal(saved.data.remaining,0);assert.equal(saved.data.cashAfter,3707000);
const replay=await rpc('solar_system_payment_save',{request_id,payload});assert.equal(replay.status,200);assert.deepEqual(replay.data,saved.data);
const stale=await rpc('solar_system_payment_save',{request_id:randomUUID(),payload});assert.equal(stale.status,409);assert.equal(stale.data.code,'PT409');assert.ok(stale.ms<1000,'business conflict retried instead of returning');
console.log(JSON.stringify({status:'PASS',transport:'actual PostgREST 14 HTTP',savedInMs:saved.ms,replayedInMs:replay.ms,staleConflictInMs:stale.ms,receipt:saved.data.receiptNo,verified:'reserved highest deleted ID skipped, full 3,707,000 settles once, committed cash, no infinite retry on stale token'}));
