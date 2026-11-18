import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {webcrypto,randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {normalizeHonorific,validHonorific} from '../app/user-name-utils.mjs';
import {normalizeUserPhone,validUserPhone} from '../app/user-phone-utils.mjs';
const require=createRequire(import.meta.url),{transform}=require('next/dist/build/swc');
const source=(await readFile(new URL('../supabase/functions/solar-admin-users/index.ts',import.meta.url),'utf8')).replace(/^import[^;]+;/gm,'').replace(/import\{createClient\}from"[^"]+";/,'');
const {code}=await transform(source,{jsc:{parser:{syntax:'typescript'},target:'es2022'}});
function fixture(role='admin'){
 const actorId=randomUUID(),existingId=randomUUID();
 const patches=[],finalizations=[],creates=[],authUsers=new Map();
 const rows=new Map([[existingId,{id:existingId,token:'original',user_type:'admin_staff',active:true,permissions:{}}]]);
 const actor={is_admin:role==='admin'||role==='warehouse',active:true,user_type:role==='warehouse'?'warehouse':'admin_staff'};
 const client={auth:{getUser:async()=>({data:{user:{id:actorId}}})}};
 const admin={
  from:table=>{assert.equal(table,'profiles');return {select:()=>({eq:(_,id)=>({single:async()=>({data:id===actorId?actor:null})})})};},
  rpc:async(name,{actor_id,action,payload})=>{
   assert.equal(name,'solar_admin_user_wizard');assert.equal(actor_id,actorId);
   if(action==='check_create')return {data:{staged:false}};
   if(action==='directory')return {data:{users:[...rows.values()],warehouses:[]}};
   assert.ok(!('password' in payload));
   const old=rows.get(payload.user_id);
   if(action==='save_details')patches.push(payload);
   else{assert.equal(action,'finalize');assert.equal(old.token,payload.token);finalizations.push(payload);}
   const user={...old,id:payload.user_id,active:true,token:randomUUID(),permissions:{}};
   rows.set(user.id,user);return {data:{user}};
  },
  auth:{admin:{
   getUserById:async id=>authUsers.has(id)?{data:{user:authUsers.get(id)}}:{data:{user:null},error:{status:404}},
   createUser:async details=>{creates.push(details);authUsers.set(details.id,details);return {data:{user:details}};},
   updateUserById:async(id,values)=>{const record=authUsers.get(id);assert.ok(record);authUsers.set(id,{...record,...values});return {data:{user:authUsers.get(id)}};}
  }}
 };
 let handler;
 vm.runInNewContext(code,{normalizeHonorific,validHonorific,normalizeUserPhone,validUserPhone,
  createClient:(_url,key)=>key==='service'?admin:client,crypto:webcrypto,TextEncoder,
  Deno:{env:{get:name=>name==='SUPABASE_SERVICE_ROLE_KEY'?'service':'public'},serve:fn=>handler=fn},Response});
 return {existingId,patches,finalizations,creates,request:async body=>{
  const r=await handler(new Request('https://test.invalid',{method:'POST',headers:{authorization:'Bearer local-only','content-type':'application/json'},body:JSON.stringify(body)}));
  return {status:r.status,data:await r.json()};
 }};
}
test('admin phone validation occurs before Auth account creation and saves the normalized profile phone',async()=>{
 const f=fixture();let r=await f.request({action:'create',username:'new_user',password:'local-fixture',phone:'123'});assert.equal(r.status,400);assert.equal(f.creates.length,0);
 r=await f.request({action:'create',username:'new_user',password:'local-fixture',phone:'٠٧٧٠ ١٢٣ ٤٥٦٧',role:'user'});assert.equal(r.status,200);assert.equal(f.patches[0].phone,'07701234567');
});
test('updating a phone preserves compatibility with old clients and never relaxes the admin role',async()=>{
 const f=fixture();let r=await f.request({action:'update',user_id:f.existingId,username:'some_user',role:'user'});assert.equal(r.status,200);assert.equal(Object.hasOwn(f.patches[0],'phone'),false);
 r=await f.request({action:'update',user_id:f.existingId,username:'some_user',phone:'00964 770 1234567',role:'user'});assert.equal(r.status,200);assert.equal(f.patches[1].phone,'+9647701234567');
 for(const role of ['staff','warehouse']){const denied=fixture(role);assert.equal((await denied.request({action:'create',phone:'07701234567'})).status,403);assert.equal(denied.creates.length,0);assert.equal(denied.patches.length,0);}
});

test('honorific is saved separately, normalized, optional for old clients and cannot change role access',async()=>{
 const f=fixture();let r=await f.request({action:'create',username:'engineer_user',password:'local-fixture',phone:'07701234567',display_name:'صفاء',honorific:'  المهندس  ',role:'installer'});
 assert.equal(r.status,200);assert.equal(f.patches[0].honorific,'المهندس');assert.equal(f.patches[0].display_name,'صفاء');assert.equal(f.finalizations[0].role,'installer');assert.equal(Object.hasOwn(f.patches[0],'is_admin'),false);
 r=await f.request({action:'update',user_id:f.creates[0].id,username:'engineer_user',display_name:'صفاء',role:'installer'});assert.equal(r.status,200);assert.equal(Object.hasOwn(f.patches[1],'honorific'),false);
 r=await f.request({action:'update',user_id:f.creates[0].id,username:'engineer_user',honorific:'',role:'installer'});assert.equal(r.status,200);assert.equal(f.patches[2].honorific,'');
 for(const honorific of ['<script>x</script>','أ'.repeat(51),{role:'admin'},'المهندس\n']){const bad=fixture();assert.equal((await bad.request({action:'create',username:'invalid_user',password:'local-fixture',phone:'07701234567',honorific})).status,400);assert.equal(bad.creates.length,0);assert.equal(bad.patches.length,0);}
});
