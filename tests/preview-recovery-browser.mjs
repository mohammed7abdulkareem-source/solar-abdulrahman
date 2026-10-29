import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {a4} from '../app/document-template.mjs';
const {chromium}=await import(process.env.SOLAR_PLAYWRIGHT_MODULE||'playwright-core');
const dir='/workspace/solar-review/v386/preview';await mkdir(dir,{recursive:true});
const server=createServer(async(req,res)=>{try{
 if(req.url==='/fail/pdf-share.mjs'){res.setHeader('Content-Type','application/javascript');res.end("export async function createPdfDocument(){throw new Error('simulated raster failure')} export function downloadPdf(){}");return;}
 const path=req.url.split('?')[0];
 if(path.endsWith('.mjs')){res.setHeader('Content-Type','application/javascript');res.end(await readFile(new URL('../app/'+path.split('/').at(-1),import.meta.url)));return;}
 if(path.startsWith('/fonts/')){res.setHeader('Content-Type','font/woff');res.end(await readFile(new URL('../public'+path,import.meta.url)));return;}
 res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><html><body><button id="open">معاينة المستند</button></body></html>');
 }catch{res.statusCode=404;res.end('missing');}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({executablePath:'/usr/bin/chromium',headless:true,args:['--no-sandbox']}),errors=[],results=[];
const html=a4('وصل اختبار الطباعة','<h2>المخزن الرئيسي</h2><table><thead><tr><th>المادة</th><th>العدد</th></tr></thead><tbody><tr><td>بطارية المعاينة</td><td>2</td></tr></tbody></table>','500,000 د.ع');
try{
 for(const scenario of ['popup','blocked','render-failure']){
  const context=await browser.newContext({viewport:{width:390,height:844},isMobile:true,hasTouch:true}),page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));await page.goto(base);
  await page.evaluate(async({html,scenario})=>{const module=await import((scenario==='render-failure'?'/fail':'')+'/pdf-preview.mjs');if(scenario!=='popup')window.open=()=>null;document.querySelector('#open').onclick=()=>module.previewPdf(html,'وصل الطباعة');},{html,scenario});
  const popupWait=scenario==='popup'?page.waitForEvent('popup',{timeout:10000}).catch(e=>({failed:e.message})):null;await page.getByRole('button',{name:'معاينة المستند',exact:true}).click({noWaitAfter:true,timeout:5000});
  let view;
  if(popupWait){view=await popupWait;if(view.failed){console.log(await page.evaluate(()=>({body:document.body.innerText,open:typeof window.open,errors:window.__errors})));throw new Error(view.failed)}}else{await page.getByRole('dialog',{name:'معاينة المستند',exact:true}).waitFor();view=await(await page.locator('iframe[title="معاينة المستند والطباعة"]').elementHandle()).contentFrame();assert.equal(await page.locator('#open').evaluate(x=>x.inert||x.parentElement.inert),true);}
  await view.locator('#pdfPrint:not([disabled])').waitFor();
  if(scenario==='render-failure'){
   const native=await(await view.locator('iframe.nativeDocumentPreview').elementHandle()).contentFrame();await native.getByText('بطارية المعاينة',{exact:true}).waitFor();assert.ok((await view.locator('#pdfNotice').innerText()).includes('طباعته مباشرة'));await native.evaluate(()=>window.print=()=>{window.__printed=true});await view.locator('#pdfPrint').click();assert.equal(await native.evaluate(()=>window.__printed),true);await view.locator('#pdfRetry').waitFor();
  }else{
   assert.ok(await view.locator('.pdfPage img').count()>0);await view.evaluate(()=>window.print=()=>{window.__printed=true});await view.locator('#pdfPrint').click();assert.equal(await view.evaluate(()=>window.__printed),true);
  }
  await (scenario==='popup'?view:page).screenshot({path:dir+'/'+scenario+'.png'});await view.locator('#pdfClose').click();
  if(scenario!=='popup'){assert.equal(await page.locator('.inlineDocumentPreview').count(),0);assert.equal(await page.locator('#open').evaluate(x=>x.inert),false);assert.equal(await page.evaluate(()=>document.body.style.overflow),'');}
  results.push({scenario,preview:true,printInvoked:true,closeRestoresApp:true});await context.close();
 }
 assert.deepEqual(errors,[]);await writeFile(dir+'/results.json',JSON.stringify({pass:true,results,errors},null,2));console.log('PASS normal popup, blocked-popup inline preview, native print after PDF rendering failure, and close/focus/inert cleanup');
}catch(error){await writeFile(dir+'/failure.json',JSON.stringify({message:error.message,errors},null,2));throw error;}finally{await browser.close();server.close();}
