const types=new Set(['purchase_received','wholesale_prices_updated']);
const text=value=>typeof value==='string'?value:'';
const amount=value=>['number','string'].includes(typeof value)&&String(value).trim()!==''&&Number.isFinite(Number(value))&&Number(value)>=0?Number(value):null;
export const notificationQuantity=value=>Number(value).toLocaleString('en-US',{maximumFractionDigits:20});

// Only these public fields may reach the inbox. In particular, a purchase
// notification never renders its raw body or any financial fields in details.
// Legacy model is a material code, never a type; only an explicit category is shown.
export function structuredNotification(notice){
 if(!types.has(notice?.event))return null;
 const purchase=notice.event==='purchase_received',details=notice.details;
 const valid=details&&typeof details==='object'&&!Array.isArray(details)&&details.type===notice.event&&Array.isArray(details.items)&&(!purchase?details.currency==='IQD':true);
 const items=valid?details.items.map(row=>{
  const item=row&&typeof row==='object'&&!Array.isArray(row)?row:{};
  const identity={name:text(item.name)||'مادة غير مسماة',category:text(item.category),brand:text(item.brand)};
  if(purchase)return {...identity,qty:amount(item.qty)};
  const price=amount(item.minPrice),enabled=typeof item.enabled==='boolean'?item.enabled:null;
  return {...identity,minPrice:enabled&&price>0?price:null,enabled,
   ...(enabled===false&&price>0?{inactiveManualPrice:price}:{})};
 }):null;
 const warehouseName=purchase&&valid?text(details.warehouseName).trim():'';
 const itemSummary=items?items.length+' '+(purchase?'فقرة في المواد المستلمة':'مادة في تحديث الأسعار'):'افتح الإشعار للاطلاع على التفاصيل';
 return {type:notice.event,purchase,title:purchase?'دخول مواد جديدة':'تحديث أسعار بيع الجملة',currency:purchase?null:'IQD',items,warehouseName,itemSummary,
  summary:warehouseName?'المخزن: '+warehouseName+' · '+itemSummary:itemSummary};
}

export function notificationPreview(notice){
 const structured=structuredNotification(notice);
 return structured?{title:structured.title,body:structured.summary}:{title:text(notice?.title),body:text(notice?.body)};
}
