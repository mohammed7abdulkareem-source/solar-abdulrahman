// Share an in-flight read per signed-in account. A confirmed write invalidates
// a read that started earlier, so every waiter receives the newer snapshot.
export function createLatestLoader(read){
 const jobs=new Map();
 return function load(key,{fresh=false}={}){
  let job=jobs.get(key);
  if(!job){job={revision:0,promise:null};jobs.set(key,job);}
  if(fresh)job.revision++;
  if(job.promise)return job.promise;
  job.promise=(async()=>{for(;;){const revision=job.revision,result=await read(key);if(revision===job.revision)return result;}})().finally(()=>{if(jobs.get(key)===job)jobs.delete(key);});
  return job.promise;
 };
}
// Saving is confirmed by the protected RPC; refreshing other sections must not
// keep the receipt in a saving state, or turn a refresh failure into a save retry.
export function refreshAfterSave(refresh,onError){
 Promise.resolve().then(()=>refresh?.()).catch(error=>onError?.(error));
}
