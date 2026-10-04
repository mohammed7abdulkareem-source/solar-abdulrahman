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
