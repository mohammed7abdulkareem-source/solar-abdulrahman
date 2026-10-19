import QRCode from 'qrcode/lib/core/qrcode.js';
import {escapeHtml as escape,invoiceDate,warrantyLastDay} from './document-format.mjs';
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
export function warrantyDocument(row,{hasQr=false}={}){
 const w=row.warranty||{enabled:false};
 if(!w.enabled)return '<div class="warrantyNone"><b>حالة الضمان:</b> هذه الفاتورة بدون ضمان محدد للمواد أو الصيانة.</div>';
 const line=(name,term)=>'<tr><td>'+escape(name)+'</td><td>'+escape(termLabel(term))+'</td><td class="documentNumber">'+(warrantyLastDay(row.created_at,term)||'—')+'</td></tr>';
 return '<section class="invoiceWarranty"><h3>ضمان المواد والصيانة'+(row.draft?' — مسودة':'')+'</h3><p class="warrantyStart">بداية الضمان: <b dir="ltr">'+invoiceDate(row.created_at)+'</b> — من تاريخ هذه الفاتورة.</p><table data-pdf-paginate class="warrantyTable"><colgroup><col style="width:50%"><col style="width:23%"><col style="width:27%"></colgroup><thead><tr><th>المادة / الخدمة</th><th>مدة الضمان</th><th>آخر يوم مشمول</th></tr></thead><tbody>'+((row.items||[]).map(item=>line(item.product_name||item.name,(w.items||[]).find(t=>String(t.id)===String(item.product_id??item.id)))).join(''))+line('ضمان الصيانة',w.maintenance)+'</tbody></table><p class="warrantyHint">'+(row.draft?'يصدر رمز التحقق بعد حفظ الوصل.':hasQr?'امسح رمز QR أعلى الوصل لمعرفة حالة الضمان والمدة المتبقية وقت الفحص.':'الضمان يشمل المواد والخدمات التي حُددت لها مدة فقط.')+'</p>'+(w.notes?'<div class="notes warrantyNotes" data-pdf-end><b>شروط وملاحظات الضمان:</b><br>'+escape(w.notes)+'</div>':'')+'</section>';
}
