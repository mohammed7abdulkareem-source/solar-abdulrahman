import test from 'node:test';
import assert from 'node:assert/strict';
import {createLoginHandler} from '../supabase/functions/solar-login/handler.mjs';

const profile={id:'fixture-id',active:true,username:'Office_Name'};
const email='historic-email@example.test',password=' Case Sensitive ';
const user={id:profile.id,email};
const grant={data:{user,session:{user,access_token:'fixture-access',refresh_token:'fixture-refresh'}}};
const sample={login:' OFFICE_NAME ',password};
function setup(overrides={}){
  const state={matching:[profile],identity:{data:{user}},grant,current:{data:profile},...overrides};
  const calls={matches:[],passwords:[],verifiedIds:[],identityIds:[],revocations:[]};
  const admin={
    from(table){
      assert.equal(table,'profiles');
      return {select(){
        return {
          filter(column,operator,pattern){
            assert.equal(column,'username');assert.equal(operator,'imatch');
            calls.matches.push(pattern);
            return {limit(n){
              assert.equal(n,2);
              return state.lookupError?{error:state.lookupError}:{data:state.matching};
            }};
          },
          eq(column,id){
            assert.equal(column,'id');
            calls.verifiedIds.push(id);
            return {maybeSingle:()=>state.current};
          }
        };
      }};
    },
    auth:{admin:{getUserById(id){
      calls.identityIds.push(id);return state.identity;
    }}}
  };
  const makeAuth=()=>({auth:{signOut(options){
    calls.revocations.push(options);
    if(state.throwAtCleanup)throw new Error('provider unavailable');
    return {error:null};
  },signInWithPassword(input){
    calls.passwords.push(input);
    if(state.throwAtGrant)throw new Error('private upstream diagnostics');
    return state.grant;
  }}});
  const handler=createLoginHandler({makeAdmin:()=>admin,makeAuth});
  async function invoke(input=sample){
    const response=await handler(new Request('https://example.test/login',{method:'POST',body:JSON.stringify(input)}));
    assert.equal(response.headers.get('cache-control'),'no-store');
    return {status:response.status,body:await response.json()};
  }
  return {handler,invoke,calls};
}

test('username lookup preserves the historical email and the exact password',async()=>{
  const {invoke,calls}=setup();
  assert.deepEqual(await invoke(),{status:200,body:{ok:true,access_token:'fixture-access',refresh_token:'fixture-refresh'}});
  assert.deepEqual(calls.passwords,[{email,password}]);
  assert.deepEqual(calls.matches,['^office_name$']);
  assert.deepEqual(calls.revocations,[]);assert.deepEqual(calls.identityIds,[user.id]);assert.deepEqual(calls.verifiedIds,[user.id]);
});
test('all characters in a username are literal through the PostgREST filter',async()=>{
  const username='a._%*[]^$()|?+{}\\z';
  const account={...profile,username};
  const {invoke,calls}=setup({matching:[account],current:{data:account}});
  assert.equal((await invoke({login:username,password})).status,200);
  const literal=new RegExp(calls.matches[0],'i');
  assert(literal.test(username));
  assert(!literal.test('before'+username));
  for(let i=0;i<username.length;i++)assert(!literal.test(username.slice(0,i)+'x'+username.slice(i+1)));
});
test('direct email login validates an active profile using the authenticated ID',async()=>{
  const {invoke,calls}=setup();
  assert.equal((await invoke({login:' Historic-Email@Example.Test ',password})).status,200);
  assert.deepEqual(calls.passwords,[{email,password}]);assert.deepEqual(calls.matches,[]);
  assert.deepEqual(calls.verifiedIds,[user.id]);
  for(const current of [{data:null},{data:{...profile,active:false}},{data:{...profile,id:'different'}}]){
    const r=await setup({current}).invoke({login:email,password});
    assert.equal(r.body.code,'invalid_credentials');assert.equal(r.body.access_token,undefined);
  }
});
test('unknown, disabled, ambiguous, nonmatching and genuinely invalid grants have identical responses',async()=>{
  const cases=[
    {matching:[]},{matching:[{...profile,active:false}]},{matching:[profile,profile]},
    {matching:[{...profile,username:'OfficeXName'}]},
    {identity:{error:{code:'user_not_found',status:404}}},
    {identity:{data:{user:{...user,id:'other'}}}},
    {grant:{data:{...grant.data,user:{id:'other'}}}},
    {grant:{data:{...grant.data,session:{...grant.data.session,user:{id:'other'}}}}},
    {current:{data:{...profile,username:'Renamed'}}},{current:{data:{...profile,active:false}}},
    {grant:{error:{status:400,code:'invalid_credentials'}}},
    {grant:{error:{status:400,message:'Invalid login credentials'}}},
    {grant:{error:{status:403,code:'user_banned'}}}
  ];
  const generic=await setup(cases[0]).invoke();
  assert.equal(generic.status,401);assert.equal(generic.body.code,'invalid_credentials');
  for(const overrides of cases)assert.deepEqual(await setup(overrides).invoke(),generic);
});
test('throttling, provider outages, directory failures and malformed successful grants are distinct from password rejection',async()=>{
  for(const overrides of [
    {grant:{error:{status:429}}},{grant:{error:{code:'over_request_rate_limit'}}},
    {lookupError:{status:429}},{current:{error:{status:429}}}
  ]){
    const r=await setup(overrides).invoke();
    assert.equal(r.status,429);assert.equal(r.body.code,'rate_limited');assert.equal(r.body.access_token,undefined);
  }
  for(const overrides of [
    {throwAtGrant:true},{grant:{error:{status:503,code:'unexpected_failure'}}},
    {grant:{error:{status:401,code:'bad_jwt'}}},{grant:{error:{status:0}}},
    {identity:{error:{status:500}}},{lookupError:{code:'PGRST000',message:'private upstream diagnostics'}},
    {current:{error:{code:'42501'}}},{grant:{data:{user}}}
  ]){
    const r=await setup(overrides).invoke();
    assert.equal(r.status,503);assert.equal(r.body.code,'unavailable');
    assert(!JSON.stringify(r.body).includes('diagnostics'));assert.equal(r.body.refresh_token,undefined);
  }
});
test('only the just-granted session is revoked when its application profile fails the final check',async()=>{
  for(const overrides of [
    {current:{data:null}}, {current:{data:{...profile,active:false}}},
    {current:{error:{code:'42501'}}}, {current:{data:null},throwAtCleanup:true}
  ]){
    const {invoke,calls}=setup(overrides);
    const result=await invoke();
    assert(result.status>=400);assert.equal(result.body.access_token,undefined);
    assert.deepEqual(calls.revocations,[{scope:'local'}]);
  }
  const {invoke,calls}=setup({grant:{error:{code:'invalid_credentials'}}});
  await invoke();assert.deepEqual(calls.revocations,[]);
});
test('malformed and empty inputs do not reach the directory or password provider',async()=>{
  const {handler,invoke,calls}=setup();
  for(const input of [{},{login:' ' ,password},{login:'a',password:42},{login:'a',password:''}]){
    const r=await invoke(input);assert.equal(r.status,400);assert.equal(r.body.code,'invalid_request');
  }
  const bad=await handler(new Request('https://example.test/login',{method:'POST',body:'{'}));
  assert.equal(bad.status,400);
  assert.equal((await handler(new Request('https://example.test/login',{method:'OPTIONS'}))).status,200);
  assert.equal((await handler(new Request('https://example.test/login'))).status,405);
  assert.deepEqual(calls.passwords,[]);assert.deepEqual(calls.matches,[]);
});
