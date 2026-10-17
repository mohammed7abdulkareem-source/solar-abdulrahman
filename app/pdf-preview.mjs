import {createPdfDocument,downloadPdf} from './pdf-share.mjs';
import {previewMarkup} from './premium-pdf.mjs';

const pendingDownloads=new Set();
export async function savePdf(html,name='مستند'){
 const key=name+'\n'+html;if(pendingDownloads.has(key))return;
 pendingDownloads.add(key);
 const notice=document.createElement('div');notice.setAttribute('role','status');notice.textContent='جاري تجهيز ملف PDF…';
 notice.style.cssText='position:fixed;bottom:24px;left:50%;transform:translateX(-50%);z-index:10000;background:#174d67;color:white;padding:12px 22px;border-radius:8px;font:14px Tahoma,Arial,sans-serif;box-shadow:0 4px 20px #0003;';document.body.appendChild(notice);
 try{await downloadPdf(name,html)}catch(error){console.error('PDF download',error);alert('تعذر تجهيز ملف PDF. حاول مرة أخرى.')}finally{pendingDownloads.delete(key);notice.remove()}
}

// Both the preview images and the downloaded PDF use the same rendered pages.
export async function previewPdf(html,name,prepared){
 const popup=window.open('','_blank');if(!popup){alert('اسمح بالنوافذ المنبثقة لفتح المعاينة');return;}
 const urls=[];const cleanup=()=>{for(const url of urls)URL.revokeObjectURL(url);urls.length=0};
 popup.document.write(previewMarkup(window.location.origin));
 popup.document.close();popup.addEventListener('pagehide',cleanup,{once:true});
 const doc=popup.document,title=name||new DOMParser().parseFromString(html,'text/html').title||'مستند';
 doc.title=title+' — معاينة PDF';doc.getElementById('pdfTitle').textContent=title;
 doc.getElementById('pdfClose').onclick=()=>popup.close();
 doc.getElementById('pdfZoom').onchange=e=>{const host=doc.querySelector('.pdfPages'),scale=Number(e.target.value),base=Math.min(794,host.clientWidth-48);for(const page of host.querySelectorAll('.pdfPage')){page.style.width=base*scale+'px';page.style.maxWidth=scale>1?'none':'100%';}};
 try{
  const result=prepared||await createPdfDocument(html);if(popup.closed)return;
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
