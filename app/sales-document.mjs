import {receiptNumber} from './supplier-utils.mjs';
export const formatMoney=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2});
export const statusLabel={pending:'بانتظار التنصيب',in_progress:'جاري التنصيب',completed:'بانتظار الغلق',closed:'ملف مغلق'};
const escape=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function salesDocument(row,customer=true){
 const system=row.kind==='system',money=formatMoney;
 const meta=[['رقم الفاتورة',receiptNumber(row)],['الزبون',row.party_name||'نقدي'],['التاريخ',new Date(row.created_at).toLocaleDateString('ar-IQ',{timeZone:'Asia/Baghdad'})],['المسؤول',row.creatorName||'—']];
 if(system)meta.push(['المهندس',row.installerName||'غير محدد'],['الحالة',statusLabel[row.installation_status]||'غير محدد'],['الهاتف',row.customer_phone||'—'],['العنوان',row.customer_address||'—'],['الموعد',[row.install_date,row.install_time?.slice(0,5)].filter(Boolean).join(' • ')||'يحدد لاحقاً']);
 const prices=customer&&!system;
 const rows=(row.items||[]).map((i,index)=>'<tr><td>'+String(index+1)+'</td><td>'+escape(i.product_name)+'<br><small>'+escape([i.brand_name,i.category].filter(Boolean).join(' • '))+'</small></td><td>'+money(i.qty)+'</td>'+(prices?'<td>'+money(i.price)+'</td><td>'+money(Number(i.qty)*Number(i.price))+'</td>':'')+'</tr>').join('');
 const body='<div class="meta">'+meta.map(([k,v])=>'<div><b>'+k+':</b> '+escape(v)+'</div>').join('')+'</div><table data-pdf-paginate><colgroup><col style="width:7%"><col style="width:'+(prices?'43':'75')+'%"></colgroup><thead><tr><th>ت</th><th>المادة / البراند / الصنف</th><th>العدد</th>'+(prices?'<th>سعر الوحدة د.ع</th><th>المجموع د.ع</th>':'')+'</tr></thead><tbody>'+rows+'</tbody></table><div class="documentCounts"><span>عدد الفقرات: '+(row.items||[]).length+'</span><span>مجموع الكميات: '+money((row.items||[]).reduce((sum,i)=>sum+Number(i.qty||0),0))+'</span></div>'+
 (customer&&!system&&Number(row.expenses)>0?'<div class="notes">المصاريف الإضافية: '+money(row.expenses)+' د.ع</div>':'')+
 (customer&&row.notes?'<div class="notes"><b>ملاحظات:</b> '+escape(row.notes)+'</div>':'');
 return {title:customer?(system?'فاتورة بيع منظومة':'فاتورة بيع جملة'):'وصل مخزني — بدون أسعار',body,total:customer?money(row.total)+' د.ع':'',subtitle:customer?'نسخة الزبون':'نسخة المخزن'};
}
