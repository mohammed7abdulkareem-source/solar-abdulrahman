const CACHE='abdulrahman-solar-v3-1-1';
const CORE=['/manifest.webmanifest','/icon.svg'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(CORE)));self.skipWaiting()});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith('abdulrahman-solar-')&&key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()))});
// Never cache authenticated data or HTML; an offline screen must not show stale accounts.
self.addEventListener('fetch',event=>{
 const url=new URL(event.request.url);
 if(event.request.method!=='GET'||url.origin!==self.location.origin||!CORE.includes(url.pathname))return;
 event.respondWith(fetch(event.request).catch(()=>caches.match(event.request)));
});
