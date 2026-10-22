const CACHE='abdulrahman-solar-v3-64-0';
const CORE=['/manifest.webmanifest','/icon-192.png','/icon-512.png','/apple-touch-icon.png'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(CORE)));self.skipWaiting()});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith('abdulrahman-solar-')&&key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()))});
// Never cache authenticated data or HTML; an offline screen must not show stale accounts.
self.addEventListener('fetch',event=>{
 const url=new URL(event.request.url);
 if(event.request.method!=='GET'||url.origin!==self.location.origin||!CORE.includes(url.pathname))return;
 event.respondWith(fetch(event.request).catch(()=>caches.match(event.request)));
});

// Persist only the account binding; never store session tokens in the worker.
function pushIdentity(userId,write=false){
 return new Promise((resolve,reject)=>{
  const request=indexedDB.open('solar-push-device',1);
  request.onupgradeneeded=()=>request.result.createObjectStore('settings');
  request.onerror=()=>reject(request.error);
  request.onsuccess=()=>{
   const db=request.result,tx=db.transaction('settings',write?'readwrite':'readonly'),store=tx.objectStore('settings');
   let value=null;const op=write?store.put(userId,'user'):store.get('user');
   op.onsuccess=()=>{value=op.result};
   tx.oncomplete=()=>{db.close();resolve(write?userId:value)};tx.onerror=()=>{db.close();reject(tx.error)};
  };
 });
}
self.addEventListener('message',event=>{
 if(event.data?.type!=='SOLAR_PUSH_USER')return;
 const userId=event.data.userId;
 if(userId!==null&&(typeof userId!=='string'||!/^[0-9a-f-]{36}$/i.test(userId)))return;
 event.waitUntil(pushIdentity(userId,true).then(()=>event.ports[0]?.postMessage({ok:true})).catch(()=>event.ports[0]?.postMessage({ok:false})));
});
self.addEventListener('push',event=>{
 event.waitUntil((async()=>{
  let data;try{data=event.data?.json()}catch{return}
  if(!data?.userId||await pushIdentity()!==data.userId)return;
  await self.registration.showNotification(data.title||'عبدالرحمن سولار',{
   body:data.body||'لديك تحديث جديد في البرنامج',icon:'/icon-192.png',badge:'/icon-192.png',
   tag:'solar-'+data.id,lang:'ar',dir:'rtl',data:{jobId:data.jobId,userId:data.userId,transferId:data.transferId,stockTransferId:data.stockTransferId,event:data.event,invoiceKind:data.invoiceKind},silent:false,vibrate:[200,90,200],renotify:!!(data.event?.startsWith('warehouse_')||data.event?.startsWith('stock_transfer_')||data.event?.startsWith('profit_'))
  });
 })());
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 event.waitUntil((async()=>{
  const {jobId,userId,transferId,stockTransferId,event:noticeEvent,invoiceKind}=event.notification.data||{};
  if(await pushIdentity()!==userId)return;
  const url=new URL('/',self.location.origin);
  if(stockTransferId&&/^[0-9a-f-]{36}$/i.test(stockTransferId)){url.searchParams.set('section','warehouse');url.searchParams.set('stockTransfer',stockTransferId);}
  else if(transferId&&/^[0-9a-f-]{36}$/i.test(transferId)){url.searchParams.set('section','cashTransfers');url.searchParams.set('transfer',transferId);}
  else if(noticeEvent?.startsWith('profit_')){url.searchParams.set('section','profit');url.searchParams.set('profitTab','settlements');}
  else if(jobId&&/^-?\d+$/.test(String(jobId))){url.searchParams.set('section',noticeEvent==='warehouse_ready'?(invoiceKind==='system'?'installations':'salesHistory'):noticeEvent?.startsWith('warehouse_')?'warehouse':'installations');url.searchParams.set('job',String(jobId));}
  const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
  const existing=windows.find(w=>new URL(w.url).origin===self.location.origin);
  if(existing){await existing.navigate(url.href);return existing.focus()}
  return self.clients.openWindow(url.href);
 })());
});
