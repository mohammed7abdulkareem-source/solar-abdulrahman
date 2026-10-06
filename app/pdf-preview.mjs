import {createPdfDocument,downloadPdf} from './pdf-share.mjs';

const pendingDownloads=new Set();
export async function savePdf(html,name='مستند'){
 const key=name+'\n'+html;if(pendingDownloads.has(key))return;
 pendingDownloads.add(key);
 const notice=document.createElement('div');notice.setAttribute('role','status');notice.textContent='جاري تجهيز ملف PDF…';
 notice.style.cssText='position:fixed;bottom:24px;left:50%;transform:translateX(-50%);z-index:10000;background:#174d67;color:white;padding:12px 22px;border-radius:8px;font:14px Tahoma,Arial,sans-serif;box-shadow:0 4px 20px #0003;';document.body.appendChild(notice);
 try{await downloadPdf(name,html)}catch(error){console.error('PDF download',error);alert('تعذر تجهيز ملف PDF. حاول مرة أخرى.')}finally{pendingDownloads.delete(key);notice.remove()}
}

// Both the preview images and the downloaded PDF use the same rendered pages.
export async function previewPdf(html,name){
 const popup=window.open('','_blank');if(!popup){alert('اسمح بالنوافذ المنبثقة لفتح المعاينة');return;}
 const urls=[];const cleanup=()=>{for(const url of urls)URL.revokeObjectURL(url);urls.length=0};
 popup.document.write(`<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>معاينة PDF</title><style>*{box-sizing:border-box}body{margin:0;background:#e6ebf1;color:#19394f;font-family:Tahoma,Arial,sans-serif}.pdfToolbar{position:sticky;top:0;z-index:10;display:flex;align-items:center;gap:8px;flex-wrap:wrap;background:#fff;padding:10px 16px;border-bottom:1px solid #c8d6e1;box-shadow:0 2px 8px #17364b12}.pdfToolbar button{font:700 13px Tahoma,Arial,sans-serif;min-height:38px;padding:8px 16px;border:1px solid #c1d3df;border-radius:6px;background:#fff;color:#174d67;cursor:pointer}.pdfToolbar button:disabled{opacity:.5;cursor:wait}.pdfToolbar #pdfDownload{background:#0878cc;color:white;border-color:#0878cc}.pdfToolbar h1{font-size:15px;margin:0 0 0 auto}.pdfToolbar span{font-size:12px}#pdfNotice{margin:12px;padding:12px;border:1px solid #bbd7df;border-radius:6px;background:#fff;font-size:13px;line-height:1.7}.pdfStatus{text-align:center;padding:24px;line-height:1.8}.pdfPages{padding:20px 12px}.pdfPage{width:794px;max-width:100%;margin:0 auto 20px}.pdfPage img{display:block;width:100%;height:auto;box-shadow:0 3px 15px #19394f26;background:#fff}.pdfPage figcaption{font-size:12px;text-align:center;padding:8px;color:#476277}@media(max-width:600px){.pdfToolbar{padding:8px;gap:6px}.pdfToolbar h1{width:100%;margin:0;font-size:14px}.pdfToolbar button{padding:8px 10px;font-size:12px}.pdfPages{padding:10px 6px}.pdfPage{margin-bottom:12px}}@page{size:A4 portrait;margin:0}@media print{body{background:white}.pdfToolbar,.pdfStatus,#pdfNotice,.pdfPage figcaption{display:none}.pdfPages{padding:0}.pdfPage{margin:0;width:210mm;max-width:none;height:297mm;break-after:page;page-break-after:always}.pdfPage:last-child{break-after:auto;page-break-after:auto}.pdfPage img{width:210mm;height:297mm;box-shadow:none}}</style></head><body><nav class="pdfToolbar"><h1 id="pdfTitle">معاينة PDF</h1><span id="pdfCount"></span><button id="pdfDownload" disabled>حفظ PDF</button><button id="pdfShare" disabled>مشاركة</button><button id="pdfPrint" disabled>طباعة</button><button id="pdfClose">رجوع للتطبيق</button></nav><p id="pdfNotice" role="status" hidden></p><div class="pdfStatus" role="status">جاري تجهيز صفحات PDF…</div><main class="pdfPages" aria-label="صفحات PDF"></main></body></html>`);
 popup.document.close();popup.addEventListener('pagehide',cleanup,{once:true});
 const doc=popup.document,title=name||new DOMParser().parseFromString(html,'text/html').title||'مستند';
 doc.title=title+' — معاينة PDF';doc.getElementById('pdfTitle').textContent=title;
 doc.getElementById('pdfClose').onclick=()=>popup.close();
 try{
  const result=await createPdfDocument(html);if(popup.closed)return;
  const fileUrl=URL.createObjectURL(result.blob);urls.push(fileUrl);
  const filename=String(title).replace(/[\\/:*?"<>|\r\n]+/g,'-').slice(0,90).replace(/\.pdf$/i,'')+'.pdf';
  const images=[];
  result.pages.forEach((page,index)=>{
   const url=URL.createObjectURL(new Blob([page.bytes],{type:'image/jpeg'}));urls.push(url);
   const figure=doc.createElement('figure');figure.className='pdfPage';const img=doc.createElement('img');img.src=url;img.width=page.width;img.height=page.height;img.alt='صفحة '+(index+1)+' من '+result.pages.length;images.push(img);
   const caption=doc.createElement('figcaption');caption.textContent=img.alt;figure.append(img,caption);doc.querySelector('.pdfPages').appendChild(figure);
  });
  await Promise.all(images.map(img=>img.decode()));if(popup.closed){cleanup();return;}
  doc.querySelector('.pdfStatus').remove();doc.getElementById('pdfCount').textContent=result.pages.length+' صفحة';
  const download=doc.getElementById('pdfDownload');download.disabled=false;download.onclick=()=>{const link=doc.createElement('a');link.href=fileUrl;link.download=filename;doc.body.appendChild(link);link.click();link.remove()};
  const share=doc.getElementById('pdfShare');share.disabled=false;
  const file=new popup.File([result.blob],filename,{type:'application/pdf'});
  share.onclick=async()=>{
   if(share.disabled)return;
   const notice=doc.getElementById('pdfNotice');notice.hidden=true;share.disabled=true;
   try{
    if(popup.navigator.share&&popup.navigator.canShare?.({files:[file]})){
     await popup.navigator.share({title,files:[file]});
    }else{
     download.onclick();notice.textContent='تم تنزيل ملف PDF. يمكنك مشاركته من الملفات أو التنزيلات.';notice.hidden=false;
    }
   }catch(error){
    if(error?.name!=='AbortError'){notice.textContent='تعذرت المشاركة. حاول مرة أخرى أو احفظ PDF وشاركه من الملفات.';notice.hidden=false;}
   }finally{share.disabled=false;}
  };
  const print=doc.getElementById('pdfPrint');print.disabled=false;print.onclick=()=>{popup.focus();popup.print()};
 }catch(error){cleanup();console.error('PDF preview',error);if(!popup.closed){doc.querySelector('.pdfStatus').textContent='تعذر تجهيز المعاينة. ارجع للتطبيق وحاول مرة أخرى.';doc.querySelector('.pdfPages').replaceChildren();}}
}
