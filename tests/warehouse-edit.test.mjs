import test from 'node:test';
import assert from 'node:assert/strict';
import {warehouseCapacity,warehouseEditError,warehouseEditPayload} from '../app/warehouse-edit-utils.mjs';
test('warehouse edits use free stock in the selected location plus the booked invoice quantity',()=>{
 const products=[{id:1,qty:2},{id:2,qty:0}],booked=[{lineId:10,productId:'1',qty:3,name:'A'}];
 assert.equal(warehouseCapacity(products,booked,1),5);
 assert.equal(warehouseEditError([{productId:1,qty:5,name:'A'}],products,booked),'');
 assert.match(warehouseEditError([{productId:1,qty:3,name:'A'},{productId:'1',qty:3,name:'A'}],products,booked),/أكبر/);
 assert.match(warehouseEditError([{productId:2,qty:1,name:'B'}],products,booked),/أكبر/);
 for(const qty of ['',0,-1,Infinity,'NaN',.0001,1000001])assert.ok(warehouseEditError([{productId:1,qty,name:'A'}],products,booked));
 assert.equal(warehouseEditError([{productId:1,qty:1.125,name:'A'}],products,booked),'');
 assert.deepEqual(warehouseEditPayload([{lineId:10,productId:1,qty:'2',price:999},{productId:2,qty:'1'}]),[{lineId:10,productId:1,qty:2},{lineId:null,productId:2,qty:1}]);
});
