import {formatMoney} from './money-format.mjs';
import {filterMovementProducts,materialQuantity as qty,sumMaterialQuantities} from './material-movement-utils.mjs';
import {escapeHtml as e} from './warehouse-utils.mjs';

const hasStock=p=>Number(p.qty||0)!==0||Number(p.reservedQty||0)!==0;
const byAvailability=(a,b)=>Number(Number(b.qty)>0)-Number(Number(a.qty)>0);
const unitFormat=new Intl.NumberFormat('en-US',{maximumFractionDigits:6});
export const personalStockPricingNote='يُحتسب سعر المادة بالسعر اليدوي عند تفعيله، وبالكلفة الحالية حسب سعر الصرف لبقية المواد.';
export const stockPriceSource=(row,field='floorSource')=>({configured:'يدوي',cost:'حسب الكلفة'}[row[field]]||'');
export const stockMoney=amount=>amount==null?'—':formatMoney(amount)+' د.ع';
export const stockUnitPrice=(amount,personalPrices)=>amount==null?'—':personalPrices?unitFormat.format(amount):formatMoney(amount);
export const stockBookQuantity=row=>row.bookQty==null?sumMaterialQuantities([row.qty??0,row.reservedQty??0]):Number(row.bookQty);
export const stockValue=(row,field='cost')=>row[field]==null?null:stockBookQuantity(row)*Number(row[field]);
const totalValue=(rows,field)=>rows.reduce((sum,row)=>sum+(stockValue(row,field)??0),0);

export function stockPriceColumns({priced,personalPrices=false,salePrices=false}){
 const columns=[];
 if(priced)columns.push({
  key:'cost',field:'cost',total:'value',unit:personalPrices?'سعر المادة':'كلفة الوحدة',
  value:personalPrices?'القيمة بسعر المادة':'القيمة بالكلفة',source:personalPrices?'floorSource':null
 });
 if(salePrices)columns.push({key:'sale',field:'salePrice',total:'saleValue',unit:'سعر البيع',value:'القيمة بسعر البيع',source:'salePriceSource'});
 return columns;
}

export function stockWarehouseScope(warehouses,warehouseId){
 const names=warehouses.filter(w=>!warehouseId||String(w.id)===String(warehouseId)).map(w=>w.name);
 const label=names.length===1?names[0]:warehouseId?'المخزن المحدد':'جميع المخازن المسموحة';
 return {names,label};
}


export function inventoryBalanceView({products,warehouses,warehouseBalances,warehouseId,byWarehouse,query,hideZero}){
 const matching=filterMovementProducts(products,query),visible=items=>items.filter(p=>!hideZero||hasStock(p)).sort(byAvailability);
 const rows=visible(matching);
 const totals={
  products:rows.length,
  available:sumMaterialQuantities(rows.map(p=>p.qty)),
  reserved:sumMaterialQuantities(rows.map(p=>p.reservedQty??0)),
  value:totalValue(rows,'cost'),saleValue:totalValue(rows,'salePrice')
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
   rows.push({...p,qty:balance?.qty??0,reservedQty:balance?.reservedQty??0,bookQty:balance?stockBookQuantity(balance):0});
  }
  rows.sort(byAvailability);
  return {id:w.id,name:w.name,active:w.active,rows,value:totalValue(rows,'cost'),saleValue:totalValue(rows,'salePrice'),available:sumMaterialQuantities(rows.map(p=>p.qty))};
 });
 totals.products=new Set(groups.flatMap(w=>w.rows.map(p=>p.id))).size;
 return {rows,groups,totals};
}

export function inventoryBalanceDocument(view,{warehouseName,warehouseNames=[],byWarehouse,priced,hideZero,query,personalPrices=false,salePrices=false}){
 const {rows,groups,totals}=view,columns=stockPriceColumns({priced,personalPrices,salePrices});
 const title=(byWarehouse?'أرصدة المواد حسب المخزن':'مجموع أرصدة المواد')+' · '+e(warehouseName);
 const showReserved=totals.reserved!==0,combined=columns.length===2;
 const financialHeaders=columns.map(col=>combined?'<th>'+col.unit+'<br><small>'+col.value+' · د.ع</small></th>':'<th>'+col.unit+' د.ع</th><th>'+col.value+' مع المحجوز د.ع</th>').join('');
 const headers='<th>الكود</th><th>المادة / البراند</th><th>المتاح</th>'+(showReserved?'<th>محجوز للنقل</th>':'')+financialHeaders;
 const colCount=3+Number(showReserved)+columns.length*(combined?1:2);
 function financialCells(row){
  return columns.map(col=>{
   const unit='<bdi>'+stockUnitPrice(row[col.field],!!col.source||combined)+'</bdi>';
   const source=col.source?stockPriceSource(row,col.source):'';
   const note=source?'<br><small>'+source+'</small>':'';
   const amount=stockValue(row,col.field),value='<bdi>'+(amount==null?'—':formatMoney(amount))+'</bdi>';
   return combined?'<td>'+unit+note+'<br><small>'+col.value+'</small><br>'+value+'</td>':'<td>'+unit+note+'</td><td>'+value+'</td>';
  }).join('');
 }
 function table(items,group){
  const subtotals=group?columns.map(col=>' · '+col.value+' '+stockMoney(group[col.total])).join(''):'';
  const heading=group?'<tr><th class="inventoryGroupHead" colspan="'+colCount+'">'+e(group.name)+subtotals+'</th></tr>':'';
  const body=items.map(p=>'<tr><td>'+e(p.code)+'</td><td>'+e(p.name)+'<br><small>'+e([p.brand,p.category].filter(Boolean).join(' · '))+'</small></td><td><bdi>'+qty(p.qty)+'</bdi></td>'+
   (showReserved?'<td><bdi>'+qty(p.reservedQty??0)+'</bdi></td>':'')+financialCells(p)+'</tr>').join('');
  return '<table data-pdf-paginate><thead>'+heading+'<tr>'+headers+'</tr></thead><tbody>'+(body||'<tr><td colspan="'+colCount+'">لا توجد مواد ضمن الاختيارات.</td></tr>')+'</tbody></table>';
 }
 const scopeName=warehouseNames.length>1?e(warehouseName)+' ('+qty(warehouseNames.length)+') · '+warehouseNames.map(e).join('، '):e(warehouseName);
 const details=columns.length?(personalPrices||salePrices?personalStockPricingNote:'الكلفة الحالية · دينار عراقي'):'كشف كميات بدون أسعار';
 const scope='<div class="meta"><div>المخازن: '+scopeName+'</div><div>عرض الأرصدة: '+(byWarehouse?'حسب المخزن':'المجموع')+'</div><div>التصفية: '+(hideZero?'إخفاء الأرصدة الصفرية':'جميع الأرصدة')+(query?' · '+e(query):'')+'</div><div>'+details+'</div></div>';
 const values=columns.map(col=>'<span>'+col.value+' مع المحجوز: '+stockMoney(totals[col.total])+'</span>').join('');
 const summary='<div class="documentCounts"><span>عدد المواد المختلفة: '+qty(totals.products)+'</span><span>الكمية المتاحة: '+qty(totals.available)+'</span><span>المحجوز للنقل: '+qty(totals.reserved)+'</span>'+values+'</div>';
 const tables=byWarehouse?(groups.map(w=>table(w.rows,w)).join('')||'<p>لا توجد مخازن مسموحة لعرض أرصدتها.</p>'):table(rows);
 return {title,body:scope+summary+tables,total:columns.length===1?stockMoney(totals[columns[0].total]):'',subtitle:qty(totals.available)+' كمية متاحة · '+qty(totals.products)+' مادة مختلفة'};
}
