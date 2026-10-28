import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
// Local fixture only: seed with the setup section of the rollback SQL test.
const base='http://127.0.0.1:3073',api='http://127.0.0.1:3079',db='solar_v383',dir='/workspace/solar-review/v383/browser',uid='00000000-0000-0000-0000-000000003831';
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
const p=await ctx.newPage();p.on('pageerror',e=>errors.push(e.message));const dialogs=[];let deletePrompts=0;p.on('dialog',d=>{dialogs.push(d.message());if(d.message().startsWith('حذف فاتورة')&&++deletePrompts===1)return d.dismiss();return d.accept();});
try{
 const row=JSON.parse(sql("select row_to_json(t)from transactions t where party_id=-383001 and kind='system'and total=3000000")),before=balance(),adminBefore=Number(sql("select solar_private.cash_balance('00000000-0000-0000-0000-000000003830')"));
 assert.equal(JSON.parse(sql("select permissions from profiles where id='"+uid+"'")).salesDeleteOwn,false);
 await p.goto(base+'/');await p.locator('a[href="/?section=salesHistory"]').first().click();
 const card=p.getByRole('article',{name:'بيع منظومة رقم '+row.receipt_no,exact:true});await card.getByRole('button',{name:'حذف الوصل',exact:true}).waitFor();
 assert.equal(await p.locator('.saleHistoryCard').count(),2);assert.ok(!(await p.locator('body').innerText()).includes('وصل المستخدم الآخر'));
 await card.getByRole('button',{name:'حذف الوصل',exact:true}).click();await p.waitForFunction(()=>!document.querySelector('.saleHistoryDelete').disabled);assert.equal(balance(),before);
 await card.getByRole('button',{name:'حذف الوصل',exact:true}).click();await p.getByText('تم حذف الفاتورة وإعادة المواد وتصحيح الحساب.',{exact:true}).waitFor();
 await p.locator('.saleHistoryCard').first().waitFor();assert.equal(await p.locator('.saleHistoryCard').count(),1);assert.ok(dialogs[0].includes('479,000')&&dialogs[0].includes('121,000')&&dialogs[0].includes('التسديدات السابقة'));
 assert.equal(balance(),before+479000);assert.equal(Number(sql("select solar_private.cash_balance('00000000-0000-0000-0000-000000003830')")),adminBefore+121000);
 assert.equal(Number(sql('select qty from products where id=-383001')),9);assert.equal(Number(sql('select count(*)from transactions where system_invoice_id='+row.id)),0);assert.equal(Number(sql("select count(*)from transactions where party_id=-383001 and kind='system_payment'")),1);
 await p.screenshot({path:dir+'/receipt-deleted-own-archive.png'});
 await p.goto(base+'/?section=cash');await p.getByTestId('cash-iqd').filter({hasText:'1,100,000'}).waitFor();
 await p.getByRole('button',{name:'تفاصيل الحركة',exact:true}).first().click();await p.locator('.cashMovementPanel').getByText('الوصل المحذوف',{exact:true}).waitFor();await p.locator('.cashMovementPanel').screenshot({path:dir+'/archived-movement-detail.png'});
 const statement=p.locator('.cashPeriodStatement');await statement.getByRole('button',{name:'عرض كشف الفترة',exact:true}).click();await statement.locator('.cashStatementTable').first().waitFor();
 assert.ok((await statement.innerText()).includes('صرف تنصيب مُلغى — أُعيد للقاصة'));assert.ok((await statement.innerText()).includes('الوصل محذوف — أُلغيت مصاريفه'));await statement.screenshot({path:dir+'/deleted-receipt-cash-statement.png'});
 assert.equal(calls.filter(c=>c.name==='solar_sale_delete'&&c.status===204).length,1);assert.deepEqual(errors,[]);
 await writeFile(dir+'/results.json',JSON.stringify({pass:true,universalOwnAccess:true,cancelDoesNotDelete:true,refundToOwner:479000,refundToAdmin:121000,collectionsRetained:1,stockRestored:2,archivedCashDetails:true,statementMarksReversedExpenses:true,calls,errors},null,2));
 console.log('PASS UI → PostgREST → PostgreSQL: universal own receipt deletion, cancel/confirm, original payer refunds, preserved collection, restored stock and archived cash details/statement');
}catch(e){await p.screenshot({path:dir+'/failure.png',fullPage:true});await writeFile(dir+'/failure.json',JSON.stringify({message:e.message,errors,calls},null,2));throw e;}
finally{await ctx.unrouteAll({behavior:'ignoreErrors'});await browser.close();}
