const key=userId=>'solar-receipt-deletion-attempt-v1:'+userId;
const storage=()=>{try{return globalThis.localStorage;}catch{return null;}};
const active=new Set();
export const DELETION_ATTEMPT_EVENT='solar-receipt-deletion-attempt';
const notify=()=>{if(typeof window!=='undefined')window.dispatchEvent(new Event(DELETION_ATTEMPT_EVENT));};
export function readDeletionAttempt(userId,store=storage()){
 try{const row=JSON.parse(store?.getItem(key(userId))||'null');return row?.userId===userId&&Number.isSafeInteger(row.invoiceId)&&typeof row.id==='string'&&/^[a-f0-9-]{36}$/i.test(row.id)&&['request','delete_direct'].includes(row.action)&&typeof row.token==='string'?row:null;}catch{return null;}
}
export const deletionAttemptBusy=userId=>active.has(userId);
export async function runDeletionAttempt(userId,options){
 if(active.has(userId))throw new Error('جاري تأكيد الحذف؛ انتظر النتيجة.');
 const locks=globalThis.navigator?.locks;
 if(locks)return locks.request('solar-receipt-deletion:'+userId,{ifAvailable:true},lock=>{
  if(!lock)throw new Error('يوجد طلب حذف قيد التأكيد في نافذة أخرى. انتظر نتيجته.');
  return executeDeletionAttempt(userId,options);
 });
 return executeDeletionAttempt(userId,options);
}
async function executeDeletionAttempt(userId,{prepare,send,currentUser,invoiceId,store=storage()}){
 if(active.has(userId))throw new Error('جاري تأكيد الحذف؛ انتظر النتيجة.');
 active.add(userId);notify();
 try{
  let row=readDeletionAttempt(userId,store);
  if(row&&invoiceId!=null&&row.invoiceId!==Number(invoiceId))throw new Error('يوجد حذف سابق لم يتأكد. أكّد نتيجة الطلب السابق أولًا.');
  if(!row){row=await prepare();if(!row)return null;row={...row,userId};
   // Do not send an irreversible request without a recoverable request ID.
   if(!store)throw new Error('تعذر حفظ محاولة الحذف على الجهاز. اسمح بالتخزين ثم أعد المحاولة.');
   const pending=readDeletionAttempt(userId,store);
   if(pending&&pending.id!==row.id)throw new Error('ظهر طلب حذف آخر قيد التأكيد. أكّد نتيجته أولًا.');
   store.setItem(key(userId),JSON.stringify(row));notify();
  }
  if(await currentUser()!==userId)throw new Error('تغيّر الحساب؛ سجّل الدخول بحساب صاحب الطلب لتأكيده.');
  const response=await send(row);
  if(await currentUser()!==userId)throw new Error('تغيّر الحساب أثناء تأكيد الحذف. ارجع إلى حساب صاحب الطلب لتأكيد النتيجة.');
  const clear=()=>{if(readDeletionAttempt(userId,store)?.id===row.id)store?.removeItem(key(userId));};
  if(response.error){if(/^[0-9A-Z]{5}$/.test(response.error.code||''))clear();throw response.error;}
  if(!response.data)throw new Error('لم يصل تأكيد الحذف؛ تحقق من الطلب السابق قبل المحاولة مجددًا.');
  clear();notify();return response.data;
 }finally{active.delete(userId);notify();}
}
