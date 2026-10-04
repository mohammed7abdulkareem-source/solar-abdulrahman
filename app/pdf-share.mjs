const PDF_PAGE_WIDTH=595.28;
const PDF_PAGE_HEIGHT=841.89;
const CSS_PAGE_WIDTH=794;
const CSS_PAGE_HEIGHT=1123;
const RASTER_SCALE=1.8;
const SVG_NS='http://www.w3.org/2000/svg';
const XHTML_NS='http://www.w3.org/1999/xhtml';

export function makePdfObjects(images){
 const encoder=new TextEncoder(),chunks=[],offsets=[0];let length=0;
 const push=data=>{const bytes=typeof data==='string'?encoder.encode(data):data;chunks.push(bytes);length+=bytes.length;};
 const object=(id,body)=>{offsets[id]=length;push(id+' 0 obj\n'+body+'\nendobj\n');};
 const binaryObject=(id,header,binary,footer)=>{offsets[id]=length;push(id+' 0 obj\n'+header);push(binary);push(footer+'\nendobj\n');};
 push('%PDF-1.4\n%');push(new Uint8Array([226,227,207,211]));push('\n');
 object(1,'<< /Type /Catalog /Pages 2 0 R >>');
 object(2,'<< /Type /Pages /Kids ['+images.map((_,i)=>(3+i*3)+' 0 R').join(' ')+'] /Count '+images.length+' >>');
 images.forEach((image,i)=>{
  const page=3+i*3,content=page+1,bitmap=page+2;
  object(page,'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 '+PDF_PAGE_WIDTH+' '+PDF_PAGE_HEIGHT+'] /Resources << /XObject << /Im0 '+bitmap+' 0 R >> >> /Contents '+content+' 0 R >>');
  const stream='q\n'+PDF_PAGE_WIDTH+' 0 0 '+PDF_PAGE_HEIGHT+' 0 0 cm\n/Im0 Do\nQ\n';
  object(content,'<< /Length '+encoder.encode(stream).length+' >>\nstream\n'+stream+'endstream');
  binaryObject(bitmap,'<< /Type /XObject /Subtype /Image /Width '+image.width+' /Height '+image.height+' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length '+image.bytes.length+' >>\nstream\n',image.bytes,'\nendstream');
 });
 const xref=length;push('xref\n0 '+offsets.length+'\n0000000000 65535 f \n');
 for(let i=1;i<offsets.length;i++)push(String(offsets[i]).padStart(10,'0')+' 00000 n \n');
 push('trailer\n<< /Size '+offsets.length+' /Root 1 0 R >>\nstartxref\n'+xref+'\n%%EOF');
 return new Blob(chunks,{type:'application/pdf'});
}

function renderPage(doc,body,styles,top,height,width){
 const svg=doc.implementation.createDocument(SVG_NS,'svg',null),root=svg.documentElement;
 root.setAttribute('width',String(width));root.setAttribute('height',String(height));root.setAttribute('viewBox','0 0 '+width+' '+height);
 const background=svg.createElementNS(SVG_NS,'rect');background.setAttribute('width','100%');background.setAttribute('height','100%');background.setAttribute('fill','#fff');root.appendChild(background);
 const foreign=svg.createElementNS(SVG_NS,'foreignObject');foreign.setAttribute('width',String(width));foreign.setAttribute('height',String(height));root.appendChild(foreign);
 const container=svg.createElementNS(XHTML_NS,'div');container.setAttribute('xmlns',XHTML_NS);container.setAttribute('style','width:'+width+'px;height:'+body.height+'px;overflow:visible;transform:translateY(-'+top+'px);transform-origin:top left;background:#fff;color:#17364b;font-family:Tahoma,Arial,sans-serif;');foreign.appendChild(container);
 for(const css of styles){const style=svg.createElementNS(XHTML_NS,'style');style.textContent=css.textContent||'';container.appendChild(style);}
 const cloned=svg.importNode(body,true);cloned.setAttribute('xmlns',XHTML_NS);cloned.style.width=width+'px';cloned.style.minHeight='0';container.appendChild(cloned);
 return new Blob([new XMLSerializer().serializeToString(svg)],{type:'image/svg+xml;charset=utf-8'});
}

async function jpegPage(doc,body,styles,top,height){
 const markup=renderPage(doc,body,styles,top,height,CSS_PAGE_WIDTH),url=URL.createObjectURL(markup);
 try{
  const image=new Image();image.src=url;await image.decode();
  const canvas=document.createElement('canvas');canvas.width=Math.round(CSS_PAGE_WIDTH*RASTER_SCALE);canvas.height=Math.round(height*RASTER_SCALE);
  const context=canvas.getContext('2d',{alpha:false});if(!context)throw new Error('تعذر تجهيز صورة صفحة PDF');
  context.fillStyle='#fff';context.fillRect(0,0,canvas.width,canvas.height);context.drawImage(image,0,0,canvas.width,canvas.height);
  const jpg=await new Promise((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(new Error('تعذر تحويل الصفحة إلى PDF')),'image/jpeg',0.9));
  return {width:canvas.width,height:canvas.height,bytes:new Uint8Array(await jpg.arrayBuffer())};
 }finally{URL.revokeObjectURL(url);}
}

function pdfFilename(name){const safe=String(name||'مستند').replace(/[\\/:*?"<>|\r\n]+/g,'-').slice(0,90)||'مستند';return (safe.toLowerCase().endsWith('.pdf')?safe:safe+'.pdf');}

export async function createPdf(html){
 if(typeof document==='undefined')throw new Error('إنشاء PDF متاح من داخل البرنامج');
 const frame=document.createElement('iframe');frame.setAttribute('aria-hidden','true');frame.title='تجهيز ملف PDF';
 Object.assign(frame.style,{position:'fixed',left:'-10000px',top:'0',width:CSS_PAGE_WIDTH+'px',height:CSS_PAGE_HEIGHT+'px',border:'0',visibility:'hidden'});
 document.body.appendChild(frame);
 try{
  await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('استغرق تجهيز الصفحة وقتاً طويلاً')),20000);frame.onload=()=>{clearTimeout(timer);resolve();};frame.srcdoc=html;});
  const doc=frame.contentDocument;if(!doc)throw new Error('تعذر قراءة صفحة الوصل');
  await doc.fonts?.ready;
  doc.querySelector('.previewNav')?.remove();doc.querySelector('.actions')?.remove();
  const sheet=doc.querySelector('.sheet')||doc.body;
  sheet.style.setProperty('width','190mm','important');sheet.style.setProperty('max-width','none','important');sheet.style.setProperty('min-height','0','important');sheet.style.setProperty('margin','0 auto','important');sheet.style.setProperty('padding','0','important');
  doc.documentElement.style.cssText+=';width:794px!important;min-height:0!important;overflow:visible!important;background:#fff!important';
  doc.body.style.cssText+=';width:794px!important;min-height:0!important;margin:0!important;padding:0!important;overflow:visible!important;background:#fff!important';
  const styles=[...doc.head.querySelectorAll('style')];
  const height=Math.ceil(Math.max(sheet.scrollHeight,sheet.getBoundingClientRect().height));if(!height)throw new Error('المستند فارغ');
  const body=sheet.cloneNode(true);body.height=height;
  const images=[];
  for(let top=0;top<height;top+=CSS_PAGE_HEIGHT){const pageHeight=Math.min(CSS_PAGE_HEIGHT,height-top);images.push(await jpegPage(doc,body,styles,top,pageHeight));}
  return makePdfObjects(images);
 }finally{frame.remove();}
}

export async function sharePdf(title,html){
 const filename=pdfFilename(title),blob=await createPdf(html),file=new File([blob],filename,{type:'application/pdf'});
 if(typeof navigator!=='undefined'&&navigator.share&&navigator.canShare?.({files:[file]})){
  try{await navigator.share({title,files:[file]});return 'shared';}
  catch(error){if(error?.name==='AbortError')return 'cancelled';}
 }
 const url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download=filename;link.style.display='none';document.body.appendChild(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);
 return 'downloaded';
}
