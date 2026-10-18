// An interrupted response may already have committed. Keep the caller's request
// ID and payload intact; a manual retry confirms the same receipt exactly once.
export async function saveRequest(makeRequest,timeoutMs=15000){
 const controller=new AbortController();let timer;
 const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>{reject(new Error('لم يصل تأكيد الحفظ. أعد تأكيد نفس الطلب ولن يتكرر الوصل.'));controller.abort();},timeoutMs);});
 try{return await Promise.race([makeRequest(controller.signal),timeout]);}finally{clearTimeout(timer);}
}
