// Real report builders and A4 pagination, with synthetic data only and all network blocked.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {a4} from '../app/document-template.mjs';
import {profitBalanceReport} from '../app/profit-balance-report.mjs';
import {profitStatementDocument,profitStatementRows} from '../app/profit-statement-report.mjs';
import {profitMaterialDocument} from '../app/profit-material-document.mjs';
import {capitalSnapshotReport} from '../app/capital-snapshot-report.mjs';
import {pendingSystemsDocument} from '../app/pending-systems-report.mjs';
import {periodSalesDocument} from '../app/period-sales-report.mjs';
import {salesDocument} from '../app/sales-document.mjs';
import {newQuote,calculateQuote,quoteDocument,money} from '../app/tahseel-utils.mjs';

const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const source=await readFile(new URL('../app/pdf-share.mjs',import.meta.url),'utf8');
const dir=process.env.SOLAR_REPORT_ARTIFACTS||'/workspace/solar-review/report-clarity/summary';
await mkdir(dir,{recursive:true});
const big=9876543210.75,from='2026-11-01',to='2026-11-08',asOf='2026-11-08T12:00:00Z';
const profitRows=Array.from({length:48},(_,i)=>({id:i,date:from,kind:i%2?'system':'sale',party:'عميل اختبار '+(i+1),receiptNo:i+1,sales:big,cost:big-1000,earned:i%2?-big:big,settled:1000,available:i%2?-big:big}));
const statementRows=profitRows.map((r,i)=>({date:r.date,label:'حركة أرباح '+(i+1),receiptNo:r.receiptNo,value:r.earned,settled:r.settled,available:r.available,deleted:i===0}));
const material={party:'عميل تجريبي',receiptNo:499,date:from,creatorName:'المستخدم التجريبي',warehouseName:'المخزن الرئيسي',items:Array.from({length:48},(_,i)=>({name:'مادة اختبار '+(i+1),code:'SKU-'+i,brand:'FULLMAX',category:'بطارية',qty:2,unitPrice:big,lineSales:big*2,unitCost:big/2,lineCost:big,lineProfit:i%2?-big:big})),sales:big,materialsCost:big/2,grossProfit:big/2,invoiceExpenses:75000,installationExpenses:200000,profitAdjustment:-1000,netProfit:-big};
const capital={scope:'company',asOf,stock:{value:big},cash:{iqd:-big,usd:1234567.89,usdBook:big},customers:{receivable:big,advances:big},suppliers:{prepayments:big,payable:big},assets:big*3,liabilities:big*4,net:-big};
const pending={scope:'own',asOf,from,to,summary:{count:48,accountCollections:big,provisionalProfit:-big,paidExpenses:big/2},rows:Array.from({length:48},(_,i)=>({receiptNo:i+1,date:from,customer:'زبون منظومة '+(i+1),creatorName:'المسؤول',status:'in_progress',total:big,approvedExpenses:big/2,provisionalProfit:i%2?-big:big})),accounts:Array.from({length:25},(_,i)=>({customer:'حساب زبون '+(i+1),openCount:2,receiptCount:3,collected:big,balance:i%2?-big:big}))};
const period={scope:'own',ownerName:'المستخدم التجريبي',from,to,asOf,kind:'system',status:'closed',search:'بطارية',summary:{materialCount:60,quantitySold:big,invoiceCount:48},rows:Array.from({length:60},(_,i)=>({name:'مادة مباعة '+(i+1),code:'PERIOD-'+i,brand:'FULLMAX',category:'بطارية',quantitySold:1234567.125,remainingQty:i===0?null:1234567.125}))};
const quote={...newQuote(15),customer:'عميل عرض سعر',day:'67',night:'50',batteryCapacity:'25',inverterQty:'2',panel:{id:1,name:'600W',brand:'FULLMAX',cost:'120000'},battery:{id:2,name:'25KW',brand:'FULLMAX',cost:'3500000'},inverter:{id:3,name:'8.6KW/IP66/HYBRID',brand:'FULLMAX',cost:'2100000'}};
const quoteTotals=calculateQuote(quote);
const invoice={kind:'sale',receipt_no:500,created_at:from,party_name:'عميل فاتورة',creatorName:'مسؤول الفاتورة',total:big,items:Array.from({length:35},(_,i)=>({product_name:'فقرة فاتورة '+(i+1),brand_name:'FULLMAX',category:'انفيرتر',qty:2,price:big/2})),invoiceAccount:{available:true,previousBalance:-big,invoiceTotal:big,paidNow:0,balanceAfter:0,lastPayment:{amount:big,date:from,receiptNo:90}}};
const unchanged=JSON.stringify({profitRows,statementRows,material,capital,pending,period,quote,invoice});
const profit={balance:{remaining:-big,period:{earned:big,settled:big*2,available:-big}},ownerName:'المستخدم التجريبي',from,to,rows:profitRows,expenses:big,fx:-big,externalProfit:big,type:'all'};
const doc=(name,document,options={})=>({name,...document,...options});
const cases=[
 doc('company-profit',{title:'تقرير الأرباح',body:profitBalanceReport(profit),total:money(-big)+' د.ع'},{rows:48,pages:true,text:['الرصيد الحالي · جميع الفترات','نتائج الفترة المختارة','الجملة والمنظومات المغلقة']}),
 doc('user-profit',{title:'كشف أرباح المستخدم',body:profitStatementDocument({ownerName:'المستخدم التجريبي',retainedProfit:-big,available:big,rows:statementRows},from,to)},{rows:48,pages:true,text:['الرصيد المتبقي بعد التسوية','ألغيت الحركة']}),
 doc('settlement-snapshot',{title:'كشف تسوية أرباح',body:profitStatementRows(statementRows,big,{snapshot:true})},{rows:48,pages:true,text:['لقطة محفوظة للطلب، وليست الرصيد الحالي.']}),
 doc('material-profit',profitMaterialDocument({...material,kind:'sale'},{settled:big,available:-big}),{rows:48,pages:true,text:['ربح الفقرة','مطابقة ربح الحركة والتسويات']}),
 doc('system-profit',profitMaterialDocument({...material,kind:'system'},{settled:big,available:-big}),{rows:48,pages:true,text:['سعر المنظومة إجمالي متفق عليه','ربح الحركة المعتمد']}),
 doc('capital-snapshot',capitalSnapshotReport(capital),{rows:10,text:['القيمة الدفترية','USD','توقيت بغداد','إجمالي الموجودات','إجمالي المطلوبات']}),
 doc('pending-systems',pendingSystemsDocument(pending),{rows:73,pages:true,text:['لا يمثل نقدًا متاحًا للتوزيع','وليسا مقصورين على فترة بيع المنظومات','رصيد الحساب الموجب مستحق لنا على العميل']}),
 doc('period-sales',periodSalesDocument(period),{rows:60,pages:true,text:['حالة التنصيب: ملف مغلق','لا يمثل رصيد نهاية الفترة','عدد الفواتير']}),
 doc('sales-invoice',salesDocument(invoice),{rows:35,pages:true,special:'invoiceSheet',text:['ملخص حساب الزبون عند إصدار الفاتورة','آخر تسديد سابق']}),
 doc('quotation',{title:'عرض سعر منظومة',body:quoteDocument(quote,false,quoteTotals),total:money(quoteTotals.price)+' د.ع',subtitle:to},{rows:3,special:'quoteSheet',text:['عرض سعر تقديري']})
];
assert.equal(JSON.stringify({profitRows,statementRows,material,capital,pending,period,quote,invoice}),unchanged,'Report builders mutated source financial objects');
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
const results=[];
try{
 const page=await browser.newPage({viewport:{width:794,height:1123}});
 await page.route('**/*',route=>route.abort());
 for(const test of cases){
  await page.setContent(a4(test.title,test.body,test.total||'',test.subtitle||''));
  await page.addScriptTag({type:'module',content:source+'\nwindow.__paginate=reportPages;'});
  await page.waitForFunction(()=>typeof window.__paginate==='function');
  const result=await page.evaluate(()=>{
   document.querySelectorAll('.previewNav,.actions').forEach(node=>node.remove());
   const sheet=document.querySelector('.sheet');
   for(const [key,value]of Object.entries({width:'190mm',maxWidth:'none',minHeight:'0',margin:'0 auto',padding:'0'}))sheet.style[key]=value;
   for(const style of sheet.querySelectorAll('style'))document.head.append(style.cloneNode(true));
   const expectedRows=[...sheet.querySelectorAll('tbody tr')].map((row,i)=>{row.dataset.qaRow=String(i);return row.textContent});
   const selector='.reportSummary,.reportCurrentBalance,.reportSectionTitle,.periodCounts,.documentCounts,.invoiceAccount,.total';
   const expectedBlocks=[...sheet.querySelectorAll(selector)].map(block=>block.textContent);
   const className=sheet.className,pages=window.__paginate(sheet,document);sheet.remove();
   const actualRows=pages.flatMap(p=>[...p.querySelectorAll('[data-qa-row]')].map(row=>({id:row.dataset.qaRow,text:row.textContent})));
   const blocks=pages.flatMap(p=>[...p.querySelectorAll(selector)].map(block=>block.textContent));
   const overflow=[],numericOverflow=[],numberDirectionErrors=[];let isolatedNumbers=0,negativeNumbers=0;
   for(const [index,p]of pages.entries()){
    const bound=p.getBoundingClientRect();
    for(const node of p.querySelectorAll('table,th,td,.reportSummary,.reportMetric,.reportCurrentBalance,.periodCounts,.total')){
     const r=node.getBoundingClientRect();
     if(r.left<bound.left-1||r.right>bound.right+1||node.scrollWidth>node.clientWidth+2)overflow.push({page:index+1,node:node.tagName,className:node.className,text:node.textContent.slice(0,100)});
    }
    for(const cell of p.querySelectorAll('td,.reportMetric>strong,.reportCurrentBalance,.total')){
     const walker=document.createTreeWalker(cell,NodeFilter.SHOW_TEXT),bound=cell.getBoundingClientRect();let node;
     while((node=walker.nextNode())){
      if(!/[-−+]?\d[\d,.]{7,}/.test(node.textContent))continue;
      const range=document.createRange();range.selectNodeContents(node);
      for(const r of range.getClientRects())if(r.left<bound.left-1||r.right>bound.right+1||r.top<bound.top-1||r.bottom>bound.bottom+1)numericOverflow.push({page:index+1,text:node.textContent});
     }
    }
    for(const number of p.querySelectorAll('.reportNumber')){
     isolatedNumbers++;
     const style=getComputedStyle(number),range=document.createRange();range.selectNodeContents(number);
     if(number.dir!=='ltr'||style.direction!=='ltr'||new Set([...range.getClientRects()].map(r=>Math.round(r.top))).size!==1||parseFloat(style.fontSize)<9)numberDirectionErrors.push(number.textContent);
     if(number.textContent.startsWith('-')){
      negativeNumbers++;
      const sign=document.createRange(),digit=document.createRange();sign.setStart(number.firstChild,0);sign.setEnd(number.firstChild,1);digit.setStart(number.firstChild,1);digit.setEnd(number.firstChild,2);
      if(sign.getBoundingClientRect().right>digit.getBoundingClientRect().left+1)numberDirectionErrors.push('misplaced minus: '+number.textContent);
     }
    }
   }
   return {pages:pages.length,heights:pages.map(p=>p.getBoundingClientRect().height),headers:pages.every(p=>!!p.querySelector(':scope>.head')),footers:pages.every((p,i)=>p.querySelector(':scope>.foot')?.textContent.includes('صفحة '+(i+1)+' من '+pages.length)),className,expectedRows,actualRows,expectedBlocks,blocks,overflow,numericOverflow,numberDirectionErrors,isolatedNumbers,negativeNumbers,text:pages.map(p=>p.textContent).join('\n')};
  });
  await page.locator('.sheet').first().screenshot({path:dir+'/'+test.name+'-first.png'});
  if(result.pages>1)await page.locator('.sheet').last().screenshot({path:dir+'/'+test.name+'-last.png'});
  results.push({name:test.name,pages:result.pages,rows:result.actualRows.length,maxHeight:Math.max(...result.heights),overflow:result.overflow,numericOverflow:result.numericOverflow,numberDirectionErrors:result.numberDirectionErrors,isolatedNumbers:result.isolatedNumbers,negativeNumbers:result.negativeNumbers,headers:result.headers,footers:result.footers});
  await writeFile(dir+'/results.json',JSON.stringify(results,null,2));
  assert.equal(result.expectedRows.length,test.rows,test.name+' fixture row count');
  assert.deepEqual(result.actualRows.map(row=>row.text),result.expectedRows,test.name+' lost/repeated/changed table rows');
  assert.equal(new Set(result.actualRows.map(row=>row.id)).size,test.rows,test.name+' duplicated rows');
  assert.deepEqual(result.blocks,result.expectedBlocks,test.name+' lost/repeated financial summaries or headings');
  assert.deepEqual(result.overflow,[],test.name+' content escaped A4 width');
  assert.deepEqual(result.numericOverflow,[],test.name+' large positive/negative numbers clipped');
  assert.deepEqual(result.numberDirectionErrors,[],test.name+' isolated amount wrapped or minus moved');
  if(['company-profit','material-profit','system-profit'].includes(test.name))assert.ok(result.isolatedNumbers>0,test.name+' missing direction-isolated table amounts');
  if(['company-profit','material-profit'].includes(test.name))assert.ok(result.negativeNumbers>0,test.name+' missing negative amount regression coverage');
  assert.ok(result.headers&&result.footers,test.name+' missing page header/footer');
  assert.ok(result.heights.every(h=>h<=1047),test.name+' content escaped A4 height: '+result.heights.join(', '));
  if(test.pages)assert.ok(result.pages>1,test.name+' should exercise pagination');
  if(test.special){assert.ok(result.className.includes(test.special));assert.ok(!result.className.includes('reportSheet'),test.name+' report styles leaked into specialized document');}
  else assert.ok(result.className.includes('reportSheet'),test.name+' missing report styles');
  for(const text of test.text)assert.ok(result.text.includes(text),test.name+' missing context: '+text);
  console.log('PASS',test.name,result.pages,'A4 pages,',test.rows,'rows; complete summaries, headings and unclipped large numbers');
 }
}finally{await browser.close();}
