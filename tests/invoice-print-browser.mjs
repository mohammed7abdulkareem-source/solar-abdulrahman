// Document HTML → real browser layout → production PDF rasterizer → scannable QR.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
const jpeg=createRequire(import.meta.url)('jpeg-js');
import jsQR from 'jsqr';
import {a4} from '../app/document-template.mjs';
import {salesDocument} from '../app/sales-document.mjs';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const module=await readFile(new URL('../app/pdf-share.mjs',import.meta.url),'utf8');
const server=createServer((req,res)=>{res.setHeader('Content-Type',req.url==='/pdf-share.mjs'?'application/javascript':'text/html');res.end(req.url==='/pdf-share.mjs'?module:'<!doctype html><title>Local invoice print verification</title>');});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
const page=await browser.newPage({viewport:{width:794,height:1123}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
const dir='/workspace/solar-review/invoices-v348';await mkdir(dir,{recursive:true});
const row={kind:'sale',receiptNo:4,created_at:'2026-10-19T10:00:00Z',creatorName:'عبدالرحمن عبدالله',party_name:'عطالله حجي',total:13720000,items:[{product_id:1,product_name:'10KW/MAGIC',brand_name:'MAGIC',category:'بطارية',qty:8,price:1715000}],invoiceAccount:{available:true,previousBalance:2000000,invoiceTotal:13720000,paidNow:0,balanceAfter:15720000,lastPayment:{date:'2026-10-18T10:00:00Z',amount:300000,receiptNo:17}},warrantyToken:'11111111-1111-1111-1111-111111111111',warehouseQrToken:'22222222-2222-2222-2222-222222222222',warranty:{enabled:true,items:[{id:1,duration:2,unit:'years'}],maintenance:{duration:6,unit:'months'},notes:'يشمل ضمان المواد عيوب الصناعة حسب شروط الشركة.\nيُرجى الاحتفاظ بهذه الفاتورة للمراجعة.'}};
async function render(name,value,customer=true){
 const d=salesDocument(value,customer),html=a4(d.title,d.body,d.total,d.subtitle);await page.goto(base);await page.setContent(html);await page.evaluate(()=>document.fonts.ready);
 const style=await page.locator('.invoiceItems th').first().evaluate(x=>({weight:getComputedStyle(x).fontWeight,color:getComputedStyle(x).color}));assert.equal(style.weight,'800');assert.equal(style.color,'rgb(16, 43, 55)');
 const result=await page.evaluate(async({html,base})=>{const {createPdfDocument}=await import(base+'/pdf-share.mjs');const pdf=await createPdfDocument(html);return {bytes:Array.from(new Uint8Array(await pdf.blob.arrayBuffer())),pages:pdf.pages.map(p=>({width:p.width,height:p.height,bytes:Array.from(p.bytes)}))};},{html,base});
 await writeFile(dir+'/'+name+'.pdf',Buffer.from(result.bytes));
 const first=result.pages[0],image=jpeg.decode(Buffer.from(first.bytes),{useTArray:true}),qr=jsQR(new Uint8ClampedArray(image.data),image.width,image.height);assert.equal(qr?.data,'https://solar-abdulrahman.vercel.app/warranty/'+(customer?row.warrantyToken:row.warehouseQrToken),'QR scan of actual PDF page');
 await page.goto(base);await page.setContent('<img style="width:100%;max-width:794px" src="data:image/jpeg;base64,'+Buffer.from(first.bytes).toString('base64')+'">');await page.locator('img').evaluate(img=>img.decode());await page.screenshot({path:dir+'/'+name+'.png',fullPage:true});
 return result;
}
try{
 const simple=await render('wholesale-receipt',row);assert.equal(simple.pages.length,1,'normal invoice should fit one readable page');
 const system=await render('system-receipt',{...row,kind:'system',customer_address:'بغداد — عنوان الزبون',customer_phone:'07701234567',installerName:'مهندس المنظومة',install_date:'2026-10-21',install_time:'09:00',installation_status:'pending'});assert.equal(system.pages.length,1);
 await render('warehouse-receipt',row,false);
 const long={...row,items:Array.from({length:60},(_,i)=>({product_id:i+1,product_name:'مادة ضمان '+String(i+1).padStart(3,'0'),qty:1,price:10000})),warranty:{...row.warranty,items:Array.from({length:60},(_,i)=>({id:i+1,duration:2,unit:'years'})),notes:'شروط ضمان مفصلة. '.repeat(400)}};
 const many=await render('long-invoice-warranty',long);assert.ok(many.pages.length>=5);assert.ok(many.pages.length<=12);
 // Verify pagination preserves every material and warranty row without clipping.
 const d=salesDocument(long),html=a4(d.title,d.body,d.total,d.subtitle);await page.goto(base);await page.setContent(html);
 const layout=await page.evaluate(async base=>{const {reportPages}=await import(base+'/pdf-share.mjs');document.querySelector('.previewNav').remove();document.querySelector('.actions').remove();const sheet=document.querySelector('.sheet');sheet.style.cssText='width:190mm;min-height:0;padding:0';const pages=reportPages(sheet,document);return {items:pages.reduce((sum,p)=>sum+p.querySelectorAll('.invoiceItems tbody tr').length,0),warranties:pages.reduce((sum,p)=>sum+p.querySelectorAll('.warrantyTable tbody tr').length,0),maxHeight:Math.max(...pages.map(p=>p.getBoundingClientRect().height)),pages:pages.length};},base);
 assert.equal(layout.items,60);assert.equal(layout.warranties,61);assert.ok(layout.maxHeight<1045,JSON.stringify(layout));assert.deepEqual(errors,[]);
 console.log('PASS readable one-page wholesale/system and warehouse PDFs; actual raster QR scans; long item/warranty tables and notes preserved across '+layout.pages+' pages.');
}finally{await browser.close();server.close();}
