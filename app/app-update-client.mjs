export async function readAppVersion(controller=new AbortController()){
 const timeout=setTimeout(()=>controller.abort(),15000);
 try{
  const response=await fetch('/version.json?check='+Date.now(),{cache:'no-store',signal:controller.signal});
  if(!response.ok)throw new Error('Version unavailable');
  const data=await response.json();
  if(typeof data?.version!=='string'||!/^\d+\.\d+\.\d+$/.test(data.version))throw new Error('Invalid app version');
  return data.version;
 }finally{clearTimeout(timeout);}
}

export function watchAppVersion(notify){
 let stopped=false,request=null;
 async function check(){
  if(stopped||request||document.visibilityState!=='visible'||window.navigator.onLine===false)return;
  request=new AbortController();
  try{
   const version=await readAppVersion(request);
   if(!stopped)notify(version);
  }catch{/* Keep the last verified version until the next successful check. */}
  finally{request=null;}
 }
 const events=['focus','online','pageshow'];
 for(const event of events)window.addEventListener(event,check);
 document.addEventListener('visibilitychange',check);
 const interval=setInterval(check,5*60*1000);
 check();
 return ()=>{
  if(stopped)return;
  stopped=true;request?.abort();clearInterval(interval);
  for(const event of events)window.removeEventListener(event,check);
  document.removeEventListener('visibilitychange',check);
 };
}

export async function reloadVerifiedApp(controller){
 await readAppVersion(controller);
 // The worker caches install icons only. A delayed worker update must not
 // prevent navigation to the verified application, including on older PWAs.
 let timer;
 try{
  const workers=window.navigator.serviceWorker;
  if(workers&&!controller.signal.aborted){
   const update=workers.register('/sw.js',{updateViaCache:'none'}).then(registration=>registration.update());
   await Promise.race([update,new Promise(resolve=>{timer=setTimeout(resolve,4000);})]);
  }
 }catch{/* The application HTML is still served over the network. */}
 finally{clearTimeout(timer);}
 if(controller.signal.aborted)return;
 const url=new URL(window.location.href);
 url.searchParams.set('updated',String(Date.now()));
 window.location.replace(url.href);
}
