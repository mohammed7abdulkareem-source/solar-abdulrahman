import test from 'node:test';
import assert from 'node:assert/strict';
import {createPasswordChangeHandler} from '../supabase/functions/solar-change-password/handler.mjs';

// All Auth responses are isolated fixtures. No real credentials or network calls.
const uid='00000000-0000-0000-0000-000000310201',otherId='00000000-0000-0000-0000-000000310202';
const originalToken='fixture-original-access',freshToken='fixture-verified-access',refreshToken='fixture-verified-refresh';
const oldPassword='CurrentSecret!31',newPassword='ChangedSecret!32';
const validBody={oldPassword,newPassword,confirmPassword:newPassword};
const user={id:uid,email:'fixture-user@solar-user.local',aud:'authenticated'};
const json=(body,status=200)=>Response.json(body,{status});
function fixture(options={}){
 const calls=[];
 const fetchImpl=async(input,init={})=>{
  const url=new URL(String(input)),method=init.method||'GET',headers=new Headers(init.headers);
  const body=init.body?JSON.parse(init.body):null;
  const call={url,method,headers,body};calls.push(call);
  assert.equal(url.origin,'https://auth-fixture.test','Handler escaped its configured Auth server');
  assert.equal(headers.get('apikey'),'fixture-anon-key','Public Auth key missing or privileged key used');
  if(url.pathname==='/auth/v1/user'&&method==='GET'){
   assert.equal(headers.get('authorization'),'Bearer '+originalToken);
   if(options.authError)return json({code:'bad_jwt',msg:'Invalid JWT'},401);
   return json(options.authUser||user);
  }
  if(url.pathname==='/rest/v1/profiles'){
   assert.equal(headers.get('authorization'),'Bearer '+originalToken);
   assert.equal(url.searchParams.get('id'),'eq.'+uid,'Profile lookup accepted a caller-supplied target');
   if(options.profileError)return json({message:'Profile service unavailable'},503);
   const profile={id:uid,active:options.active!==false,is_admin:false,user_type:'installer',permissions:{}};
   return json(headers.get('accept')?.includes('vnd.pgrst.object')?profile:[profile]);
  }
  if(url.pathname==='/auth/v1/token'){
   assert.equal(method,'POST');assert.equal(url.searchParams.get('grant_type'),'password');
   assert.equal(body.email,user.email,'Verification used untrusted email/username');
   if(options.tokenError)return json(options.tokenError.body,options.tokenError.status);
   if(options.tokenFailure)throw new TypeError('fixture network failure');
   return json({access_token:freshToken,refresh_token:refreshToken,expires_in:3600,expires_at:Math.floor(Date.now()/1000)+3600,token_type:'bearer',user:options.verifiedUser||user});
  }
  if(url.pathname==='/auth/v1/user'&&method==='PUT'){
   assert.equal(headers.get('authorization'),'Bearer '+freshToken,'Update used original or privileged session');
   assert.deepEqual(Object.keys(body).sort(),['current_password','password'],'Unexpected profile/email/role update');
   if(options.updateTimeout)return new Promise((resolve,reject)=>{
    assert.ok(init.signal,'Update needs a bounded timeout');
    if(init.signal.aborted)reject(init.signal.reason);else init.signal.addEventListener('abort',()=>reject(init.signal.reason),{once:true});
   });
   if(options.updateFailure)throw new TypeError('fixture network failure');
   if(options.updateError)return json(options.updateError.body,options.updateError.status);
   return json(options.updatedUser||user);
  }
  if(url.pathname==='/auth/v1/logout'){
   assert.equal(method,'POST');assert.equal(url.searchParams.get('scope'),'local','Cleanup revoked other sessions');
   assert.equal(headers.get('authorization'),'Bearer '+freshToken);
   if(options.logoutFailure)throw new TypeError('fixture cleanup unavailable');
   return new Response(null,{status:204});
  }
  throw new Error('Unexpected Auth operation '+method+' '+url.pathname);
 };
 const handler=createPasswordChangeHandler({url:'https://auth-fixture.test',anonKey:'fixture-anon-key',fetchImpl,timeoutMs:options.timeoutMs||1000});
 return {calls,async request(body=validBody,requestOptions={}){
  const headers={'Content-Type':'application/json',Authorization:'Bearer '+originalToken,...requestOptions.headers};
  const req=new Request('https://app-fixture.test/functions/v1/solar-change-password',{method:requestOptions.method||'POST',headers,...((requestOptions.method||'POST')==='POST'?{body:requestOptions.rawBody??JSON.stringify(body)}:{})});
  const response=await handler(req),data=response.status===204?null:await response.json().catch(()=>null);
  if(data){const serialized=JSON.stringify(data);assert.ok(!serialized.includes(oldPassword)&&!serialized.includes(newPassword),'Password leaked in response');}
  return {response,data};
 }};
}
const updates=f=>f.calls.filter(c=>c.method==='PUT');
const logouts=f=>f.calls.filter(c=>c.url.pathname==='/auth/v1/logout');

test('active same user changes only their password and retains the fresh verified session',async()=>{
 const f=fixture(),{response,data}=await f.request({...validBody,userId:otherId,email:'victim@solar-user.local',is_admin:true});
 assert.equal(response.status,200);assert.equal(data.ok,true);assert.equal(data.userId,uid);
 assert.equal(data.session.access_token,freshToken);assert.equal(data.session.refresh_token,refreshToken);
 assert.equal(updates(f).length,1);assert.deepEqual(updates(f)[0].body,{password:newPassword,current_password:oldPassword});
 assert.equal(logouts(f).length,0,'Successful session must survive for client setSession');
 assert.match(response.headers.get('cache-control')||'',/no-store/);
 assert.deepEqual(f.calls.map(c=>c.url.pathname),['/auth/v1/user','/rest/v1/profiles','/auth/v1/token','/auth/v1/user']);
});

test('authentication and active own profile are required before password verification',async()=>{
 for(const options of [{headers:{Authorization:''}},{headers:{Authorization:'Basic fixture'}}]){
  const f=fixture(),{response,data}=await f.request(validBody,options);assert.equal(response.status,401);assert.equal(data.ok,false);assert.equal(f.calls.length,0);
 }
 for(const options of [{authError:true},{active:false},{profileError:true}]){
  const f=fixture(options),{response,data}=await f.request();assert.ok(response.status>=400);assert.equal(data.ok,false);
  assert.equal(f.calls.filter(c=>c.url.pathname==='/auth/v1/token').length,0);assert.equal(updates(f).length,0);
 }
});

test('invalid JSON, missing/mismatched/same passwords and oversized UTF8 secrets never reach Auth update',async()=>{
 const invalid=[{}, {...validBody,oldPassword:''}, {...validBody,newPassword:'short',confirmPassword:'short'}, {...validBody,confirmPassword:'DoesNotMatch'}, {...validBody,newPassword:oldPassword,confirmPassword:oldPassword}, {...validBody,oldPassword:'x'.repeat(1025)}, {...validBody,newPassword:'ع'.repeat(37),confirmPassword:'ع'.repeat(37)}, {...validBody,newPassword:{password:newPassword}}, {...validBody,oldPassword:null}];
 for(const body of invalid){const f=fixture(),r=await f.request(body);assert.ok(r.response.status>=400);assert.equal(r.data.ok,false);assert.equal(updates(f).length,0);assert.equal(f.calls.filter(c=>c.url.pathname==='/auth/v1/token').length,0);}
 const f=fixture(),r=await f.request(validBody,{rawBody:'{not json'});assert.ok(r.response.status>=400);assert.equal(updates(f).length,0);
});

test('passwords preserve leading/trailing spaces rather than silently changing the credential',async()=>{
 const f=fixture(),body={oldPassword:'  old secret  ',newPassword:'  new secret  ',confirmPassword:'  new secret  '},r=await f.request(body);
 assert.equal(r.response.status,200);assert.equal(f.calls.find(c=>c.url.pathname==='/auth/v1/token').body.password,body.oldPassword);
 assert.deepEqual(updates(f)[0].body,{password:body.newPassword,current_password:body.oldPassword});
});

test('incorrect old password and rate-limited verification cannot change a password',async()=>{
 for(const [status,body,code]of [[400,{code:'invalid_credentials',error_code:'invalid_credentials',msg:'Invalid login credentials'},'invalid_old_password'],[429,{code:'over_request_rate_limit',error_code:'over_request_rate_limit',msg:'Too many requests'},'rate_limited']]){
  const f=fixture({tokenError:{status,body}}),r=await f.request();assert.equal(r.data.ok,false);assert.equal(r.data.code,code);assert.equal(updates(f).length,0);assert.equal(logouts(f).length,0);
 }
 const f=fixture({tokenFailure:true}),r=await f.request();assert.equal(r.data.ok,false);assert.equal(r.data.code,'unavailable');assert.equal(updates(f).length,0);
});

test('verification returning a different user fails before mutation and cleans only its temporary session',async()=>{
 const f=fixture({verifiedUser:{...user,id:otherId}}),r=await f.request();assert.equal(r.data.ok,false);assert.equal(updates(f).length,0);assert.equal(logouts(f).length,1);
});

test('known password rejection cleans the temporary session and is not reported as success',async()=>{
 for(const logoutFailure of [false,true])for(const code of ['weak_password',422]){
  const f=fixture({updateError:{status:422,body:{code,error_code:'weak_password',msg:'Password is too weak'}},logoutFailure}),r=await f.request();
  assert.equal(r.data.ok,false);assert.equal(r.data.code,'weak_password');assert.notEqual(r.data.uncertain,true);assert.equal(updates(f).length,1);assert.equal(logouts(f).length,1);assert.ok(!r.data.session);
 }
});

test('unknown update outcome is explicit and does not revoke the potentially successful session',async()=>{
 for(const options of [{updateFailure:true},{updateError:{status:503,body:{msg:'Unavailable'}}},{updateTimeout:true,timeoutMs:20}]){
  const f=fixture(options),r=await f.request();assert.equal(r.data.ok,false);assert.equal(r.data.code,'change_uncertain');assert.equal(r.data.uncertain,true);assert.equal(updates(f).length,1);assert.equal(logouts(f).length,0);assert.ok(!r.data.session);
 }
});

test('handler never logs password request bodies or bearer/refresh tokens',async t=>{
 const logged=[];for(const name of ['log','warn','error','debug','info'])t.mock.method(console,name,(...args)=>logged.push(args));
 await fixture().request();await fixture({updateFailure:true}).request();
 const output=JSON.stringify(logged);for(const secret of [oldPassword,newPassword,originalToken,freshToken,refreshToken])assert.ok(!output.includes(secret),'Credential logged');
});

test('bounded input accepts exactly 72 UTF8 bytes and rejects oversized streamed JSON',async()=>{
 const exact='ع'.repeat(36),f=fixture(),r=await f.request({...validBody,newPassword:exact,confirmPassword:exact});
 assert.equal(r.response.status,200);assert.equal(updates(f)[0].body.password,exact);
 const oversized=fixture(),bad=await oversized.request(validBody,{rawBody:JSON.stringify({...validBody,unrelated:'x'.repeat(9000)})});
 assert.equal(bad.data.ok,false);assert.equal(bad.data.code,'invalid_input');assert.equal(oversized.calls.length,0);
});

test('malformed update acknowledgement cannot claim success or revoke a potentially saved change',async()=>{
 const f=fixture({updatedUser:{...user,id:otherId}}),r=await f.request();
 assert.equal(r.data.ok,false);assert.equal(r.data.code,'change_uncertain');assert.equal(r.data.uncertain,true);
 assert.equal(updates(f).length,1);assert.equal(logouts(f).length,0);assert.ok(!r.data.session);
});

test('non-POST requests cannot reach password Auth operations',async()=>{
 const f=fixture(),r=await f.request(validBody,{method:'GET'});assert.equal(r.response.status,405);assert.equal(f.calls.length,0);
});
