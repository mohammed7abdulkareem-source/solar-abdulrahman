const same=(a,b)=>String(a)===String(b);
export function warehouseHeld(items,productId){return items.filter(i=>same(i.productId,productId)).reduce((n,i)=>n+Number(i.qty||0),0);}
export function warehouseCapacity(products,booked,productId){return Number(products.find(p=>same(p.id,productId))?.qty||0)+warehouseHeld(booked,productId);}
export function warehouseEditError(lines,products,booked){
 if(!lines.length||lines.length>300)return 'اختر من فقرة واحدة إلى 300 فقرة.';
 for(const i of lines){const n=Number(i.qty);if(!Number.isFinite(n)||n<=0||n>1000000||Math.abs(n*1000-Math.round(n*1000))>.000001)return 'اكتب كمية صحيحة للمادة: '+i.name;}
 for(const id of new Set(lines.map(i=>String(i.productId))))if(warehouseHeld(lines,id)>warehouseCapacity(products,booked,id))return 'الكمية المطلوبة أكبر من المتاح للمادة: '+lines.find(i=>same(i.productId,id)).name;
 return '';
}
export function warehouseEditPayload(lines){return lines.map(i=>({lineId:i.lineId??null,productId:Number(i.productId),qty:Number(i.qty)}));}
