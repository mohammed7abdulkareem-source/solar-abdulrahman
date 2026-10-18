import QRCode from 'qrcode/lib/core/qrcode.js';
export const blankWarranty=()=>({enabled:false,items:[],maintenance:{duration:'',unit:'months'},notes:''});
export function warrantyPolicy(value,items){const w=value||blankWarranty();return {...w,enabled:!!w.enabled,items:items.map(i=>({id:i.id,...(w.items||[]).find(r=>String(r.id)===String(i.id)),duration:(w.items||[]).find(r=>String(r.id)===String(i.id))?.duration??'',unit:(w.items||[]).find(r=>String(r.id)===String(i.id))?.unit||'months'})),maintenance:w.maintenance||{duration:'',unit:'months'}};}
export function warrantyError(value,items){
 const w=warrantyPolicy(value,items);if(!w.enabled)return '';
 const terms=[...w.items,w.maintenance];if(terms.some(t=>!['days','months','years'].includes(t.unit)||!Number.isInteger(Number(t.duration||0))||Number(t.duration||0)<0||Number(t.duration||0)>({days:36500,months:1200,years:100})[t.unit]))return 'أدخل مدة ضمان صحيحة بالأيام أو الأشهر أو السنوات.';
 if(!terms.some(t=>Number(t.duration)>0))return 'حدد مدة ضمان لمادة واحدة على الأقل أو للصيانة.';
 return '';
}
export const warrantyUrl=token=>'https://solar-abdulrahman.vercel.app/warranty/'+encodeURIComponent(token);
export function warrantyQrSvg(token){
 if(!/^[a-f\d-]{36}$/i.test(token||''))return '';
 const matrix=QRCode.create(warrantyUrl(token),{errorCorrectionLevel:'M'}).modules,n=matrix.size,pad=4,parts=[];
 for(let y=0;y<n;y++)for(let x=0;x<n;x++)if(matrix.get(y,x))parts.push('M'+(x+pad)+','+(y+pad)+'h1v1h-1z');
 return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 '+(n+pad*2)+' '+(n+pad*2)+'" width="116" height="116" shape-rendering="crispEdges"><rect width="100%" height="100%" fill="#fff"/><path fill="#000" d="'+parts.join('')+'"/></svg>';
}
export const termLabel=t=>Number(t?.duration)>0?t.duration+' '+({days:'يوم',months:'شهر',years:'سنة'})[t.unit]:'بدون ضمان';
const escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function warrantyDocument(row){
 const w=row.warranty||{enabled:false},token=row.warrantyToken||row.warranty_token;
 if(!w.enabled)return '<p style="font-size:11px;color:#657886">هذه الفاتورة بدون ضمان محدد.</p>';
 return '<div style="display:flex;align-items:center;gap:16px;border:1px solid #d9e8e3;padding:10px;margin:0 0 12px;break-inside:avoid">'+(!row.draft&&token?warrantyQrSvg(token):'')+'<div><b>ضمان المواد والصيانة</b><p style="font-size:11px;margin:5px 0">'+(row.draft?'مسودة ضمان — يصدر رمز التحقق بعد حفظ الوصل.':'امسح رمز QR للتحقق من الضمان والمدة المتبقية.')+'</p><p style="font-size:11px;margin:5px 0">يبدأ الضمان من تاريخ الوصل. ضمان الصيانة: '+escape(termLabel(w.maintenance))+'</p>'+((w.items||[]).map(term=>{const item=(row.items||[]).find(i=>String(i.product_id??i.id)===String(term.id));return item?'<div style="font-size:11px">'+escape(item.product_name||item.name)+' — '+escape(termLabel(term))+'</div>':'';}).join(''))+(w.notes?'<p style="font-size:11px">'+escape(w.notes)+'</p>':'')+'</div></div>';
}
