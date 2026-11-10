import {belowSystemMinimum} from './system-pricing-utils.mjs';

export function wholesalePricingReady(state){
 return !!state&&typeof state.enabled==='boolean'&&typeof state.canOverride==='boolean'&&state.currency==='IQD'&&state.revision!=null&&state.revision!==''&&Number.isSafeInteger(Number(state.revision))&&Number(state.revision)>=0&&Array.isArray(state.products);
}

function lineSignature(items){
 return JSON.stringify((items||[]).map(item=>[String(item.productId??item.product_id??item.id),Number(item.qty),Number(item.price)]).sort((a,b)=>a[0].localeCompare(b[0])||a[1]-b[1]||a[2]-b[2]));
}

// Preserve the agreed prices when only notes, party, payment mode or fees are
// edited. New quantities, changed prices and added/removed materials use the
// current policy; fees cannot compensate for an underpriced material.
export function wholesaleEconomicsChanged(items,originalItems){
 return !Array.isArray(originalItems)||lineSignature(items)!==lineSignature(originalItems);
}

export function wholesaleLinePricing(state,productId,{historical=false}={}){
 const product=state?.products?.find(row=>String(row.id)===String(productId));
 const raw=product?.minPrice,minimum=raw==null||raw===''?null:Number(raw);
 const price=Number.isFinite(minimum)&&minimum>=0?minimum:null;
 return {
  price,
  marked:product?.enabled===true,
  required:state?.enabled===true&&product?.enabled===true&&state?.canOverride===false&&!historical,
  historical,
  reason:state?.enabled!==true?'disabled':product?.enabled!==true?'unmarked':state?.canOverride===true?'override':historical?'historical':'required',
 };
}

export function wholesalePriceDefault(state,productId){
 const rule=wholesaleLinePricing(state,productId);
 return rule.required&&rule.price!==null?String(rule.price):'';
}

export function wholesalePricingIssues(state,items,originalItems){
 if(!wholesalePricingReady(state))return [{message:'انتظر تأكيد أسعار بيع الجملة أو حدّث الأسعار قبل الحفظ.'}];
 const historical=!wholesaleEconomicsChanged(items,originalItems);
 return items.flatMap(item=>{
  const rule=wholesaleLinePricing(state,item.id??item.productId??item.product_id,{historical});
  if(!rule.required)return [];
  if(rule.price===null)return [{id:item.id,name:item.name,minimum:null,message:'السعر المقرر للمادة «'+(item.name||'المحددة')+'» غير متاح. حدّث الأسعار قبل الحفظ.'}];
  if(item.price===''||item.price==null)return [];
  return belowSystemMinimum(item.price,rule.price)?[{id:item.id,name:item.name,minimum:rule.price}]:[];
 });
}
