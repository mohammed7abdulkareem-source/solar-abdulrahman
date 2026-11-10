export const WHOLESALE_PRICE_BATCH_LIMIT=100;

export function wholesalePriceDraft(row){
 return {minPrice:row.minPrice==null?'':String(row.minPrice),enabled:row.enabled===true};
}

const comparablePrice=value=>value===''||value==null?null:Number(value);
export function wholesalePriceChanged(row,draft){
 if(!draft)return false;
 return draft.enabled!==(row.enabled===true)||comparablePrice(draft.minPrice)!==comparablePrice(row.minPrice);
}

export function wholesalePriceValidation(draft){
 if(draft.minPrice==='')return draft.enabled?'حدد سعر البيع الأدنى قبل تطبيقه على المادة.':'';
 const value=Number(draft.minPrice);
 if(!/^\d*(?:\.\d{1,2})?$/.test(draft.minPrice)||!Number.isFinite(value)||value<=0||value>1e12)return 'أدخل سعراً صحيحاً أكبر من صفر، أو اتركه فارغاً بدون تطبيق الحد.';
 return '';
}

export function wholesalePriceItems(products,drafts){
 return products.filter(row=>wholesalePriceChanged(row,drafts[row.id])).map(row=>({productId:row.id,minPrice:drafts[row.id].minPrice===''?null:Number(drafts[row.id].minPrice),enabled:drafts[row.id].enabled,expectedRevision:row.revision}));
}

const attemptKey=userId=>'solar-wholesale-pricing-attempt-v1:'+userId;
const attemptStore=()=>{try{return globalThis.sessionStorage;}catch{return null;}};
export function readWholesalePriceAttempt(userId){
 try{
  const attempt=JSON.parse(attemptStore()?.getItem(attemptKey(userId))||'null');
  if(!attempt||typeof attempt.id!=='string'||!/^[a-f0-9-]{36}$/i.test(attempt.id)||!['save','toggle'].includes(attempt.action)||!attempt.payload||typeof attempt.payload!=='object')return null;
  if(attempt.action==='toggle')return typeof attempt.payload.enabled==='boolean'&&Number.isInteger(attempt.payload.expectedRevision)&&attempt.payload.expectedRevision>=0?attempt:null;
  return Array.isArray(attempt.payload.items)&&attempt.payload.items.length>0&&attempt.payload.items.length<=WHOLESALE_PRICE_BATCH_LIMIT?attempt:null;
 }catch{return null;}
}
export function rememberWholesalePriceAttempt(userId,attempt){
 try{const storage=attemptStore(),key=attemptKey(userId),value=JSON.stringify(attempt);if(!storage)return false;storage.setItem(key,value);return storage.getItem(key)===value;}catch{return false;}
}
export function clearWholesalePriceAttempt(userId,id){try{if(readWholesalePriceAttempt(userId)?.id===id)attemptStore()?.removeItem(attemptKey(userId));}catch{}}
