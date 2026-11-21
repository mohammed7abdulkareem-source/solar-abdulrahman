import {belowSystemMinimum} from './system-pricing-utils.mjs';

export function wholesalePricingReady(state){
 if(!state||typeof state.enabled!=='boolean'||typeof state.canOverride!=='boolean'||state.currency!=='IQD'||state.revision==null||state.revision===''||!Number.isSafeInteger(Number(state.revision))||Number(state.revision)<0||!Array.isArray(state.products))return false;
 // A pre-scope response keeps the original all-user policy. A partial new
 // response must never silently exempt an account from the server's policy.
 const scoped=['scopeMode','scopeConfigured','appliesToCurrentUser','appliesToSubject','effectiveEnforced'].some(key=>Object.hasOwn(state,key));
 return !scoped||['all','selected'].includes(state.scopeMode)&&typeof state.scopeConfigured==='boolean'&&typeof state.appliesToCurrentUser==='boolean'&&typeof state.appliesToSubject==='boolean'&&typeof state.effectiveEnforced==='boolean'&&state.effectiveEnforced===(state.enabled&&state.appliesToSubject&&(state.scopeConfigured||!state.canOverride));
}

export const wholesaleAppliesToSubject=state=>state?.appliesToSubject!==false;
// The server resolves the invoice owner's scope, including an explicit choice
// that binds a previously exempt user. Profile permissions cannot override it.
export const wholesalePolicyEnforced=state=>typeof state?.effectiveEnforced==='boolean'?state.effectiveEnforced:state?.enabled===true&&state?.canOverride===false;

function lineSignature(items){
 return JSON.stringify((items||[]).map(item=>[String(item.productId??item.product_id??item.id),Number(item.qty),Number(item.price)]).sort((a,b)=>a[0].localeCompare(b[0])||a[1]-b[1]||a[2]-b[2]));
}

// Preserve the agreed prices when only notes, party, payment mode or fees are
// edited. New quantities, changed prices and added/removed materials use the
// current policy; fees cannot compensate for an underpriced material.
export function wholesaleEconomicsChanged(items,originalItems){
 return !Array.isArray(originalItems)||lineSignature(items)!==lineSignature(originalItems);
}

export function wholesaleSuggestedPrice(price){
 if(price==null||price===''||!Number.isFinite(Number(price))||Number(price)<0)return null;
 const nearest=Math.round(Number(price)*100)/100;
 return belowSystemMinimum(nearest,price)?Number((nearest+.01).toFixed(2)):nearest;
}

export function wholesaleLinePricing(state,productId,{historical=false}={}){
 const product=state?.products?.find(row=>String(row.id)===String(productId));
 const automatic=product?.floorSource==='cost',marked=product?.enabled===true;
 // Older servers expose only the configured price. An automatic row may carry
 // an inactive saved override; it must never stand in for the current cost.
 const raw=automatic||product?.floorSource==='configured'?product.effectiveMinPrice:product?.minPrice;
 const minimum=raw==null||raw===''?null:Number(raw);
 const price=Number.isFinite(minimum)&&minimum>=0?minimum:null;
 const suggested=wholesaleSuggestedPrice(price);
 return {
  price,suggested,marked,automatic,
  required:wholesalePolicyEnforced(state)&&(marked||automatic)&&!historical,
  historical,
  reason:state?.enabled!==true?'disabled':!marked&&!automatic?'unmarked':!wholesaleAppliesToSubject(state)?'outside_scope':!wholesalePolicyEnforced(state)?'override':historical?'historical':'required',
 };
}

export function wholesalePriceDefault(state,productId){
 const rule=wholesaleLinePricing(state,productId);
 return rule.required&&rule.suggested!==null?String(rule.suggested):'';
}

// Refresh a suggested line with the same policy snapshot used to validate and
// submit it. A manual/negotiated price and an archived agreed price stay put.
export function refreshWholesaleDefaults(items,state){
 if(!state)return items;
 return items.map(item=>{
  if(!item.useWholesaleFloor)return item;
  const rule=wholesaleLinePricing(state,item.id);
  if(!rule.required)return item;
  const price=rule.suggested==null?'':String(rule.suggested);
  return item.price===price?item:{...item,price};
 });
}

export function wholesaleFloorTokens(state,items,originalItems){
 if(!wholesalePolicyEnforced(state)||!wholesaleEconomicsChanged(items,originalItems))return undefined;
 const selected=new Set(items.map(i=>String(i.id??i.productId??i.product_id)));
 const tokens=Object.fromEntries((state.products||[]).filter(row=>selected.has(String(row.id))&&typeof row.floorToken==='string'&&row.floorToken).map(row=>[String(row.id),row.floorToken]));
 return Object.keys(tokens).length?tokens:undefined;
}

export function wholesalePricingIssues(state,items,originalItems){
 if(!wholesalePricingReady(state))return [{message:'انتظر تأكيد أسعار بيع الجملة أو حدّث الأسعار قبل الحفظ.'}];
 const historical=!wholesaleEconomicsChanged(items,originalItems);
 return items.flatMap(item=>{
  const rule=wholesaleLinePricing(state,item.id??item.productId??item.product_id,{historical});
  if(!rule.required)return [];
  // Protected users can enter a sale price; the server checks the private floor.
  if(rule.price===null&&rule.automatic)return [];
  if(rule.price===null)return [{id:item.id,name:item.name,minimum:null,message:'السعر المقرر للمادة «'+(item.name||'المحددة')+'» غير متاح. حدّث الأسعار قبل الحفظ.'}];
  if(item.price===''||item.price==null)return [];
  return belowSystemMinimum(item.price,rule.price)?[{id:item.id,name:item.name,minimum:rule.suggested}]:[];
 });
}
