import test from 'node:test';
import assert from 'node:assert/strict';
import {createNoticeTracker} from '../app/notification-sound.mjs';
test('new notifications alert once across realtime and poll, without replaying old history',()=>{
 const seen=createNoticeTracker();seen.baseline([{id:'old'}]);
 assert.deepEqual(seen.receive([{id:'new',event:'warehouse_new'}]).map(n=>n.id),['new']);
 assert.deepEqual(seen.receive([{id:'old'},{id:'new'}]),[]);
 assert.deepEqual(seen.receive([{id:'newer'},{id:'new'}]).map(n=>n.id),['newer']);
 const cold=createNoticeTracker();assert.deepEqual(cold.receive([{id:'old'}]),[]);
});
