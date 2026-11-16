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
 if(changed===0)return action==='save'?'الأسعار مطابقة للمحفوظ؛ لا توجد تغييرات جديدة.':'حالة الأسعار الإلزامية مطابقة للمحفوظ.';
 if(action==='save')return changed===null?'تم حفظ أسعار بيع الجملة.':'تم تحديث أسعار '+changed+' مادة'+(notified?' وإرسال إشعار للمستخدمين.':'.');
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
  if(!attempt||typeof attempt.id!=='string'||!/^[a-f0-9-]{36}$/i.test(attempt.id)||!['save','toggle','scope'].includes(attempt.action)||!attempt.payload||typeof attempt.payload!=='object')return null;
  if(attempt.action==='toggle')return typeof attempt.payload.enabled==='boolean'&&Number.isInteger(attempt.payload.expectedRevision)&&attempt.payload.expectedRevision>=0?attempt:null;
  if(attempt.action==='scope'){
   const {mode,userIds,expectedRevision}=attempt.payload;
   return ['all','selected'].includes(mode)&&Array.isArray(userIds)&&userIds.every(id=>typeof id==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(id))&&new Set(userIds).size===userIds.length&&Number.isInteger(expectedRevision)&&expectedRevision>=0&&(mode==='all'?userIds.length===0:userIds.length>0)?attempt:null;
  }
  return Array.isArray(attempt.payload.items)&&attempt.payload.items.length>0&&attempt.payload.items.length<=WHOLESALE_PRICE_BATCH_LIMIT?attempt:null;
 }catch{return null;}
}
export function rememberWholesalePriceAttempt(userId,attempt){
 try{const storage=attemptStore(),key=attemptKey(userId),value=JSON.stringify(attempt);if(!storage)return false;storage.setItem(key,value);return storage.getItem(key)===value;}catch{return false;}
}
export function clearWholesalePriceAttempt(userId,id){try{if(readWholesalePriceAttempt(userId)?.id===id)attemptStore()?.removeItem(attemptKey(userId));}catch{}}
