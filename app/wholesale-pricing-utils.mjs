import {wholesaleSuggestedPrice} from './wholesale-invoice-pricing.mjs';

export const WHOLESALE_PRICE_BATCH_LIMIT=100;

// This is a settings view filter only. Keep the full server policy intact so an
// out-of-stock item's saved floor still applies when stock returns.
export function availableWholesalePriceProducts(products){
 return Array.isArray(products)?products.filter(row=>{
  const quantity=row?.qty;
  return (typeof quantity==='number'||typeof quantity==='string'&&quantity.trim()!=='')&&Number.isFinite(Number(quantity))&&Number(quantity)>0;
 }):[];
}

export function wholesalePriceSaveNotice(action,payload,result){
 const changed=Number.isInteger(result?.changedCount)&&result.changedCount>=0?result.changedCount:null;
 const notified=Number.isInteger(result?.notifiedCount)&&result.notifiedCount>0;
 if(action==='configure'||(['toggle','scope'].includes(action)&&typeof result?.enabled==='boolean')){
  const enabled=typeof result?.enabled==='boolean'?result.enabled:payload.enabled;
  const mode=['all','selected'].includes(result?.scopeMode)?result.scopeMode:payload.mode;
  const status=enabled?'مفعّل'+(mode==='all'?' لجميع المستخدمين':mode==='selected'?' للمستخدمين المحددين':''):'متوقف للجميع مع الاحتفاظ بالاختيارات';
  return 'تم تأكيد حفظ إعدادات الإلزام؛ الحالة الحالية: '+status+'.'+(changed>0&&notified?' تم إرسال إشعار بالتغيير المحفوظ.':'');
 }
 if(changed===0)return action==='save'?'الأسعار مطابقة للمحفوظ؛ لا توجد تغييرات جديدة.':'حالة الأسعار الإلزامية مطابقة للمحفوظ.';
 if(action==='save')return changed===null?'تم حفظ أسعار المواد.':'تم تحديث أسعار '+changed+' مادة'+(notified?' وإرسال إشعار للمستخدمين.':'.');
 if(action==='scope')return 'تم حفظ المستخدمين المشمولين بالأسعار الإلزامية'+(changed!==null&&notified?' وإرسال إشعار للمستخدمين.':'.');
 const message=payload.enabled?'تم تشغيل الأسعار الإلزامية':'تم إيقاف الأسعار الإلزامية مع الاحتفاظ بالأسعار المحفوظة';
 return message+(changed!==null&&notified?' وإرسال إشعار للمستخدمين.':'.');
}

const uniqueSortedIds=ids=>[...new Set(Array.isArray(ids)?ids:[])].sort();
export function wholesaleScopeDraft(state){
 const eligible=new Set((state?.eligibleUsers||[]).map(user=>user.id));
 return {mode:state?.scopeMode==='selected'?'selected':'all',userIds:uniqueSortedIds(state?.selectedUserIds).filter(id=>eligible.has(id))};
}
export function wholesaleScopeChanged(state,draft){
 if(!draft)return false;
 const saved=wholesaleScopeDraft(state);
 return state?.scopeConfigured===false||draft.mode!==saved.mode||(draft.mode==='selected'&&JSON.stringify(uniqueSortedIds(draft.userIds))!==JSON.stringify(saved.userIds));
}
export function wholesaleScopeValidation(draft,eligibleUsers){
 if(!['all','selected'].includes(draft?.mode))return 'اختر المستخدمين المشمولين بالتسعير.';
 if(draft.mode==='all')return '';
 const ids=uniqueSortedIds(draft.userIds),eligible=new Set((eligibleUsers||[]).map(user=>user.id));
 if(!ids.length)return 'اختر مستخدماً واحداً على الأقل قبل حفظ النطاق.';
 if(ids.some(id=>!eligible.has(id)))return 'تغيّرت قائمة المستخدمين المتاحين. حدّث القائمة وراجع الاختيار.';
 return '';
}
export function wholesaleScopePayload(draft,revision){
 return {mode:draft.mode,userIds:draft.mode==='all'?[]:uniqueSortedIds(draft.userIds),expectedRevision:revision};
}

export function wholesaleConfigurationDraft(state){
 return {enabled:state?.enabled===true,...wholesaleScopeDraft(state)};
}
export function wholesaleConfigurationChanged(state,draft){
 return !!draft&&(draft.enabled!==(state?.enabled===true)||wholesaleScopeChanged(state,draft));
}
export function wholesaleConfigurationValidation(draft,eligibleUsers){
 if(typeof draft?.enabled!=='boolean')return 'حدد تشغيل الإلزام أو إيقافه.';
 if(draft.mode==='selected'&&Array.isArray(draft.userIds)&&draft.userIds.length===0)return draft.enabled?'اختر مستخدماً واحداً على الأقل لتشغيل الإلزام.':'';
 return wholesaleScopeValidation(draft,eligibleUsers);
}
export function wholesaleConfigurationPayload(draft,revision){
 return {enabled:draft.enabled,...wholesaleScopePayload(draft,revision)};
}
export function wholesaleConfigurationUser(draft,id,checked,eligibleUsers){
 const eligible=uniqueSortedIds((eligibleUsers||[]).map(user=>user.id));
 if(!eligible.includes(id))return draft;
 const selected=new Set(draft.mode==='all'?eligible:uniqueSortedIds(draft.userIds).filter(value=>eligible.includes(value)));
 if(checked)selected.add(id);else selected.delete(id);
 return {...draft,mode:eligible.every(value=>selected.has(value))?'all':'selected',userIds:eligible.every(value=>selected.has(value))?[]:[...selected].sort()};
}

// Use the database quote for the saved automatic floor. A manager previewing an
// unchecked override needs the current cost because its saved floor is manual.
export function wholesaleEffectivePrice(row,draft,personalPrices=false){
 const enabled=draft?.enabled??row.enabled;
 const amount=Number(draft?.minPrice??row.minPrice);
 if(enabled&&amount>0)return {source:'configured',amount};
 if(personalPrices||row.personalPriceBasis)return {source:'cost',amount:null};
 const cost=row.floorSource==='cost'?row.effectiveMinPrice:row.cost;
 return {source:'cost',amount:wholesaleSuggestedPrice(cost)};
}

export function refreshWholesalePricing(previous,latest,editing){
 if(!editing||!previous)return latest;
 // Keep the settings/revisions the administrator actually edited. Refresh only
 // valuation fields so a concurrent override still requires conflict review.
 const liveRows=new Map(latest.products.map(row=>[row.id,row]));
 const products=previous.products.map(row=>{
  const live=liveRows.get(row.id);
  if(!live)return row;
  const custom=row.enabled&&Number(row.minPrice)>0;
  const liveCost=live.floorSource==='cost'?live.effectiveMinPrice:live.cost;
  return {...row,cost:live.cost,personalPriceBasis:live.personalPriceBasis,
   floorSource:custom?'configured':'cost',effectiveMinPrice:custom?row.minPrice:live.personalPriceBasis?null:liveCost};
 });
 return {...previous,products};
}

export function wholesalePriceDraft(row){
 return {minPrice:row.minPrice==null?'':String(row.minPrice),enabled:row.enabled===true};
}

const comparablePrice=value=>value===''||value==null?null:Number(value);
export function wholesalePriceChanged(row,draft){
 if(!draft)return false;
 return draft.enabled!==(row.enabled===true)||comparablePrice(draft.minPrice)!==comparablePrice(row.minPrice);
}

export function wholesalePriceValidation(draft){
 if(draft.minPrice==='')return draft.enabled?'أدخل السعر اليدوي أو ألغِ التحديد لاستخدام الكلفة الحالية.':'';
 const value=Number(draft.minPrice);
 if(!/^\d*(?:\.\d{1,2})?$/.test(draft.minPrice)||!Number.isFinite(value)||value<=0||value>1e12)return 'أدخل سعراً يدوياً أكبر من صفر أو امسح الحقل لاستخدام الكلفة الحالية.';
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
  if(!attempt||typeof attempt.id!=='string'||!/^[a-f0-9-]{36}$/i.test(attempt.id)||!['save','toggle','scope','configure'].includes(attempt.action)||!attempt.payload||typeof attempt.payload!=='object')return null;
  if(attempt.action==='toggle')return typeof attempt.payload.enabled==='boolean'&&Number.isInteger(attempt.payload.expectedRevision)&&attempt.payload.expectedRevision>=0?attempt:null;
  if(attempt.action==='scope'||attempt.action==='configure'){
   const {mode,userIds,expectedRevision}=attempt.payload;
   const configuration=attempt.action==='configure';
   if(configuration&&typeof attempt.payload.enabled!=='boolean')return null;
   return ['all','selected'].includes(mode)&&Array.isArray(userIds)&&userIds.every(id=>typeof id==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id))&&new Set(userIds).size===userIds.length&&Number.isInteger(expectedRevision)&&expectedRevision>=0&&(mode==='all'?userIds.length===0:userIds.length>0||configuration&&attempt.payload.enabled===false)?attempt:null;
  }
  return Array.isArray(attempt.payload.items)&&attempt.payload.items.length>0&&attempt.payload.items.length<=WHOLESALE_PRICE_BATCH_LIMIT?attempt:null;
 }catch{return null;}
}
export function rememberWholesalePriceAttempt(userId,attempt){
 try{const storage=attemptStore(),key=attemptKey(userId),value=JSON.stringify(attempt);if(!storage)return false;storage.setItem(key,value);return storage.getItem(key)===value;}catch{return false;}
}
export function clearWholesalePriceAttempt(userId,id){try{if(readWholesalePriceAttempt(userId)?.id===id)attemptStore()?.removeItem(attemptKey(userId));}catch{}}
