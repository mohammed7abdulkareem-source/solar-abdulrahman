export const PROFIT_TARGET_EVENT='solar-profit-target-attempt';
const storageKey=actorId=>'solar-profit-target-v1:'+actorId;
const active=new Set();
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const numeric=value=>(typeof value==='number'||(typeof value==='string'&&value.trim()!==''))&&Number.isFinite(Number(value));
const storage=()=>{try{return globalThis.localStorage;}catch{return null;}};
const notify=()=>{if(typeof window!=='undefined')window.dispatchEvent(new Event(PROFIT_TARGET_EVENT));};

function targetPayload(input){
 if(!uuid.test(input?.ownerId)||!numeric(input.targetBalance)||typeof input.expectedToken!=='string'||!input.expectedToken.trim())return null;
 return {ownerId:input.ownerId,targetBalance:Number(input.targetBalance),expectedToken:input.expectedToken,note:input.note??''};
}
export function readProfitTargetAttempt(actorId,store=storage()){
 if(!uuid.test(actorId))return null;
 try{
  const attempt=JSON.parse(store?.getItem(storageKey(actorId))||'null');
  return attempt?.actorId===actorId&&uuid.test(attempt.id)&&targetPayload(attempt.payload)?attempt:null;
 }catch{return null;}
}
export async function runProfitTargetAttempt(actorId,input,{currentUser,send,store=storage(),locks=globalThis.navigator?.locks,makeId=()=>crypto.randomUUID()}){
 const key=storageKey(actorId);
 const busy=()=>new Error('توجد تسوية أرباح قيد التأكيد. انتظر نتيجتها.');
 if(active.has(actorId))throw busy();
 async function execute(){
  if(active.has(actorId))throw busy();
  active.add(actorId);
  try{
   if(!uuid.test(actorId)||await currentUser()!==actorId)throw new Error('تغيّر الحساب. افتح التسوية من حساب الإدارة الذي بدأها.');
   let attempt=readProfitTargetAttempt(actorId,store);
   if(input!=null){
    const payload=targetPayload(input);
    if(!payload)throw new Error('راجع المستخدم والرصيد المطلوب وحدّث كشف الأرباح قبل التسوية.');
    if(attempt&&JSON.stringify(attempt.payload)!==JSON.stringify(payload))throw new Error('أكّد نتيجة التسوية السابقة أولاً.');
    if(!attempt){
     attempt={actorId,id:makeId(),payload};
     try{
      store.setItem(key,JSON.stringify(attempt));
      if(readProfitTargetAttempt(actorId,store)?.id!==attempt.id)throw new Error();
     }catch{throw new Error('تعذر حفظ مرجع التسوية على الجهاز. تحقق من التخزين ثم أعد المحاولة.');}
     notify();
    }
   }
   if(!attempt)throw new Error('لا توجد تسوية سابقة بانتظار التأكيد.');
   const {data,error}=await send(attempt);
   if(await currentUser()!==actorId)throw new Error('تغيّر الحساب أثناء التأكيد. ارجع إلى حساب الإدارة للتحقق من النتيجة.');
   const clear=()=>{if(readProfitTargetAttempt(actorId,store)?.id===attempt.id){store.removeItem(key);notify();}};
   if(error){
    // A database rejection rolls back the operation. An HTTP/transport failure can arrive after commit.
    if(/^[0-9A-Z]{5}$/.test(error.code||''))clear();
    throw error;
   }
   if(data?.id!==attempt.id||data.ownerId!==attempt.payload.ownerId||!numeric(data.before)||!numeric(data.after)||!numeric(data.delta)||Number(data.after)!==Number(attempt.payload.targetBalance)){
    throw new Error('لم يصل تأكيد مطابق للتسوية. أعد تأكيد نفس الطلب.');
   }
   clear();
   return data;
  }finally{active.delete(actorId);}
 }
 if(locks)return locks.request(key,{ifAvailable:true},lock=>{if(!lock)throw busy();return execute();});
 return execute();
}
