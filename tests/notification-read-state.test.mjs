import test from 'node:test';
import assert from 'node:assert/strict';
import {notificationReadBoundary,mergeNotificationRows,markAllNotificationsRead,markNotificationIdsRead} from '../app/notification-read-state.mjs';

const before='2026-11-09T09:00:00.000+00:00',readAt='2026-11-09T09:01:00.000Z';
const id=n=>String(n).padStart(12,'0');
function fixture({total=275,pageCap=80,failSelect=0,failUpdate=0,beforeUpdate}={}){
 const rows=Array.from({length:total},(_,index)=>({id:id(index+1),user_id:'mine',created_at:before,read_at:null}));
 rows.push({id:id(9001),user_id:'other',created_at:before,read_at:null},{id:id(9002),user_id:'mine',created_at:before,read_at:'2026-11-01T00:00:00Z'});
 const calls=[];let selects=0,updates=0;
 const client={from(table){assert.equal(table,'solar_notifications');const query={filters:[],fields:'',patch:null,limitValue:Infinity,select(fields){this.fields=fields;return this;},update(patch){this.patch=patch;return this;},eq(field,value){this.filters.push(['eq',field,value]);return this;},is(field,value){this.filters.push(['is',field,value]);return this;},lte(field,value){this.filters.push(['lte',field,value]);return this;},gt(field,value){this.filters.push(['gt',field,value]);return this;},in(field,value){this.filters.push(['in',field,value]);return this;},order(){return this;},limit(value){this.limitValue=value;return this;},abortSignal(){return this;},then(resolve,reject){
  return Promise.resolve().then(()=>{
   const writing=!!this.patch;calls.push({writing,filters:this.filters,patch:this.patch});
   if(writing){updates++;beforeUpdate?.(rows,updates);if(updates===failUpdate)return{error:{message:'isolated write failure'}};}
   else if(++selects===failSelect)return{error:{message:'isolated page failure'}};
   let matches=rows.filter(row=>this.filters.every(([kind,field,value])=>kind==='in'?value.includes(row[field]):kind==='lte'?row[field]<=value:kind==='gt'?row[field]>value:row[field]===value)).sort((a,b)=>a.id.localeCompare(b.id));
   if(!writing)matches=matches.slice(0,Math.min(pageCap,this.limitValue));
   if(writing)for(const row of matches)Object.assign(row,this.patch);
   return{data:matches.map(row=>Object.fromEntries(this.fields.split(',').map(key=>[key,row[key]]))),error:null};
  }).then(resolve,reject);
 }};return query;}};
 return{client,rows,calls};
}

test('mark-all reads every own unread page, freezes IDs, and preserves a notification arriving during writes',async()=>{
 const f=fixture({beforeUpdate(rows,batch){if(batch===1)rows.push({id:id(9500),user_id:'mine',created_at:before,read_at:null});}}),confirmed=[];
 const result=await markAllNotificationsRead(f.client,{userId:'mine',before,readAt,onConfirmed:rows=>confirmed.push(...rows)});
 assert.deepEqual(result,{updatedCount:275,targetCount:275});assert.equal(confirmed.length,275);
 assert.equal(f.rows.filter(row=>row.user_id==='mine'&&!row.read_at).length,1);
 assert.equal(f.rows.find(row=>row.id===id(9500)).read_at,null);
 assert.equal(f.rows.find(row=>row.user_id==='other').read_at,null);
 assert.equal(f.rows.find(row=>row.id===id(9002)).read_at,'2026-11-01T00:00:00Z');
 assert.equal(f.calls.filter(call=>call.writing).length,3);
 for(const call of f.calls){assert.ok(call.filters.some(filter=>filter[0]==='eq'&&filter[1]==='user_id'&&filter[2]==='mine'));if(call.writing){assert.deepEqual(call.patch,{read_at:readAt});assert.ok(call.filters.find(filter=>filter[0]==='in')[2].length<=100);}}
 const replay=await markNotificationIdsRead(f.client,{userId:'mine',ids:confirmed.map(row=>row.id),readAt:'2026-11-10T00:00:00Z'});
 assert.equal(replay.updatedCount,0);assert.equal(f.rows[0].read_at,readAt);
});

test('selection failure performs no writes; partial update failure reports only confirmed rows and is safely retryable',async()=>{
 const unread=fixture({failSelect:2});await assert.rejects(markAllNotificationsRead(unread.client,{userId:'mine',before}),error=>error.message==='isolated page failure');
 assert.equal(unread.calls.filter(call=>call.writing).length,0);assert.equal(unread.rows.filter(row=>row.user_id==='mine'&&!row.read_at).length,275);
 const partial=fixture({failUpdate:2}),confirmed=[];
 await assert.rejects(markAllNotificationsRead(partial.client,{userId:'mine',before,readAt,onConfirmed:rows=>confirmed.push(...rows)}),error=>error.updatedCount===100&&error.targetCount===275);
 assert.equal(confirmed.length,100);assert.equal(partial.rows.filter(row=>row.user_id==='mine'&&!row.read_at).length,175);
 const retry=await markAllNotificationsRead(partial.client,{userId:'mine',before,readAt});assert.equal(retry.updatedCount,175);
});

test('reload merges late arrivals and confirmed reads without making new notices read or reviving stale unread rows',()=>{
 const original=[{id:'old',created_at:'2026-11-08T10:00:00Z',read_at:null},{id:'read',created_at:'2026-11-07T10:00:00Z',read_at:readAt}];
 const arrived=[{id:'new',created_at:'2026-11-09T10:00:00Z',read_at:null}];
 const result=mergeNotificationRows(original,arrived,new Map([['old',readAt]]));
 assert.deepEqual(result.map(row=>[row.id,row.read_at]),[['new',null],['old',readAt],['read',readAt]]);
 assert.equal(original[0].read_at,null);assert.equal(arrived[0].read_at,null);
 assert.equal(notificationReadBoundary(result),'2026-11-09T10:00:00Z');assert.equal(notificationReadBoundary([]),null);
});
