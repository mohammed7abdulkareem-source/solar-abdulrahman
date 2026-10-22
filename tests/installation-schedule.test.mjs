import test from 'node:test';
import assert from 'node:assert/strict';
import {installationStages,installationIndex,installationWeek,installationStart,installationLocalDay,installationTime,installationConflict,installationSlotsForDay,bookingSelectionKey} from '../app/installation-utils.mjs';
const slot=(day,time)=>{const start=installationStart(day,time);return {start:new Date(start).toISOString(),end:new Date(start+6*3600000).toISOString()};};
test('one canonical stage sequence covers office and engineer completion',()=>{assert.equal(installationStages.length,4);assert.deepEqual(installationStages.map(([s])=>installationIndex(s)),[0,1,2,3]);assert.equal(installationStages[3][1],'ملف مغلق');});
test('a six-hour booking blocks overlaps and permits exact adjacent endpoints',()=>{const slots=[slot('2026-10-26','10:00')];for(const t of ['04:01','09:00','10:00','15:59'])assert.ok(installationConflict(slots,'2026-10-26',t),t);for(const t of ['04:00','16:00','23:59'])assert.equal(installationConflict(slots,'2026-10-26',t),undefined,t);});
test('Baghdad time, midnight and next-day bookings remain one interval',()=>{const slots=[slot('2026-10-26','22:00')];assert.ok(installationConflict(slots,'2026-10-27','03:59'));assert.equal(installationConflict(slots,'2026-10-27','04:00'),undefined);assert.equal(installationSlotsForDay(slots,'2026-10-26').length,1);assert.equal(installationSlotsForDay(slots,'2026-10-27').length,1);assert.equal(installationSlotsForDay(slots,'2026-10-28').length,0);assert.equal(installationTime(slots[0].end),'04:00');assert.equal(installationLocalDay(slots[0].end),'2026-10-27');});
test('week spans Saturday to Friday even across month boundary',()=>{assert.deepEqual(installationWeek('2026-11-02'),['2026-10-31','2026-11-01','2026-11-02','2026-11-03','2026-11-04','2026-11-05','2026-11-06']);});
test('selection validity cannot carry over another engineer, time or edited invoice',()=>{const key=bookingSelectionKey('2026-10-26','one','10:00',8);assert.notEqual(key,bookingSelectionKey('2026-10-26','two','10:00',8));assert.notEqual(key,bookingSelectionKey('2026-10-26','one','16:00',8));assert.notEqual(key,bookingSelectionKey('2026-10-26','one','10:00',9));assert.equal(bookingSelectionKey('','','',null),bookingSelectionKey('','',''));});

import {installationMatchesStatus} from '../app/installation-utils.mjs';
test('status shortcuts use the same scope for counts and visible jobs, including active appointments today',()=>{
 const day='2026-10-23',jobs=[{id:1,installDate:day,installationStatus:'pending'},{id:2,installDate:day,installationStatus:'in_progress'},{id:3,installDate:'2026-10-24',installationStatus:'completed'},{id:4,installDate:day,installationStatus:'closed'},{id:5,installationStatus:'pending'}];
 const ids=status=>jobs.filter(j=>installationMatchesStatus(j,status,day)).map(j=>j.id);
 assert.deepEqual(ids('today'),[1,2]);assert.deepEqual(ids('in_progress'),[2]);assert.deepEqual(ids('completed'),[3]);assert.deepEqual(ids('closed'),[4]);assert.deepEqual(ids('open'),[1,2,3,5]);assert.deepEqual(ids('all'),[1,2,3,4,5]);
});
