import {formatMoney} from './money-format.mjs';
import {filterMovementProducts,materialQuantity as qty,sumMaterialQuantities} from './material-movement-utils.mjs';
import {escapeHtml as e} from './warehouse-utils.mjs';

const hasStock=p=>Number(p.qty||0)!==0||Number(p.reservedQty||0)!==0;
const byAvailability=(a,b)=>Number(Number(b.qty)>0)-Number(Number(a.qty)>0);
export const stockMoney=(amount)=>amount==null?'غير محدد':formatMoney(amount)+' د.ع';
export const stockValue=row=>row.cost==null?null:Number(row.bookQty??row.qty)*Number(row.cost??0);

export function inventoryBalanceView({products,warehouses,warehouseBalances,warehouseId,byWarehouse,query,hideZero}){
 const matching=filterMovementProducts(products,query),visible=items=>items.filter(p=>!hideZero||hasStock(p)).sort(byAvailability);
 const rows=visible(matching);
 const totals={
  products:rows.length,
  available:sumMaterialQuantities(rows.map(p=>p.qty)),
  reserved:sumMaterialQuantities(rows.map(p=>p.reservedQty??0)),
  value:rows.reduce((sum,p)=>sum+stockValue(p),0)
 };
 if(!byWarehouse)return {rows,groups:[],totals};
 const balances=new Map();
 for(const balance of warehouseBalances){
  const id=String(balance.warehouseId);
  if(!balances.has(id))balances.set(id,new Map());
  balances.get(id).set(String(balance.productId),balance);
 }
 const groups=warehouses.filter(w=>!warehouseId||String(w.id)===String(warehouseId)).map(w=>{
  const stock=balances.get(String(w.id));
  const rows=[];
  for(const p of matching){
   const balance=stock?.get(String(p.id));
   if(hideZero&&(!balance||!hasStock(balance)))continue;
   rows.push({...p,qty:balance?.qty??0,reservedQty:balance?.reservedQty??0,bookQty:balance?.bookQty??0});
  }
  rows.sort(byAvailability);
  return {id:w.id,name:w.name,active:w.active,rows,available:sumMaterialQuantities(rows.map(p=>p.qty))};
 });
 totals.products=new Set(groups.flatMap(w=>w.rows.map(p=>p.id))).size;
 return {rows,groups,totals};
}

export function inventoryBalanceDocument(view,{warehouseName,byWarehouse,priced,hideZero,query,personalPrices=false}){
 const {rows,groups,totals}=view;
 const title=(byWarehouse?'أرصدة المواد حسب المخزن':'مجموع أرصدة المواد')+' · '+e(warehouseName);
 const showReserved=totals.reserved!==0;
 const headers='<th>الكود</th><th>المادة / البراند</th><th>المتاح</th>'+(showReserved?'<th>محجوز للنقل</th>':'')+(priced?'<th>'+(personalPrices?'سعر الجملة':'كلفة الوحدة')+' د.ع</th><th>القيمة مع المحجوز د.ع</th>':'');
 const colCount=3+Number(showReserved)+(priced?2:0);
 function table(items,groupName){
  const heading=groupName?'<tr><th class="inventoryGroupHead" colspan="'+colCount+'">'+e(groupName)+'</th></tr>':'';
  const body=items.map(p=>'<tr><td>'+e(p.code)+'</td><td>'+e(p.name)+'<br><small>'+e([p.brand,p.category].filter(Boolean).join(' · '))+'</small></td><td><bdi>'+qty(p.qty)+'</bdi></td>'+
   (showReserved?'<td><bdi>'+qty(p.reservedQty??0)+'</bdi></td>':'')+
   (priced?'<td><bdi>'+(p.cost==null?'غير محدد':formatMoney(p.cost))+'</bdi></td><td><bdi>'+(p.cost==null?'—':formatMoney(stockValue(p)))+'</bdi></td>':'')+'</tr>').join('');
  return '<table data-pdf-paginate><thead>'+heading+'<tr>'+headers+'</tr></thead><tbody>'+(body||'<tr><td colspan="'+colCount+'">لا توجد مواد ضمن الاختيارات.</td></tr>')+'</tbody></table>';
 }
 const scope='<div class="meta"><div>المخازن: '+e(warehouseName)+'</div><div>عرض الأرصدة: '+(byWarehouse?'حسب المخزن':'المجموع')+'</div><div>التصفية: '+(hideZero?'إخفاء الأرصدة الصفرية':'جميع الأرصدة')+(query?' · '+e(query):'')+'</div><div>'+(priced?(personalPrices?'القيمة بحسب أسعار الجملة المحددة فقط · دينار عراقي':'الكلفة الحالية · دينار عراقي'):'كشف كميات بدون أسعار')+'</div></div>';
 const summary='<div class="documentCounts"><span>عدد المواد: '+qty(totals.products)+'</span><span>الكمية المتاحة: '+qty(totals.available)+'</span><span>المحجوز للنقل: '+qty(totals.reserved)+'</span></div>';
 const tables=byWarehouse?(groups.map(w=>table(w.rows,w.name)).join('')||'<p>لا توجد مخازن مسموحة لعرض أرصدتها.</p>'):table(rows);
 return {title,body:scope+summary+tables,total:priced?formatMoney(totals.value)+' د.ع':'',subtitle:qty(totals.available)+' كمية متاحة · '+qty(totals.products)+' مادة'};
}
