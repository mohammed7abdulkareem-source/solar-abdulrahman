// Requires version4121-warehouse-receipts-fixture.sql on a disposable PostgREST database.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
process.env.SOLAR_FIXTURE_DB ||= 'solar_v4121_warehouse_docs_browser';
process.env.SOLAR_FIXTURE_API ||= 'http://127.0.0.1:3290';
process.env.SOLAR_APP_URL ||= 'http://127.0.0.1:3291';
process.env.SOLAR_ARTIFACT_DIR ||= '/workspace/solar-review/v4121/warehouse-receipts-browser';
const {db,sql,rpc,createHarness}=await import('./version4-browser-support.mjs');
assert.equal(db,'solar_v4121_warehouse_docs_browser');
const worker='00000000-0000-0000-0000-000000412101';
const invoices=JSON.parse(sql("select jsonb_agg(jsonb_build_object('id',id,'n',receipt_no,'party',party_name) order by party_id desc) from transactions where party_id in(-412101,-412102,-412103) and kind='sale'"));
const transfers=JSON.parse(sql("select jsonb_agg(jsonb_build_object('id',id,'n',receipt_no,'state',status,'source',from_name,'target',to_name) order by id) from solar_private.stock_transfers where id::text like '00000000-0000-0000-0000-00000041211%'"));
assert.equal(invoices.length,3);assert.equal(transfers.length,5);
const button=(view,name)=>view.getByRole('button',{name,exact:true});
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const forbidden=/PRIVATE-COMMERCIAL-NOTE|987,?654|197,?531|196,?421|سعر البيع|سعر الشراء|مجموع الأرباح|ربح الوصل|رصيد الزبون|كلفة المواد|\bIQD\b|\bUSD\b|د\.ع/;
const h=await createHarness('warehouse-receipts');
const path=(transfer,id)=>'/?section=warehouse&'+(transfer?'stockTransfer':'job')+'='+id;
async function rowFor(page,transfer,row){
 const card=transfer?page.locator('.sourceTransferOrder.highlighted'):page.locator('#warehouse-order-'+row.id);
 await card.waitFor();
 if(!(await card.locator('details').evaluate(e=>e.open)))await card.locator('summary').click();
 const actions=card.locator('.warehouseReceiptActions');
 await actions.getByRole('button',{name:'حفظ PDF',exact:true}).waitFor();
 return {card,actions};
}
async function receipt(page,actions,record,transfer,state,qty){
 await actions.locator('.reportButton.download:not([disabled])').waitFor({timeout:90000});
 const body=await page.evaluate(({state,n})=>{
  for(const html of [...window.__documentHtmls].reverse()){
   const doc=new DOMParser().parseFromString(html,'text/html'),slip=doc.querySelector('.warehouseSlip');
   if(slip&&slip.dataset.slipStatus===state&&slip.textContent.includes(String(n))){
    return {text:slip.textContent,total:slip.querySelector('tfoot .wsQty')?.textContent,head:slip.querySelector('.wsIdentifier')?.textContent};
   }
  }return null;
 },{state,n:record.n});
 assert.ok(body,'Missing operational document '+state);
 assert.ok(body.text.includes('لوح وثائق المخزن'));
 assert.ok(body.text.includes('مجموع الكميات'));
 assert.equal(body.total.replace(/[^0-9.]/g,''),String(qty));
 assert.doesNotMatch(body.text,forbidden);
 if(transfer){assert.ok(body.text.includes(record.source)&&body.text.includes(record.target));}
 else{assert.ok(body.text.includes(record.party));assert.ok(body.text.includes('مخزن التجهيز'));}
 if(['posted','ready','reversed'].includes(state))assert.match(body.text,/جهّز الوصل/);
 h.checks['status-'+state]={qty,visible:true,operationalOnly:true};
}
async function download(page,trigger,file){
 const [dl]=await Promise.all([page.waitForEvent('download'),trigger.click()]);
 assert.match(dl.suggestedFilename(),/\.pdf$/);
 await dl.saveAs(file);
 return readFile(file);
}
async function delivery(page,ctx,actions,label){
 const dl=await download(page,button(actions,'حفظ PDF'),h.dir+'/'+label+'.pdf');
 assert.equal(dl.subarray(0,5).toString(),'%PDF-');
 const digest=hash(dl);
 const [preview]=await Promise.all([ctx.waitForEvent('page'),button(actions,'معاينة').click()]);
 await preview.locator('.pdfPage img').first().waitFor();
 const previewImages=await preview.locator('.pdfPage img').evaluateAll(async imgs=>Promise.all(imgs.map(async img=>{
  const bytes=await(await fetch(img.src)).arrayBuffer();return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),n=>n.toString(16).padStart(2,'0')).join('');
 })));
 execFileSync('pdfimages',['-j',h.dir+'/'+label+'.pdf',h.dir+'/'+label+'-image'],{stdio:'pipe'});
 const imageFiles=(await readdir(h.dir)).filter(n=>n.startsWith(label+'-image-')&&n.endsWith('.jpg')).sort();
 assert.deepEqual(await Promise.all(imageFiles.map(async file=>hash(await readFile(h.dir+'/'+file)))),previewImages);
 const previewBytes=await download(preview,preview.locator('#pdfDownload'),h.dir+'/'+label+'-preview.pdf');
 assert.equal(hash(previewBytes),digest);
 await preview.screenshot({path:h.dir+'/'+label+'-preview.png'});
 await preview.close();
 await page.evaluate(()=>{window.__slipPrintCalls=0;const open=window.open.bind(window);window.open=(...args)=>{const child=open(...args);if(child)child.print=()=>{window.__slipPrintCalls++;};return child;};});
 const [printView]=await Promise.all([ctx.waitForEvent('page'),button(actions,'طباعة').click()]);
 await page.waitForFunction(()=>window.__slipPrintCalls>0);
 assert.equal(await printView.locator('.pdfPage img').count(),previewImages.length);await printView.close();
 const sharedBefore=await page.evaluate(()=>window.__shares.length);
 const share=button(actions,'مشاركة وإرسال');
 await share.click();
 await page.waitForFunction(n=>window.__shares.length>n,sharedBefore);
 const shared=await page.evaluate(()=>window.__shares.at(-1));
 assert.equal(shared.hash,digest);assert.equal(shared.type,'application/pdf');assert.equal(shared.active,true);
 await page.evaluate(()=>Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>false}));
 assert.equal(hash(await download(page,share,h.dir+'/'+label+'-share-fallback.pdf')),digest);
 await page.evaluate(()=>Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>true}));
 h.checks[label+'Delivery']={pdfBytes:dl.length,pages:previewImages.length,samePreviewImages:true,printed:true,nativeShareWithActivation:true,fallbackMatchesPdf:true};
}
try{
 const {page,ctx}=await h.open(worker,path(false,invoices[1].id));
 const head=page.locator('.warehouseDayHead');await head.waitFor();
 assert.equal(await head.getByRole('heading',{name:'قائمة تجهيز المخزن',exact:true}).count(),1);
 assert.equal(await button(head,'الرجوع إلى الشاشة السابقة').count(),1);
 assert.equal(await page.locator('.workspaceBack').count(),0);
 const ready=await rowFor(page,false,invoices[1]);
 await receipt(page,ready.actions,invoices[1],false,'ready',3);
 await h.layout(page,'prepared-sale',ready.actions);
 await delivery(page,ctx,ready.actions,'warehouse-sale');
 const workerHome=(await h.open(worker)).page;
 const go=workerHome.locator('main a[href="/?section=warehouse"]:visible');
 await go.first().click();
 await workerHome.getByTestId('warehouse-daily-queue').waitFor();
 for(const [index,state,qty] of [[0,'pending',2],[2,'pricing',5]]){
  await workerHome.goto(process.env.SOLAR_APP_URL+path(false,invoices[index].id));
  const {actions}=await rowFor(workerHome,false,invoices[index]);await receipt(workerHome,actions,invoices[index],false,state,qty);
 }
 const transferNav=workerHome.getByRole('navigation',{name:'نوع تجهيز المخزن'});
 await transferNav.getByRole('button',{name:/طلبات نقل المخازن/}).click();
 await workerHome.locator('.warehouseTransferQueue').waitFor();
 for(const record of transfers.slice(0,4)){
  await page.goto(process.env.SOLAR_APP_URL+path(true,record.id));
  const {actions,card}=await rowFor(page,true,record);
  await receipt(page,actions,record,true,record.state,4);
  if(record.state==='posted'){
   await h.layout(page,'posted-transfer',actions);await delivery(page,ctx,actions,'warehouse-transfer');
  }
  if(record.state!=='pending')assert.equal(await button(card,'تأكيد تجهيز النقل').count(),0);
 }
 const outside=transfers[4];
 const transferQueue=id=>rpc(worker,'solar_inventory',{action:'transfer_queue',payload:{id,state:'',search:'',offset:0,warehouseId:null}});
 const own=await transferQueue(transfers[1].id);
 assert.equal(own.rows.length,1);assert.equal(own.rows[0].id,transfers[1].id);
 const publicLine=own.rows[0].items[0];
 assert.ok(!Object.keys(publicLine).some(key=>/cost|price|profit|margin/i.test(key)));
 const other=await transferQueue(outside.id);
 assert.ok(!other.rows.some(r=>r.id===outside.id));
 await page.goto(process.env.SOLAR_APP_URL+path(true,outside.id));
 await page.locator('.warehouseTransferQueue').waitFor();
 await page.getByText(/لا توجد طلبات|لا توجد تحويلات/).first().waitFor();
 assert.equal(await page.locator('.warehouseReceiptActions').count(),0);
 assert.ok(!h.calls.some(c=>['solar_warehouse_action','solar_invoice_save'].includes(c.path.split('/').at(-1))||c.body?.action==='prepare_transfer'));
 h.checks.workerNavigation={homeAndBothDirectLinks:true,otherSourceHidden:true,noOperationalWrites:true};
 await h.finish();console.log('PASS warehouse receipts, all statuses, PDF delivery and no financial data');
}catch(error){await h.fail(error);throw error;}
finally{await h.close();}
