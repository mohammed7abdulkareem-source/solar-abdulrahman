import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
// Local fixture only: seed with the setup section of the rollback SQL test.
const base='http://127.0.0.1:3073',api='http://127.0.0.1:3079',db='solar_v382',dir='/workspace/solar-review/v382/browser',uid='00000000-0000-0000-0000-000000003821';
await mkdir(dir,{recursive:true});
const sql=q=>execFileSync('python',['/workspace/solar-review/v359/db.py',db],{input:q,encoding:'utf8'}).trim();
const balance=()=>Number(sql("select solar_private.cash_balance('"+uid+"')"));
const encode=x=>Buffer.from(JSON.stringify(x)).toString('base64url'),raw=encode({alg:'HS256',typ:'JWT'})+'.'+encode({role:'authenticated',sub:uid,exp:Math.floor(Date.now()/1000)+3600}),token=raw+'.'+createHmac('sha256','solar-local-test-only-signing-secret-347').update(raw).digest('base64url');
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),ctx=await browser.newContext({viewport:{width:390,height:920},hasTouch:true}),errors=[],calls=[];
ctx.setDefaultTimeout(20000);
await ctx.addInitScript(({uid,token})=>localStorage.setItem('sb-afxxaafsuscwyjzrnagc-auth-token',JSON.stringify({access_token:token,refresh_token:'local-fixture',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user:{id:uid,email:'fixture@local.test',aud:'authenticated'}})),{uid,token});
await ctx.routeWebSocket(/supabase/,socket=>socket.close());
await ctx.route('https://afxxaafsuscwyjzrnagc.supabase.co/**',async route=>{
 const req=route.request(),u=new URL(req.url());
 if(u.pathname==='/auth/v1/user')return route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({id:uid,email:'fixture@local.test',aud:'authenticated'})});
 if(!u.pathname.startsWith('/rest/v1/'))return route.abort();
 const headers={...req.headers(),authorization:'Bearer '+token};delete headers.apikey;delete headers.host;delete headers.origin;
 const response=await ctx.request.fetch(api+u.pathname.replace('/rest/v1','')+u.search,{method:req.method(),headers,data:req.postDataBuffer()||undefined}),body=await response.text();
 if(u.pathname.includes('/rpc/'))calls.push({name:u.pathname.split('/').at(-1),payload:req.postData()?JSON.parse(req.postData()):null,status:response.status()});
 if(response.status()>=400)errors.push({path:u.pathname,status:response.status(),body});
 return route.fulfill({response,body});
});
await ctx.route('**/*',route=>{const u=new URL(route.request().url());if(u.hostname==='127.0.0.1'||['data:','blob:'].includes(u.protocol))return route.continue();if(u.hostname==='afxxaafsuscwyjzrnagc.supabase.co')return route.fallback();return route.abort();});
const p=await ctx.newPage();p.on('pageerror',e=>errors.push(e.message));p.on('dialog',d=>d.accept());
try{
 assert.equal(balance(),1000000);
 const row=JSON.parse(sql('select row_to_json(t)from transactions t where party_id=-382001 and kind=\'system\'order by id limit 1'));
 await p.goto(base+'/?section=installations');
 const card=p.locator('.workflowJob').filter({has:p.getByText('ملف #'+row.receipt_no,{exact:true})});
 await card.getByLabel('المصاريف النهائية للمنظومة',{exact:true}).fill('2000000');
 await card.getByRole('button',{name:'اعتماد المصاريف وإغلاق الملف',exact:true}).click();
 await p.locator('.installationActionToast').getByText('تم الغلق',{exact:true}).waitFor();
 assert.equal(balance(),-1000000);assert.equal(sql('select installation_status from transactions where id='+row.id),'closed');
 assert.equal(Number(sql('select -sum(delta)from solar_cash_entries where job_id='+row.id)),2000000);
 await p.screenshot({path:dir+'/closed-with-overdraw.png'});
 await p.goto(base+'/?section=cash');await p.getByTestId('cash-iqd').filter({hasText:'-1,000,000'}).waitFor();await p.screenshot({path:dir+'/negative-cashbox.png'});
 await p.goto(base+'/');await p.locator('a[href="/?section=systemPayment"]').first().click();
 await p.getByRole('combobox',{name:'بحث عميل الكشف',exact:true}).fill('عميل القاصة السالبة');
 await p.getByRole('option').filter({hasText:'عميل القاصة السالبة'}).click();
 await p.getByLabel('تخصيص تسديد المنظومات',{exact:true}).selectOption(String(row.id));
 await p.getByLabel('مبلغ حركة المنظومات',{exact:true}).fill('1200000');
 await p.getByRole('button',{name:'حفظ التسديد',exact:true}).click();
 await p.getByRole('status').filter({hasText:'تم حفظ تسديد المنظومات وإضافته إلى القاصة'}).waitFor();
 assert.equal(balance(),200000);
 assert.equal(Number(sql('select count(*)from transactions where party_id=-382001 and kind=\'system_payment\'')),1);
 await p.goto(base+'/?section=cash');await p.getByTestId('cash-iqd').filter({hasText:'200,000'}).waitFor();await p.screenshot({path:dir+'/cashbox-positive-after-payment.png'});
 assert.equal(calls.filter(c=>c.name==='solar_installation_action'&&c.payload.action==='close'&&c.status===204).length,1);
 assert.equal(calls.filter(c=>c.name==='solar_system_payment_save'&&c.status===200).length,1);
 assert.deepEqual(errors,[]);
 await writeFile(dir+'/results.json',JSON.stringify({pass:true,initialCash:1000000,installationPayout:2000000,negativeCash:-1000000,customerPayment:1200000,finalCash:200000,calls,errors},null,2));
 console.log('PASS UI → PostgREST → PostgreSQL: installation closes with negative cash, cash page shows -1,000,000, customer payment returns it to +200,000');
}catch(e){await p.screenshot({path:dir+'/failure.png',fullPage:true});await writeFile(dir+'/failure.json',JSON.stringify({message:e.message,errors,calls},null,2));throw e;}
finally{await ctx.unrouteAll({behavior:'ignoreErrors'});await browser.close();}
