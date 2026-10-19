import {salesDocument} from './sales-document.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
export const quantity=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:3});
export const escapeHtml=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const movementLabel={purchase:'شراء / دخول',sale:'جملة / خروج',system:'منظومة / خروج',stock_adjustment:'تسوية رصيد',transfer_in:'نقل وارد',transfer_out:'نقل صادر',transfer_return_in:'إلغاء نقل / دخول',transfer_return_out:'إلغاء نقل / خروج'};
export const warehouseDate=s=>new Date(s).toLocaleDateString('ar-IQ',{timeZone:'Asia/Baghdad'});
export function filteredStock(rows,query='',brand='',category='',available=false){const q=normalizeSearch(query);return rows.filter(p=>(!available||Number(p.qty)>0)&&(!brand||p.brand===brand)&&(!category||p.category===category)&&normalizeSearch([p.name,p.code,p.brand,p.category].join(' ')).includes(q));}
export function quantityDocument(rows){return '<table><thead><tr><th>الكود</th><th>المادة / البراند / الصنف</th><th>الرصيد</th></tr></thead><tbody>'+rows.map(p=>'<tr><td>'+escapeHtml(p.code)+'</td><td>'+escapeHtml(p.name)+'<br><small>'+escapeHtml([p.brand,p.category].filter(Boolean).join(' • '))+'</small></td><td>'+quantity(p.qty)+'</td></tr>').join('')+'</tbody></table>';}
export function warehouseDocument(row){
 const invoice={...row,party_name:row.party,created_at:row.date,warehouse_status:row.status,customer_phone:row.phone,customer_address:row.address,items:row.items.map(i=>({...i,product_id:i.productId,product_name:i.name,brand_name:i.brand}))};
 return salesDocument(invoice,false).body;
}
export function movementDocument(rows){return '<table><thead><tr><th>التاريخ / الوصل</th><th>المادة / الطرف</th><th>داخل</th><th>خارج</th><th>الرصيد المخزني</th></tr></thead><tbody>'+rows.map(r=>'<tr><td>'+escapeHtml(warehouseDate(r.date))+'<br>#'+escapeHtml(r.receiptNo)+'</td><td>'+escapeHtml(r.name)+'<br><small>'+escapeHtml(r.warehouseName||'')+' • '+escapeHtml((r.kind==='stock_adjustment'?'':(r.party||'زبون نقدي')+' • ')+movementLabel[r.kind]+(r.note?' • '+r.note:''))+'</small></td><td>'+quantity(r.inQty)+'</td><td>'+quantity(r.outQty)+'</td><td>'+quantity(r.balance)+'</td></tr>').join('')+'</tbody></table>';}
