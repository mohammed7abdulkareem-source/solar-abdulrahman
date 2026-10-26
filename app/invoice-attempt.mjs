import {invoiceAttemptSignature} from './inventory-valuation.mjs';
const storageKey=uid=>'solar-invoice-attempt-v1:'+uid;
const browserStorage=()=>{try{return globalThis.localStorage;}catch{return null;}};
const valid=record=>record&&typeof record.requestId==='string'&&/^[a-f0-9-]{36}$/i.test(record.requestId)&&record.payload&&['sale','system','purchase'].includes(record.payload.kind)&&Array.isArray(record.payload.items);
export function restoreInvoiceAttempt(attempt,uid,storage=browserStorage()){
 if(attempt.current?.userId===uid)return attempt.current;
 let stored=null;try{stored=JSON.parse(storage?.getItem(storageKey(uid))||'null');}catch{}
 attempt.current=valid(stored)&&stored.userId===uid?{...stored,signature:invoiceAttemptSignature(stored.payload)}:null;
 return attempt.current;
}
function persist(record,storage){try{storage?.setItem(storageKey(record.userId),JSON.stringify(record));}catch{}}
export function clearInvoiceAttempt(attempt,uid,storage=browserStorage(),requestId=attempt.current?.requestId){
 if(attempt.current?.userId===uid&&attempt.current.requestId===requestId)attempt.current=null;
 try{const stored=JSON.parse(storage?.getItem(storageKey(uid))||'null');if(stored?.requestId===requestId)storage.removeItem(storageKey(uid));}catch{}
}
async function sameUser(uid,currentUser){if(currentUser&&await currentUser()!==uid)throw new Error('تغيّر الحساب؛ افتح الفاتورة من حساب صاحبها.');}
async function resolveRecord(attempt,uid,record,{resolve,currentUser,storage}){
 await sameUser(uid,currentUser);
 const {data,error}=await resolve(record);
 if(error)throw error;
 await sameUser(uid,currentUser);
 if(!['saved','not_saved','deleted'].includes(data?.state))throw new Error('تعذر التحقق من محاولة الحفظ السابقة.');
 if(data.state!=='saved')clearInvoiceAttempt(attempt,uid,storage,record.requestId);
 return data;
}
export async function resolveInvoiceAttempt(attempt,uid,options){
 if(attempt.busy)throw new Error('جاري تأكيد الحفظ؛ انتظر النتيجة.');
 const storage=options.storage??browserStorage(),record=restoreInvoiceAttempt(attempt,uid,storage);
 if(!record)return {state:'not_saved'};
 attempt.busy=true;try{return await resolveRecord(attempt,uid,record,{...options,storage});}finally{attempt.busy=false;}
}
export async function saveInvoiceAttempt(attempt,uid,candidate,{send,resolve,currentUser,storage=browserStorage(),uuid=()=>crypto.randomUUID()}){
 if(attempt.busy)throw new Error('جاري تأكيد الحفظ؛ انتظر النتيجة.');
 attempt.busy=true;
 try{
  await sameUser(uid,currentUser);
  let record=restoreInvoiceAttempt(attempt,uid,storage);
  const signature=invoiceAttemptSignature(candidate);
  if(record&&record.signature!==signature){
   const status=await resolveRecord(attempt,uid,record,{resolve,currentUser,storage});
   if(status.state==='saved'){
    const error=new Error('المحاولة السابقة محفوظة بوصل #'+status.invoice.receiptNo+'. راجع الوصل قبل حفظ فاتورة مستقلة.');
    error.invoiceRecovery=status;throw error;
   }
   record=null;
  }
  if(!record){record={userId:uid,requestId:uuid(),payload:JSON.parse(JSON.stringify(candidate)),signature,createdAt:new Date().toISOString()};attempt.current=record;persist(record,storage);}
  await sameUser(uid,currentUser);
  const {data,error}=await send(record);
  await sameUser(uid,currentUser);
  if(error){
   // A SQLSTATE confirms a rolled-back database operation. Transport/API errors
   // leave the original nonce intact until the server resolves its outcome.
   if(/^[0-9A-Z]{5}$/.test(error.code||''))clearInvoiceAttempt(attempt,uid,storage,record.requestId);
   throw error;
  }
  clearInvoiceAttempt(attempt,uid,storage,record.requestId);return data;
 }finally{attempt.busy=false;}
}
