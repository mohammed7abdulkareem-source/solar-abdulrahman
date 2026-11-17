// Read-only browser/PDF checks. Seed version412-finance-privacy-browser-fixture.sql
// once in the disposable DB before running; never run against a production URL.
import assert from 'node:assert/strict';
process.env.SOLAR_FIXTURE_DB||='solar_seller_scope_browser';
process.env.SOLAR_FIXTURE_API||='http://127.0.0.1:3149';
process.env.SOLAR_APP_URL||='http://127.0.0.1:3100';
process.env.SOLAR_ARTIFACT_DIR||='/workspace/solar-review/v412/finance-browser';
const {createHarness,fingerprint,rpc,sql}=await import('./version4-browser-support.mjs');
const owner='00000000-0000-0000-0000-000000412901',h=await createHarness('finance-privacy'),responses=[];
const hiddenReceipts=JSON.parse(sql("select jsonb_agg(receipt_no)from transactions where id in(-412901,-412902,-412905)"));
const confidential=(value,label)=>{
 const text=typeof value==='string'?value:JSON.stringify(value);
 assert.ok(!text.includes('SECRET'),label+' exposes foreign party, notes, material, or creator');
 assert.ok(!/77123400[12589]/.test(text),label+' exposes archived foreign receipt');
 assert.ok(!/(?:tx:)?-41290[12589]/.test(text),label+' exposes foreign document ID');
};
h.setIntercept(async({call,response})=>{
 if(['/rpc/solar_cash_workspace','/rpc/solar_cash_statement','/rpc/solar_profit_workspace','/rpc/solar_profit_detail'].some(path=>call.path.endsWith(path))&&response.status()===200){
  const data=await response.json();responses.push({path:call.path,request:call.body,data});confidential(data,'Browser API '+call.path);
 }
 return false;
});
const financeState=async()=>({
 cash:await rpc(owner,'solar_cash_workspace',{payload:{ownerId:owner}}),
 profit:await rpc(owner,'solar_profit_workspace',{action:'overview',payload:{ownerId:owner}}),
 checkpoints:sql("select md5(coalesce(jsonb_agg(to_jsonb(x)order by source_key),'[]')::text)from solar_private.profit_checkpoints x where owner_id='"+owner+"'"),
 settlements:sql("select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)from solar_private.profit_settlements x where owner_id='"+owner+"'")
});
try{
 const before=fingerprint(),initial=await financeState();
 assert.equal(initial.cash.summary.IQD,940);assert.equal(initial.cash.summary.USD,0);assert.equal(initial.cash.count,8);
 assert.equal(initial.cash.rows.filter(r=>r.receiptRestricted).length,5);
 assert.equal(initial.profit.available,102);confidential(initial.cash,'Cash baseline');confidential(initial.profit,'Profit baseline');
 const {page,ctx}=await h.open(owner,'/?section=cash&cashView=ledger');
 await page.waitForFunction(()=>document.querySelectorAll('.cfMovementCards .cfMovement').length===8&&document.querySelectorAll('.cfMovementCards .cfMovement:disabled').length===5);
 const restricted=page.locator('.cfMovementCards .cfMovement:disabled');
 assert.ok((await restricted.allTextContents()).every(text=>/أثر حسابي|حركة مالية/.test(text)));confidential(await page.locator('.cashFinanceV2').innerText(),'Cash ledger UI');
 const detailCalls=()=>h.calls.filter(c=>c.path.endsWith('/rpc/solar_cash_movement_detail')).length;
 const detailBefore=detailCalls();await restricted.evaluateAll(buttons=>buttons.forEach(button=>button.click()));await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
 assert.equal(detailCalls(),detailBefore,'Restricted cash effects must not open a detail RPC');
 await h.layout(page,'cash-generic-effects',page.locator('.cfLedger'));
 await page.locator('.cfMovementCards .cfMovement').filter({hasText:'Own visible customer'}).click();
 await page.locator('.cashMovementPanel').getByText(/Own visible material/).first().waitFor();
 assert.equal(detailCalls(),detailBefore+1,'Own cash invoice remains openable');confidential(await page.locator('.cashMovementPanel').innerText(),'Own cash detail');
 h.checks.cashGenericLiveArchivedEffectsAndOwnDetail=true;
 console.log('PASS cash generic effects and own detail');

 await page.goto(process.env.SOLAR_APP_URL+'/?section=cash&cashView=reports');
 const statement=page.getByRole('region',{name:'كشف صندوق حسب الفترة'});
 await statement.getByRole('button',{name:'عرض كشف الفترة',exact:true}).click();
 await statement.locator('.cashStatementScreen').waitFor();
 assert.equal(await statement.locator('.cfReportSummary').count(),2,'IQD and USD remain separate');
 assert.match(await statement.locator('.cfReportSummary.IQD .cashStatementFinalBalance').innerText(),/940/);
 confidential(await statement.innerText(),'Cash statement UI');
 const cashHtml=await h.report(page,ctx,statement.locator('.reportExport'),'cash-statement-generic');
 confidential(cashHtml,'Cash statement PDF HTML');assert.match(cashHtml,/أثر حسابي|حركة مالية/);assert.ok(cashHtml.includes('Own visible customer'));
 for(const number of hiddenReceipts)assert.ok(!cashHtml.includes('#'+number+'<'),'PDF must not label a foreign receipt');
 h.checks.cashStatementSeparateCurrenciesGenericPDF=true;
 console.log('PASS cash statement PDF');

 await page.goto(process.env.SOLAR_APP_URL+'/?section=profit');
 await page.locator('.profitMovementRestricted').first().waitFor();
 assert.equal(await page.locator('.profitMovementRestricted').count(),2,'Live assigned profit and deleted settled checkpoint are generic');
 const effects=page.locator('.profitMovementRestricted');
 assert.equal(await effects.locator('button,summary,a').count(),0,'Generic profit effects have no receipt links or controls');
 const profitBefore=h.calls.filter(c=>c.path.endsWith('/rpc/solar_profit_detail')).length;
 await effects.evaluateAll(nodes=>nodes.forEach(node=>node.click()));await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
 assert.equal(h.calls.filter(c=>c.path.endsWith('/rpc/solar_profit_detail')).length,profitBefore,'Generic profit effect must not fetch invoice details');
 const effectsText=await effects.allTextContents();assert.ok(effectsText.some(t=>t.includes('51')));assert.ok(effectsText.some(t=>t.includes('6')));
 confidential(await page.locator('body').innerText(),'Own profit UI');
 await h.layout(page,'profit-generic-effects',page.locator('.staffProfitRows'));
 const profitSection=page.locator('.uiPanel').filter({has:page.locator('.staffProfitRows')});
 const profitHtml=await h.report(page,ctx,profitSection.locator('.reportExport'),'profit-statement-generic');
 confidential(profitHtml,'Profit statement PDF HTML');assert.match(profitHtml,/أثر حسابي|ربح محوّل/);
 await page.locator('.staffProfitRows details.profitMovement summary').filter({hasText:'Own visible customer'}).click();
 await page.locator('.profitMovementTable').getByText(/Own visible material/).first().waitFor();
 confidential(await page.locator('.profitMovementDetail').innerText(),'Own profit invoice detail');
 assert.equal(h.calls.filter(c=>c.path.endsWith('/rpc/solar_profit_detail')).length,profitBefore+1,'Own profit detail stays functional');
 h.checks.profitAvailableSettledEffectsGenericAndOwnDetail=true;

 const after=await financeState();
 assert.deepEqual(after.cash.summary,initial.cash.summary);assert.equal(after.cash.count,initial.cash.count);
 for(const key of['available','profit','settled','retainedProfit','token'])assert.deepEqual(after.profit[key],initial.profit[key],'Profit '+key+' changed while reading');
 assert.equal(after.checkpoints,initial.checkpoints);assert.equal(after.settlements,initial.settlements);assert.equal(fingerprint(),before,'Read-only browser changed financial state');
 for(const call of h.calls){
  assert.ok(!/solar_(?:cash_save|cash_record|cash_movement_delete|invoice_save)$/.test(call.path),'Unexpected financial write endpoint');
  if(call.path.endsWith('/solar_profit_workspace'))assert.ok(['overview','balance'].includes(call.body.action),'Unexpected settlement write');
 }
 h.checks.noFinancialOrSettlementChanges=true;h.checks.maskedApiResponses=responses.length;
 await h.finish();console.log('PASS V4.12 finance browser: five generic cash effects, two generic profit effects, own details retained, cash/profit PDF preview/download/share, mobile/desktop, unchanged balances/checkpoints/settlements.');
}catch(error){await h.fail(error);throw error;}finally{await h.close();}
