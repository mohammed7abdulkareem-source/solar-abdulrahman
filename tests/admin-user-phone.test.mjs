import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {createRequire} from 'node:module';
import {normalizeHonorific,validHonorific} from '../app/user-name-utils.mjs';
import {normalizeUserPhone,validUserPhone} from '../app/user-phone-utils.mjs';
const require=createRequire(import.meta.url),{transform}=require('next/dist/build/swc');
const source=(await readFile(new URL('../supabase/functions/solar-admin-users/index.ts',import.meta.url),'utf8')).replace(/^import[^;]+;/gm,'').replace(/import\{createClient\}from"[^"]+";/,'');
const {code}=await transform(source,{jsc:{parser:{syntax:'typescript'},target:'es2022'}});
function fixture(role='admin'){
 const patches=[],creates=[];let handler;
 const profile={is_admin:role==='admin'||role==='warehouse',active:true,user_type:role==='warehouse'?'warehouse':'admin_staff'};
 const client={auth:{getUser:async()=>({data:{user:{id:'admin'}}})}};
 const admin={from:()=>({select:()=>({eq:()=>({single:async()=>({data:profile})}),order:async()=>({data:[{...profile,phone:'07701234567'}]})}),update:patch=>({eq:async()=>{patches.push(patch);return {};}})}),auth:{admin:{createUser:async x=>{creates.push(x);return {data:{user:{id:'new-user'}}};},updateUserById:async()=>({})}}};
 vm.runInNewContext(code,{normalizeHonorific,validHonorific,normalizeUserPhone,validUserPhone,createClient:(_url,key)=>key==='service'?admin:client,Deno:{env:{get:name=>name==='SUPABASE_SERVICE_ROLE_KEY'?'service':'public'},serve:fn=>handler=fn},Response,Date,Object,Error,String});
 return {patches,creates,request:async body=>{const r=await handler(new Request('https://test.invalid',{method:'POST',headers:{authorization:'Bearer local-only','content-type':'application/json'},body:JSON.stringify(body)}));return {status:r.status,data:await r.json()};}};
}
test('admin phone validation occurs before Auth account creation and saves the normalized profile phone',async()=>{
 const f=fixture();let r=await f.request({action:'create',username:'new_user',password:'local-fixture',phone:'123'});assert.equal(r.status,400);assert.equal(f.creates.length,0);
 r=await f.request({action:'create',username:'new_user',password:'local-fixture',phone:'٠٧٧٠ ١٢٣ ٤٥٦٧',role:'user'});assert.equal(r.status,200);assert.equal(f.patches[0].phone,'07701234567');
});
test('updating a phone preserves compatibility with old clients and never relaxes the admin role',async()=>{
 const f=fixture();let r=await f.request({action:'update',user_id:'some-user',username:'some_user',role:'user'});assert.equal(r.status,200);assert.equal(Object.hasOwn(f.patches[0],'phone'),false);
 r=await f.request({action:'update',user_id:'some-user',username:'some_user',phone:'00964 770 1234567',role:'user'});assert.equal(r.status,200);assert.equal(f.patches[1].phone,'+9647701234567');
 for(const role of ['staff','warehouse']){const denied=fixture(role);assert.equal((await denied.request({action:'create',phone:'07701234567'})).status,400);assert.equal(denied.creates.length,0);assert.equal(denied.patches.length,0);}
});

test('honorific is saved separately, normalized, optional for old clients and cannot change role access',async()=>{
 const f=fixture();let r=await f.request({action:'create',username:'engineer_user',password:'local-fixture',phone:'07701234567',display_name:'صفاء',honorific:'  المهندس  ',role:'installer'});
 assert.equal(r.status,200);assert.equal(f.patches[0].honorific,'المهندس');assert.equal(f.patches[0].display_name,'صفاء');assert.equal(f.patches[0].is_admin,false);assert.equal(f.patches[0].user_type,'installer');
 r=await f.request({action:'update',user_id:'new-user',username:'engineer_user',display_name:'صفاء',role:'installer'});assert.equal(r.status,200);assert.equal(Object.hasOwn(f.patches[1],'honorific'),false);
 r=await f.request({action:'update',user_id:'new-user',username:'engineer_user',honorific:'',role:'installer'});assert.equal(r.status,200);assert.equal(f.patches[2].honorific,'');
 for(const honorific of ['<script>x</script>','أ'.repeat(51),{role:'admin'},'المهندس\n']){const bad=fixture();assert.equal((await bad.request({action:'create',username:'invalid_user',password:'local-fixture',phone:'07701234567',honorific})).status,400);assert.equal(bad.creates.length,0);assert.equal(bad.patches.length,0);}
});
