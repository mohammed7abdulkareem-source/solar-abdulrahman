import test from 'node:test';
import assert from 'node:assert/strict';
import {materialsByCode,baghdadDay,canReadPaymentKind,recordPage} from '../app/record-browser-utils.mjs';
import {canOpenPage} from '../app/access-utils.mjs';
test('material navigation follows numeric codes including Arabic digits without changing the source',()=>{
 const rows=[{id:10,code:'0010'},{id:2,code:'٠٠٠٢'},{id:1,code:'0001'},{id:3,code:'0003'}];
 assert.deepEqual(materialsByCode(rows).map(r=>r.id),[1,2,3,10]);assert.equal(rows[0].id,10);
});
test('single record navigation crosses page boundaries and clamps the first/last position',()=>{
 assert.deepEqual(recordPage(30,67),{position:30,offset:30,index:0});assert.deepEqual(recordPage(29,67),{position:29,offset:0,index:29});assert.deepEqual(recordPage(100,67),{position:66,offset:60,index:6});assert.deepEqual(recordPage(-1,67),{position:0,offset:0,index:0});assert.deepEqual(recordPage(0,0),{position:0,offset:0,index:0});
});
test('today changes at Baghdad midnight for receipt filtering',()=>{
 assert.equal(baghdadDay('2026-10-24T20:59:59Z'),'2026-10-24');assert.equal(baghdadDay('2026-10-24T21:00:00Z'),'2026-10-25');
});
test('payment history inherits only existing read capabilities and rejects special roles',()=>{
 const user={active:true,id:'owner',user_type:'admin_staff',permissions:{customerPayment:true}};
 assert.equal(canReadPaymentKind(user,'customer_payment'),true);assert.equal(canReadPaymentKind(user,'supplier_payment'),false);assert.equal(canReadPaymentKind(user,'system_payment'),false);assert.equal(canOpenPage(user,'paymentHistory'),true);
 for(const type of ['installer','warehouse'])assert.equal(canOpenPage({...user,user_type:type,is_admin:true},'paymentHistory'),false);
 assert.equal(canOpenPage({...user,permissions:{}},'paymentHistory'),false);
});
