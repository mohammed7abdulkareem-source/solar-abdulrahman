export async function releaseDevicePush({worker,storage,userId,isCurrent=()=>true,timeoutMs=5000,clearBinding,removeEndpoint}){
 const controller=new AbortController();
 let timer;
 const current=()=>!controller.signal.aborted&&isCurrent()&&(!storage.getItem('solar_push_user')||storage.getItem('solar_push_user')===userId);
 async function cleanup(){
  if(!current())return;
  storage.removeItem('solar_push_user');
  if(!worker)return;
  // ready never settles on a browser with no active registration.
  const registration=await worker.getRegistration();
  if(!registration||!current())return;
  const clear=clearBinding(registration,userId).catch(()=>{});
  const subscription=await registration.pushManager?.getSubscription();
  if(!current())return;
  const tasks=[clear];
  if(subscription){
   tasks.push(removeEndpoint(subscription.endpoint,userId,controller.signal),subscription.unsubscribe());
  }
  if(registration.getNotifications)tasks.push(registration.getNotifications().then(notices=>{
   if(current())notices.filter(n=>!userId||n.data?.userId===userId).forEach(n=>n.close());
  }));
  const results=await Promise.allSettled(tasks);
  const failed=results.find(result=>result.status==='rejected');
  if(failed)throw failed.reason;
 }
 try{
  await Promise.race([cleanup(),new Promise((_,reject)=>{timer=setTimeout(()=>{
   controller.abort();reject(new Error('تعذر إكمال إيقاف إشعارات الجهاز.'));
  },timeoutMs);})]);
 }finally{clearTimeout(timer);}
}
