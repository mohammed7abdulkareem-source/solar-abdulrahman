import test from 'node:test';
import assert from 'node:assert/strict';
import {createSessionFetch,guardSessionAdoption} from '../app/auth-session-fetch.mjs';

const url='https://auth-fixture.test/auth/v1/user';
const auth=token=>({headers:{Authorization:'Bearer '+token}});
const aborted=error=>error?.name==='AbortError';
function deferred(){let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};}

test('ordinary fetches pass through unchanged for string, URL and Request inputs',async()=>{
 for(const input of [url,new URL(url),new Request(url,{headers:{Authorization:'Bearer ordinary'}})]){
  const init={headers:{Authorization:'Bearer ordinary'},cache:'no-store'},response=Response.json({id:'ordinary'});let seen;
  const request=createSessionFetch(async(...args)=>{seen=args;return response;},5);
  assert.equal(await request(input,init),response);assert.equal(seen[0],input);assert.equal(seen[1],init);assert.equal(init.signal,undefined);
 }
});

test('registered token scopes only GET Auth user, leaving other tokens and write/RPC requests untouched',async()=>{
 const token='scope-fixture',response=Response.json({ok:true}),calls=[];
 const request=createSessionFetch(async(...args)=>{calls.push(args);return response;},5);
 await guardSessionAdoption(token,new AbortController().signal,async()=>{
  for(const [input,init]of [[url,auth('other-token')],[url,{...auth(token),method:'PUT',body:'{}'}],['https://auth-fixture.test/rest/v1/rpc/solar_invoice_save',{...auth(token),method:'POST',body:'{}'}]]){
   assert.equal(await request(input,init),response);assert.equal(calls.at(-1)[0],input);assert.equal(calls.at(-1)[1],init);
  }
 });
});

test('fresh-session GET preserves status, headers and full body for supported fetch input shapes',async()=>{
 const token='successful-fixture';
 await guardSessionAdoption(token,new AbortController().signal,async()=>{
  for(const input of [url,new URL(url),new Request(url,auth(token))]){
   const init=input instanceof Request?{}:auth(token);let signal;
   const request=createSessionFetch(async(_input,options)=>{signal=options.signal;return Response.json({id:'same-user',user_metadata:{name:'اسم عربي'}},{status:200,headers:{'X-Fixture':'preserved'}});},100);
   const response=await request(input,init);assert.ok(signal instanceof AbortSignal);assert.equal(signal.aborted,false);
   assert.equal(response.status,200);assert.equal(response.headers.get('X-Fixture'),'preserved');assert.deepEqual(await response.json(),{id:'same-user',user_metadata:{name:'اسم عربي'}});
  }
 });
});

test('matching-token header wait times out and rejects before the Auth SDK can adopt a session',async()=>{
 const token='timeout-headers';let signal;
 const request=createSessionFetch((_input,init)=>new Promise((resolve,reject)=>{
  signal=init.signal;signal.addEventListener('abort',()=>reject(new DOMException('Fixture aborted','AbortError')),{once:true});
 }),15);
 await assert.rejects(guardSessionAdoption(token,new AbortController().signal,()=>request(url,auth(token))),aborted);
 assert.equal(signal.aborted,true);
});

test('timeout also bounds streamed body reading after successful response headers',async()=>{
 const token='timeout-body';let bodyAborted=false;
 const request=createSessionFetch(async(_input,init)=>new Response(new ReadableStream({start(controller){
  controller.enqueue(new TextEncoder().encode('{"id":'));
  init.signal.addEventListener('abort',()=>{bodyAborted=true;controller.error(new DOMException('Fixture body aborted','AbortError'));},{once:true});
 }}),{headers:{'Content-Type':'application/json'}}),15);
 await assert.rejects(guardSessionAdoption(token,new AbortController().signal,()=>request(url,auth(token))),aborted);
 assert.equal(bodyAborted,true);
});

test('logout or account change cancels adoption before request and while a response body is pending',async()=>{
 const before=new AbortController();before.abort();let calls=0;
 const request=createSessionFetch(async()=>{calls++;return Response.json({id:'old-user'});});
 await assert.rejects(guardSessionAdoption('cancel-before',before.signal,()=>request(url,auth('cancel-before'))),aborted);assert.equal(calls,0);
 const during=new AbortController(),started=deferred();let bodyAborted=false;
 const slow=createSessionFetch(async(_input,init)=>new Response(new ReadableStream({start(controller){
  init.signal.addEventListener('abort',()=>{bodyAborted=true;controller.error(new DOMException('Account switched','AbortError'));},{once:true});started.resolve();
 }})),1000);
 const result=guardSessionAdoption('cancel-during',during.signal,()=>slow(url,auth('cancel-during')));
 await started.promise;during.abort();await assert.rejects(result,aborted);assert.equal(bodyAborted,true);
});

test('already-aborted caller Request signal is respected for a guarded session',async()=>{
 const caller=new AbortController();caller.abort();let called=false;
 const request=createSessionFetch(async()=>{called=true;return Response.json({id:'old-user'});});
 const input=new Request(url,{...auth('request-signal'),signal:caller.signal});
 await assert.rejects(guardSessionAdoption('request-signal',new AbortController().signal,()=>request(input)),aborted);assert.equal(called,false);
});

test('guard is removed after successful or failed operations so later ordinary fetches stay untouched',async()=>{
 for(const fail of [false,true]){
  const token='cleanup-'+fail,signal=new AbortController(),response=Response.json({ok:true});let seen;
  const request=createSessionFetch(async(_input,init)=>{seen=init;return response;},5);
  const operation=()=>guardSessionAdoption(token,signal.signal,async()=>{if(fail)throw new Error('fixture operation failed');return 'saved';});
  if(fail)await assert.rejects(operation,/fixture operation failed/);else assert.equal(await operation(),'saved');
  signal.abort();const init=auth(token);assert.equal(await request(url,init),response);assert.equal(seen,init);
 }
});

test('account cancellation observed at body completion cannot return a stale Auth response',async()=>{
 const token='cancel-body-complete',controller=new AbortController();
 const request=createSessionFetch(async()=>({status:200,statusText:'OK',headers:new Headers({'content-type':'application/json'}),async arrayBuffer(){controller.abort();return new TextEncoder().encode('{"id":"old-user"}').buffer;}}),100);
 await assert.rejects(guardSessionAdoption(token,controller.signal,()=>request(url,auth(token))),aborted);
});

test('only explicit revoked-session logout responses normalize to empty success',async()=>{
 const logout='https://auth-fixture.test/auth/v1/logout?scope=global';
 for(const status of [401,403])for(const body of [{code:'session_not_found'},{error_code:'session_not_found'},{code:status,error_code:'session_not_found'}])for(const input of [logout,new URL(logout),new Request(logout,{method:'POST'})]){
  const upstream=Response.json({...body,msg:'Session already revoked'},{status});let seen;
  const request=createSessionFetch(async(...args)=>{seen=args;return upstream;});
  const init=input instanceof Request?{}:{method:'POST'},result=await request(input,init);
  assert.equal(seen[0],input);assert.equal(seen[1],init);assert.equal(result.status,204);assert.equal(await result.text(),'');
  assert.match(result.headers.get('cache-control')||'',/no-store/);
 }
});

test('other logout errors retain status, response identity and unconsumed body',async()=>{
 const cases=[
  [403,{code:'forbidden'}],[401,{error_code:'bad_jwt'}],[403,{message:'session_not_found'}],
  [403,{code:403,error_code:'forbidden'}],[200,{code:'session_not_found'}],
  [400,{code:'session_not_found'}],[500,{code:'session_not_found'}],
 ];
 for(const [status,body]of cases){
  const upstream=Response.json(body,{status}),request=createSessionFetch(async()=>upstream);
  const result=await request('https://auth-fixture.test/auth/v1/logout',{method:'POST'});
  assert.equal(result,upstream);assert.equal(result.status,status);assert.deepEqual(await result.json(),body);
 }
 const upstream=new Response('upstream unavailable',{status:403}),request=createSessionFetch(async()=>upstream);
 assert.equal(await request('https://auth-fixture.test/auth/v1/logout',{method:'POST'}),upstream);
 assert.equal(await upstream.text(),'upstream unavailable');
});

test('revoked-session error on Auth user or any non-logout request is never changed into authorization success',async()=>{
 for(const [input,method]of [[url,'GET'],[url,'POST'],['https://auth-fixture.test/rest/v1/profiles','GET'],['https://auth-fixture.test/auth/v1/logout','GET']]){
  const upstream=Response.json({code:'session_not_found'},{status:403}),request=createSessionFetch(async()=>upstream);
  const result=await request(input,{method});assert.equal(result,upstream);assert.equal(result.status,403);assert.deepEqual(await result.json(),{code:'session_not_found'});
 }
});

test('logout network failures propagate without pretending the server revoked a session',async()=>{
 const failure=new TypeError('fixture network unavailable'),request=createSessionFetch(async()=>{throw failure;});
 await assert.rejects(request('https://auth-fixture.test/auth/v1/logout',{method:'POST'}),error=>error===failure);
});
