// Browser layout check: a final invoice line and its subtotal stay together.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {a4} from '../app/document-template.mjs';
import {customerAccount,compactPeriod} from '../app/compact-party-utils.mjs';
import {groupedInvoicesBody} from '../app/party-invoice-reports.mjs';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const account=customerAccount({id:1,name:'اختبار',rows:Array.from({length:111},(_,i)=>({id:i+1,date:'2026-10-01T09:00Z',kind:'sale',total:10,cash:false,receiptNo:i+1}))});
const documents=Object.fromEntries(account.rows.map(r=>[r.id,{kind:'sale',items:[{product_name:'مادة '+r.id,qty:1,price:10}]}]));
const html=a4('كشف الفواتير',groupedInvoicesBody(account,compactPeriod(account.rows,'','','invoices'),'','',documents));
const source=await readFile(new URL('../app/pdf-share.mjs',import.meta.url),'utf8');
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
try{
 const page=await browser.newPage({viewport:{width:794,height:1123}});await page.setContent(html);await page.addScriptTag({type:'module',content:source+'\nwindow.__paginate=reportPages;'});await page.waitForFunction(()=>typeof window.__paginate==='function');
 const result=await page.evaluate(()=>{const sheet=document.querySelector('.sheet');for(const [k,v] of Object.entries({width:'190mm',maxWidth:'none',minHeight:'0',margin:'0 auto',padding:'0'}))sheet.style[k]=v;const pages=window.__paginate(sheet,document);return {pages:pages.length,headers:pages.map(p=>!!p.querySelector(':scope > .head')),invoiceTables:pages.flatMap(p=>[...p.querySelectorAll('table[data-pdf-keep-footer-with-row]')].map(t=>({rows:[...t.tBodies].reduce((n,b)=>n+b.rows.length,0),hasFooter:!!t.tFoot,text:t.textContent})))}});
 assert.ok(result.pages>5);assert.ok(result.headers.every(Boolean));assert.equal(result.invoiceTables.length,111);assert.ok(result.invoiceTables.every(t=>t.rows===1&&t.hasFooter),'An invoice subtotal was separated from its item');for(let i=1;i<=111;i++)assert.ok(result.invoiceTables.some(t=>t.text.includes('مادة '+i)));
 const many={id:8,name:'اختبار',type:'customer',currency:'IQD'},row={id:8,date:'2026-10-01T09:00Z',effect:500,amount:500,balance:500,receiptNo:999};
 const bigHtml=a4('فاتورة طويلة',groupedInvoicesBody(many,{rows:[row]},'','',{8:{kind:'sale',items:Array.from({length:55},(_,i)=>({product_name:'فقرة طويلة '+(i+1),qty:1,price:10}))}}));
 await page.setContent(bigHtml);await page.addScriptTag({type:'module',content:source+'\nwindow.__paginate=reportPages;'});await page.waitForFunction(()=>typeof window.__paginate==='function');
 const long=await page.evaluate(()=>{const sheet=document.querySelector('.sheet');for(const [k,v] of Object.entries({width:'190mm',maxWidth:'none',minHeight:'0',margin:'0 auto',padding:'0'}))sheet.style[k]=v;const pages=window.__paginate(sheet,document);return pages.flatMap(p=>[...p.querySelectorAll('table[data-pdf-keep-footer-with-row]')].map(t=>({rows:[...t.tBodies].reduce((n,b)=>n+b.rows.length,0),hasFooter:!!t.tFoot})));});
 assert.ok(long.length>1);assert.equal(long.reduce((n,t)=>n+t.rows,0),55);assert.equal(long.filter(t=>t.hasFooter).length,1);assert.ok(long.find(t=>t.hasFooter).rows>0);
 console.log('PASS',result.pages,'pages with every invoice and subtotal together; long invoice retains all 55 lines');
}finally{await browser.close();}
