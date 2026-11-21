import test from 'node:test';
import assert from 'node:assert/strict';
import {readAppVersion,reloadVerifiedApp,watchAppVersion} from '../app/app-update-client.mjs';
import {setImmediate as settled} from 'node:timers/promises';

function browser(t){
 const win=new EventTarget(),doc=new EventTarget(),locations=[];
 win.location={href:'https://example.test/?section=sale#draft',replace:href=>locations.push(href)};
 win.navigator={onLine:true};
 doc.visibilityState='visible';
 for(const [name,value] of [['window',win],['document',doc]]){
  const original=Object.getOwnPropertyDescriptor(globalThis,name);
  Object.defineProperty(globalThis,name,{value,configurable:true});
  t.after(()=>{if(original)Object.defineProperty(globalThis,name,original);else delete globalThis[name];});
 }
 return {win,doc,locations};
}

test('version checks on mount, resume, reconnect and while visible preserve an open draft',async t=>{
 const {win,doc,locations}=browser(t),noticed=[];
 const fetch=t.mock.method(globalThis,'fetch',async()=>Response.json({version:'4.1.20'}));
 let tick;
 t.mock.method(globalThis,'setInterval',(callback,delay)=>{assert.equal(delay,300000);tick=callback;return 0;});
 const stop=watchAppVersion(version=>noticed.push(version));t.after(stop);
 await settled();
 assert.deepEqual(noticed,['4.1.20']);
 assert.equal(fetch.mock.calls[0].arguments[1].cache,'no-store');
 doc.visibilityState='hidden';doc.dispatchEvent(new Event('visibilitychange'));tick();await settled();
 assert.equal(noticed.length,1);
 doc.visibilityState='visible';doc.dispatchEvent(new Event('visibilitychange'));win.dispatchEvent(new Event('focus'));await settled();
 assert.equal(noticed.length,2,'paired focus and visibility events should coalesce');
 win.dispatchEvent(new Event('pageshow'));await settled();
 win.navigator.onLine=false;tick();await settled();
 assert.equal(noticed.length,3);
 win.navigator.onLine=true;win.dispatchEvent(new Event('online'));await settled();tick();await settled();
 assert.equal(noticed.length,5);
 stop();win.dispatchEvent(new Event('focus'));await settled();
 assert.equal(noticed.length,5);
 assert.deepEqual(locations,[]);
});
test('confirmed refresh navigates to the same section after worker registration fails',async t=>{
 const {win,locations}=browser(t);
 t.mock.method(globalThis,'fetch',async()=>Response.json({version:'4.1.20'}));
 win.navigator.serviceWorker={register:async()=>{throw Error('unsupported');}};
 await reloadVerifiedApp(new AbortController());
 const result=new URL(locations[0]);
 assert.equal(result.searchParams.get('section'),'sale');
 assert.ok(result.searchParams.has('updated'));assert.equal(result.hash,'#draft');
});
test('invalid or unavailable version information cannot trigger a reload',async t=>{
 const {locations}=browser(t);
 const mock=t.mock.method(globalThis,'fetch',async()=>Response.json({}));
 await assert.rejects(reloadVerifiedApp(new AbortController()));
 mock.mock.mockImplementation(async()=>new Response(null,{status:503}));
 await assert.rejects(readAppVersion());assert.deepEqual(locations,[]);
});
