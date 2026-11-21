import test from 'node:test';
import assert from 'node:assert/strict';
import {watchAuthSession,sessionKey,rememberLogout,finishLogout,pendingLogout} from '../app/auth-lifecycle.mjs';
import {createSessionFetch,signOutDevice} from '../app/auth-session-fetch.mjs';
import {releaseDevicePush} from '../app/push-release.mjs';

const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const session=(id,sid)=>({user:{id},access_token:'header.'+Buffer.from(JSON.stringify({session_id:sid})).toString('base64url')+'.signature'});
function deferred(){let resolve;const promise=new Promise(r=>{resolve=r;});return {promise,resolve};}

test('a late startup read and deferred earlier events cannot restore a signed-out account',async()=>{
 let emit,unsubscribed=false,reads=[],identities=[];
 const fallback=deferred(),auth={getSession:()=>fallback.promise,onAuthStateChange(fn){emit=fn;return {data:{subscription:{unsubscribe(){unsubscribed=true;}}}};}};
 const watcher=watchAuthSession(auth,{onIdentity:s=>identities.push(s?.user.id||null),onRead:s=>reads.push(s.user.id),onUnavailable:()=>assert.fail()},1,1000);
 await wait(5);
 emit('SIGNED_IN',session('alice','one'));emit('SIGNED_OUT',null);emit('INITIAL_SESSION',session('outdated','startup'));
 fallback.resolve({data:{session:session('old','old')}});
 await wait(5);
 assert.deepEqual(identities,['alice',null]);assert.deepEqual(reads,[]);
 emit('SIGNED_IN',session('bob','two'));await wait(5);
 watcher.stop();emit('SIGNED_IN',session('stale','three'));
 assert.deepEqual(identities,['alice',null,'bob']);assert.deepEqual(reads,['bob']);assert.equal(unsubscribed,true);
});

test('an already-started profile read loses authority across sign-out and replacement login',async()=>{
 let emit;
 const started=deferred(),auth={onAuthStateChange(fn){emit=fn;return {data:{subscription:{unsubscribe(){}}}};}};
 const watcher=watchAuthSession(auth,{onIdentity(){},onRead(s,event,current){started.resolve(current);},onUnavailable(){}});
 emit('INITIAL_SESSION',session('alice','A'));const current=await started.promise;
 assert.equal(current(),true);emit('SIGNED_OUT',null);emit('SIGNED_IN',session('alice','B'));
 assert.equal(current(),false);watcher.stop();
});

test('failed logout marker survives refresh and never blocks a replacement session',()=>{
 const values=new Map(),previous=globalThis.localStorage;
 globalThis.localStorage={getItem:k=>values.get(k),setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)};
 try{
  const first=sessionKey(session('same','old')),another=sessionKey(session('same','new'));
  rememberLogout(first);assert.equal(pendingLogout(),first);assert.notEqual(pendingLogout(),another);
  rememberLogout(another);finishLogout(first);assert.equal(pendingLogout(),another);
  finishLogout(another);assert.equal(pendingLogout(),'');
 }finally{if(previous)globalThis.localStorage=previous;else delete globalThis.localStorage;}
});

test('logout push cleanup does not wait for worker.ready or change another user’s subscription',async()=>{
 let unsubscribed=0,cleared=0,deleted=0;
 const stored=new Map([['solar_push_user','old']]),storage={getItem:key=>stored.get(key),removeItem:key=>stored.delete(key)};
 const opts={storage,userId:'old',timeoutMs:50,isCurrent:()=>true,
  clearBinding:async()=>{cleared++;},removeEndpoint:async()=>{deleted++;}};
 await releaseDevicePush({...opts,worker:{get ready(){assert.fail('ready may never settle');},getRegistration:async()=>undefined}});
 const subscription=deferred(),clear=deferred();
 const worker={getRegistration:async()=>({pushManager:{getSubscription:()=>subscription.promise}})};
 const cleanup=releaseDevicePush({...opts,worker,clearBinding:async()=>clear.resolve()});await clear.promise;
 stored.set('solar_push_user','new');subscription.resolve({endpoint:'endpoint',unsubscribe:()=>{unsubscribed++;}});await cleanup;
 assert.equal(cleared+deleted+unsubscribed,0);assert.equal(stored.get('solar_push_user'),'new');
});

test('deferred push cleanup stops after its deadline before clearing a new user’s binding',async()=>{
 const reg=deferred();let touched=0;
 const cleanup=releaseDevicePush({worker:{getRegistration:()=>reg.promise},storage:{getItem:()=>null,removeItem(){}},
  userId:'old',timeoutMs:3,clearBinding:async()=>{touched++;},removeEndpoint:async()=>{touched++;}});
 await assert.rejects(cleanup);reg.resolve({pushManager:{getSubscription:()=>null}});await wait(0);assert.equal(touched,0);
});

test('local sign-out rejects a replacement bearer before network and permits a bounded retry',async()=>{
 const original=session('user','alpha'),next=session('user','beta');let calls=0;
 const request=createSessionFetch(async(_input,options)=>{calls++;return new Promise((resolve,reject)=>options.signal.addEventListener('abort',()=>reject(new DOMException('aborted','AbortError'))));},4);
 async function attempt(token){
  return signOutDevice({signOut({scope}){assert.equal(scope,'local');return request('https://fixture.test/auth/v1/logout',{method:'POST',headers:{authorization:'Bearer '+token}});}},original,()=>true);
 }
 assert.equal((await attempt(next.access_token)).status,409);assert.equal(calls,0);
 await assert.rejects(attempt(original.access_token),{name:'AbortError'});assert.equal(calls,1);
 assert.equal((await attempt(next.access_token)).status,409);
});
