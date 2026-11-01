// Real document renderer and preview controls, without any database connection.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {newQuote,calculateQuote,quoteDocument,money} from '../app/tahseel-utils.mjs';
import {a4} from '../app/document-template.mjs';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const dir=process.env.SOLAR_ARTIFACT_DIR||'/workspace/solar-review/v393/print';await mkdir(dir,{recursive:true});
const modules=new Map(await Promise.all(['pdf-share.mjs','pdf-preview.mjs','premium-pdf.mjs','ui-icons.mjs'].map(async name=>['/'+name,await readFile(new URL('../app/'+name,import.meta.url),'utf8')])));
const server=createServer((req,res)=>{res.setHeader('Content-Type',modules.has(req.url)?'application/javascript':'text/html');res.end(modules.get(req.url)||'<!doctype html><title>Quotation print verification</title>');});await new Promise(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),context=await browser.newContext({viewport:{width:794,height:1123}}),page=await context.newPage();
const form={...newQuote(15),customer:'محمد فرات',day:'67',night:'50',batteryCapacity:'25',inverterQty:'2',panel:{id:1,name:'600W',brand:'FULLMAX',cost:'120000'},battery:{id:2,name:'25KW',brand:'FULLMAX',cost:'3500000'},inverter:{id:3,name:'8.6KW/IP66/HYBRID',brand:'FULLMAX',cost:'2100000'}};
const htmlFor=(form,internal=false)=>{const q=calculateQuote(form);return a4(internal?'التحصيل — تفاصيل الكلفة':'عرض سعر منظومة',quoteDocument(form,internal,q),money(q.price)+' د.ع','٢٠٢٦/١١/١');};
const results={};
async function render(html,name){
 await page.goto(base);const rendered=await page.evaluate(async({base,html})=>{const {createPdfDocument}=await import(base+'/pdf-share.mjs');const d=await createPdfDocument(html);return{pdf:Array.from(new Uint8Array(await d.blob.arrayBuffer())),pages:d.pages.map(p=>({width:p.width,height:p.height,bytes:Array.from(p.bytes)}))};},{base,html});
 assert.equal(Buffer.from(rendered.pdf).subarray(0,5).toString(),'%PDF-');await writeFile(dir+'/'+name+'.pdf',Buffer.from(rendered.pdf));
 for(const [i,p]of rendered.pages.entries())await writeFile(dir+'/'+name+'-'+(i+1)+'.jpg',Buffer.from(p.bytes));
 return rendered;
}
async function layout(html){
 await page.goto(base);await page.setContent(html);return page.evaluate(async base=>{const {reportPages}=await import(base+'/pdf-share.mjs');document.querySelectorAll('.previewNav,.actions').forEach(e=>e.remove());const sheet=document.querySelector('.sheet');sheet.style.cssText='width:190mm;min-height:0;padding:0';const pages=reportPages(sheet,document);sheet.remove();return{pages:pages.length,heights:pages.map(p=>p.getBoundingClientRect().height),rowCount:pages.reduce((n,p)=>n+p.querySelectorAll('.quoteMaterials tbody tr').length,0),totalCount:pages.reduce((n,p)=>n+p.querySelectorAll(':scope>.total').length,0),text:pages.map(p=>p.textContent).join(' '),overflow:pages.flatMap(p=>[...p.querySelectorAll('.head,.quoteCustomer,.quoteDemandCard,.quoteMaterials table,.notes,.total,.foot')].filter(e=>e.scrollWidth>e.clientWidth+2).map(e=>e.className))};},base);
}
try{
 const original=JSON.stringify(form),html=htmlFor(form),q=calculateQuote(form);assert.equal(JSON.stringify(form),original);
 assert.equal(q.panelQty,32);assert.equal(q.batteryQty,2);assert.equal(q.inverterQty,2);assert.ok(html.includes('quoteSheet'));
 const basic=await layout(html);assert.equal(basic.pages,1,JSON.stringify(basic));assert.equal(basic.rowCount,3);assert.equal(basic.totalCount,1);assert.deepEqual(basic.overflow,[]);assert.ok(basic.heights.every(h=>h<1045));assert.ok(!html.includes('3,500,000')&&!html.includes('1,845,000'));
 const customer=await render(html,'customer');assert.equal(customer.pages.length,1);
 await page.goto(base);await page.setContent(html);await page.locator('.previewNav,.actions').evaluateAll(es=>es.forEach(e=>e.remove()));await page.screenshot({path:dir+'/customer-layout.png',fullPage:true});
 const internal=await layout(htmlFor(form,true));assert.equal(internal.rowCount,3);assert.equal(internal.totalCount,1);assert.deepEqual(internal.overflow,[]);assert.ok(internal.text.includes('عمولة المندوب'));assert.ok(internal.text.includes('3,500,000'));await render(htmlFor(form,true),'internal');
 const note=Array.from({length:110},(_,i)=>'ملاحظة'+i+' تفاصيل التجهيز والتنصيب').join('\n');
 const long={...form,customer:'المهندس '+('محمد عبدالله '.repeat(10)),phone:'07701234567',panel:{...form.panel,name:'لوح شمسي ثنائي الوجه 600 واط '+('تفاصيل المادة '.repeat(10))},notes:note+' <script>alert(1)</script>'};
 const longLayout=await layout(htmlFor(long));assert.ok(longLayout.pages>1);assert.equal(longLayout.rowCount,3);assert.equal(longLayout.totalCount,1);assert.deepEqual(longLayout.overflow,[]);assert.ok(longLayout.heights.every(h=>h<1045));for(let i=0;i<110;i++)assert.ok(longLayout.text.includes('ملاحظة'+i));assert.ok(!htmlFor(long).includes('<script>'));await render(htmlFor(long),'long-notes');
 const noNight={...form,night:'0',batteryCapacity:'',battery:null},noDay={...form,day:'0',panel:null};assert.equal((await layout(htmlFor(noNight))).rowCount,2);assert.equal((await layout(htmlFor(noDay))).rowCount,2);
 const largest={...form,day:'1000',night:'1000',inverterQty:'1000',panel:{...form.panel,cost:'10000000000'},battery:{...form.battery,cost:'10000000000'},inverter:{...form.inverter,cost:'10000000000'}};assert.deepEqual((await layout(htmlFor(largest))).overflow,[]);
 // Preview, download, share and print all use these same rendered bytes.
 await page.goto(base);await page.setContent('<button id="open">معاينة</button>');
 await page.evaluate(async({base,html})=>{const {previewPdf}=await import(base+'/pdf-preview.mjs');document.querySelector('#open').onclick=()=>previewPdf(html,'عرض سعر منظومة');},{base,html});
 const[preview]=await Promise.all([context.waitForEvent('page'),page.locator('#open').click()]);await preview.locator('#pdfPrint:not([disabled])').waitFor();assert.equal(await preview.locator('.pdfPage').count(),1);
 const[download]=await Promise.all([preview.waitForEvent('download'),preview.locator('#pdfDownload').click()]);await download.saveAs(dir+'/preview-download.pdf');assert.deepEqual(await readFile(dir+'/preview-download.pdf'),Buffer.from(customer.pdf));
 await preview.evaluate(()=>{window.__prints=0;window.print=()=>window.__prints++;window.__files=[];Object.defineProperty(navigator,'canShare',{configurable:true,value:()=>true});Object.defineProperty(navigator,'share',{configurable:true,value:async({files})=>window.__files.push({type:files[0].type,size:files[0].size})});});
 await preview.locator('#pdfPrint').click();assert.equal(await preview.evaluate(()=>window.__prints),1);await preview.locator('#pdfShare').click();await preview.waitForFunction(()=>window.__files.length===1);assert.equal((await preview.evaluate(()=>window.__files))[0].type,'application/pdf');
 for(const width of[360,768,1440]){await preview.setViewportSize({width,height:920});assert.ok(await preview.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await preview.screenshot({path:dir+'/preview-'+width+'.png',fullPage:true});}
 await preview.locator('#pdfClose').click();
 // Popup-blocked browsers retain the same document through the inline preview.
 await page.evaluate(()=>window.open=()=>null);await page.locator('#open').click();const inline=page.frameLocator('.inlineDocumentPreview iframe');await inline.locator('#pdfPrint:not([disabled])').waitFor();assert.equal(await inline.locator('.pdfPage').count(),1);await inline.locator('#pdfClose').click();assert.equal(await page.locator('.inlineDocumentPreview').count(),0);
 results.pass=true;results.customerPages=basic.pages;results.internalPages=internal.pages;results.longNotePages=longLayout.pages;results.exactQuantitiesAndTotals=true;results.privateCostsHidden=true;results.longNotesComplete=true;results.noFinancialWrites=true;results.previewDownloadExact=true;results.shareAndPrint=true;results.popupFallback=true;results.noOverflow=[360,768,1440];await writeFile(dir+'/results.json',JSON.stringify(results,null,2));console.log('PASS quotation PDF: themed artwork, actual quantities/prices, private costs, long names/notes pagination, preview/download/share/print, popup fallback and mobile widths');
}finally{await context.close();await browser.close();server.close();}
