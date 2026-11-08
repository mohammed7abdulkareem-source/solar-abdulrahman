// Isolated layout test: no API requests or financial writes.
import assert from 'node:assert/strict';
import {readFile,mkdir} from 'node:fs/promises';
import {a4} from '../app/document-template.mjs';
import {cashStatementDocument,cashStatementTable} from '../app/cash-statement-report.mjs';
import {cashStatementStyle} from '../app/cash-statement-style.mjs';
import {materialMovementDocument} from '../app/material-movement-utils.mjs';
import {movementDocument} from '../app/warehouse-utils.mjs';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const source=await readFile(new URL('../app/pdf-share.mjs',import.meta.url),'utf8');
const cashCss=await readFile(new URL('../app/cash-period-statement.css',import.meta.url),'utf8');
const rows=Array.from({length:45},(_,i)=>({id:'cash:'+i,created_at:'2026-11-07T09:00:00Z',kind:i%2?'cash_expense':'cash_income',party:'قاصة اختبار',receipt_no:i+1,delta:i%2?-5000:10000,balance:123456789.25,note:i===0?'ملاحظات عربية كاملة '.repeat(70):'حركة مختبرة'}));
const group={ownerId:'a',ownerName:'المستخدم التجريبي',currency:'IQD',opening:1000000,incoming:230000,outgoing:110000,closing:1120000,rows};
const cash={ownerName:group.ownerName,from:'2026-11-01',to:'2026-11-07',asOf:'2026-11-08T09:00:00Z',count:45,ledgers:[group,{...group,currency:'USD',opening:250.25,incoming:40,outgoing:10,closing:280.25,rows:[]}]};
const materialRows=Array.from({length:60},(_,i)=>({id:'material:'+i,date:'2026-11-07T09:00:00Z',receiptNo:i+1,kind:i%2?'sale':'purchase',name:'ألواح شمسية',party:i%2?'العميل':'المورد',warehouseName:'المخزن الرئيسي',inQty:i%2?0:5,outQty:i%2?3:0,balance:120.125,createdByName:'مستخدم الاختبار',preparedByName:'المجهز',note:i===0?'ملاحظات عربية كاملة '.repeat(70):'',pricing:{kind:i%2?'sale':'purchase',unitPrice:1234567.89,lineTotal:6172839.45}}));
const material={product:{name:'ألواح شمسية 600W',code:'001',brand:'FULLMAX'},withPrices:true,from:'2026-11-01',to:'2026-11-07',scope:'own',currentQty:300,warehouses:[{name:'المخزن الرئيسي',beforeFirst:100,inQty:150,outQty:90,afterLast:160,currentQty:300}]};
const out=process.env.SOLAR_REPORT_ARTIFACTS;
if(out)await mkdir(out,{recursive:true});
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
try{
 const page=await browser.newPage({viewport:{width:794,height:1123}});
 await page.route('**/*',route=>route.abort());
 for(const [name,html,expected]of [
  ['cash',cashStatementDocument(cash,a4),45],
  ['material',a4('كشف حركة مادة',materialMovementDocument(material,materialRows)),60],
  ['all-movements',a4('سجل حركة المواد',movementDocument(materialRows)),60]
 ]){
  await page.setContent(html);await page.addScriptTag({type:'module',content:source+'\nwindow.__paginate=reportPages;'});await page.waitForFunction(()=>typeof window.__paginate==='function');
  const result=await page.evaluate(()=>{document.querySelectorAll('.previewNav,.actions').forEach(node=>node.remove());const sheet=document.querySelector('.sheet');for(const [k,v]of Object.entries({width:'190mm',maxWidth:'none',minHeight:'0',margin:'0 auto',padding:'0'}))sheet.style[k]=v;
   for(const style of sheet.querySelectorAll('style'))document.head.append(style.cloneNode(true));const pages=window.__paginate(sheet,document);sheet.remove();
   return {pages:pages.length,rows:pages.flatMap(p=>[...p.querySelectorAll('[data-movement-id]')].map(r=>r.dataset.movementId)),overflows:pages.flatMap((p,index)=>[...p.querySelectorAll('table')].filter(t=>t.getBoundingClientRect().width>p.getBoundingClientRect().width+1).map(()=>index)),heights:pages.map(p=>p.getBoundingClientRect().height),headers:pages.every(p=>!!p.querySelector(':scope>.head'))};});
  assert.ok(result.pages>1,name+' must paginate');assert.equal(result.rows.length,expected,name+' lost or repeated movements');assert.equal(new Set(result.rows).size,expected);assert.deepEqual(result.overflows,[],name+' table overflow');assert.ok(result.headers);assert.ok(result.heights.every(h=>h<=1047),name+' page body exceeds A4 printable height: '+result.heights);
  if(out)await page.locator('.sheet').first().screenshot({path:out+'/'+name+'-a4.png'});
  console.log('PASS',name,result.pages,'A4 pages,',expected,'rows, no table overflow');
 }
 await page.setViewportSize({width:390,height:844});
 await page.setContent('<html dir="rtl"><style>*{box-sizing:border-box}body{margin:0;font-family:Arial}main{width:100%;padding:12px}.cashPeriodStatement{min-width:0}'+cashStatementStyle+cashCss+'</style><main><section class="cashPeriodStatement"><p class="cashStatementSwipe">اسحب الجدول أفقيًا لعرض الأعمدة.</p><div class="cashStatementScreen"><div class="cashStatementScroll" role="region" tabindex="0" aria-label="كشف قاصة">'+cashStatementTable(group)+'</div></div></section></main></html>');
 const mobile=await page.evaluate(()=>{const region=document.querySelector('.cashStatementScroll');return {pageWidth:document.documentElement.scrollWidth,viewport:innerWidth,regionWidth:region.clientWidth,contentWidth:region.scrollWidth,tabIndex:region.tabIndex}});
 assert.ok(mobile.pageWidth<=mobile.viewport,'Cash screen scroll escaped to the page');assert.ok(mobile.contentWidth>mobile.regionWidth);assert.equal(mobile.tabIndex,0);
 if(out)await page.screenshot({path:out+'/cash-mobile.png'});
 console.log('PASS mobile cash table contains horizontal scrolling at 390px');
}finally{await browser.close();}
