import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
test('notification opens the cash request, installation task and rejects another account',async()=>{
 const handlers={},opened=[];
 const uid='11111111-1111-1111-1111-111111111111',transfer='22222222-2222-2222-2222-222222222222';
 const context=vm.createContext({URL,self:{location:{origin:'https://solar.example'},addEventListener:(name,fn)=>handlers[name]=fn,clients:{matchAll:async()=>[],openWindow:async url=>opened.push(url)}}});
 vm.runInContext(readFileSync(new URL('../public/sw.js',import.meta.url),'utf8'),context);
 vm.runInContext('pushIdentity=async()=>"'+uid+'"',context);
 const click=async data=>{let done;handlers.notificationclick({notification:{data,close(){}},waitUntil:p=>done=p});await done};
 await click({userId:uid,transferId:transfer});assert.equal(new URL(opened[0]).searchParams.get('section'),'cashTransfers');assert.equal(new URL(opened[0]).searchParams.get('transfer'),transfer);
 await click({userId:uid,jobId:42});assert.equal(new URL(opened[1]).searchParams.get('job'),'42');
 await click({userId:uid,jobId:44,event:'warehouse_new'});assert.equal(new URL(opened[2]).searchParams.get('section'),'warehouse');assert.equal(new URL(opened[2]).searchParams.get('job'),'44');
 await click({userId:'another-account',jobId:43});assert.equal(opened.length,3);
});
test('warehouse push requests audible notification and routes ready systems to the office',async()=>{
 const handlers={},shown=[],opened=[],uid='11111111-1111-1111-1111-111111111111';
 const context=vm.createContext({URL,self:{location:{origin:'https://solar.example'},addEventListener:(n,fn)=>handlers[n]=fn,registration:{showNotification:async(t,o)=>shown.push({t,o})},clients:{matchAll:async()=>[],openWindow:async url=>opened.push(url)}}});
 vm.runInContext(readFileSync(new URL('../public/sw.js',import.meta.url),'utf8'),context);vm.runInContext('pushIdentity=async() => "'+uid+'"',context);
 let done;handlers.push({data:{json:()=>({id:'notice',userId:uid,event:'warehouse_new',jobId:1})},waitUntil:p=>done=p});await done;
 assert.equal(shown[0].o.silent,false);assert.equal(shown[0].o.renotify,true);assert.equal(shown[0].o.vibrate[0],200);
 handlers.notificationclick({notification:{data:{userId:uid,event:'warehouse_ready',invoiceKind:'system',jobId:2},close(){}},waitUntil:p=>done=p});await done;
 assert.equal(new URL(opened[0]).searchParams.get('section'),'installations');
});
