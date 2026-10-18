import test from 'node:test';
import assert from 'node:assert/strict';
import jsQR from 'jsqr';
import {warrantyQrSvg,warrantyUrl,warrantyPolicy,warrantyError,warrantyDocument} from '../app/warranty-utils.mjs';
import {salesDocument} from '../app/sales-document.mjs';
import {invoicePayload} from '../app/currency-utils.mjs';
const token='12345678-1234-1234-1234-123456789abc';
test('printed QR modules decode to the exact live certificate link',()=>{
 const svg=warrantyQrSvg(token),n=Number(svg.match(/viewBox="0 0 (\d+)/)[1]),scale=8,width=n*scale,data=new Uint8ClampedArray(width*width*4).fill(255);
 for(const match of svg.matchAll(/M(\d+),(\d+)h1v1h-1z/g))for(let y=0;y<scale;y++)for(let x=0;x<scale;x++){const offset=((Number(match[2])*scale+y)*width+Number(match[1])*scale+x)*4;data[offset]=data[offset+1]=data[offset+2]=0;}
 assert.equal(jsQR(data,width,width).data,warrantyUrl(token));assert.equal(warrantyQrSvg('<script>'),'');
});
test('warranty follows current invoice materials and validates optional individual terms',()=>{
 const policy={enabled:true,items:[{id:1,duration:5,unit:'years'},{id:2,duration:12,unit:'months'}],maintenance:{duration:6,unit:'months'}};
 assert.deepEqual(warrantyPolicy(policy,[{id:2},{id:3}]).items.map(i=>[i.id,i.duration]),[[2,12],[3,'']]);
 assert.equal(warrantyError(policy,[{id:1}]),'');assert.ok(warrantyError({...policy,items:[],maintenance:{duration:'',unit:'months'}},[]));assert.ok(warrantyError({...policy,maintenance:{duration:1.5,unit:'years'}},[]));assert.equal(warrantyError({enabled:false},[]),'');
 assert.equal(invoicePayload('sale',{warranty:policy},[{id:1,qty:1,price:5}]).warranty,policy);
});
test('customer documents include approved QR and escaped warranty, drafts and warehouse copies do not claim approval',()=>{
 const row={kind:'sale',created_at:'2026-10-18',party_name:'عميل',items:[{product_id:1,product_name:'بطارية',qty:1,price:5}],warranty:{enabled:true,items:[{id:1,duration:2,unit:'years'}],maintenance:{duration:6,unit:'months'},notes:'<unsafe>'},warrantyToken:token};
 assert.ok(salesDocument(row).body.includes('<svg'));assert.ok(salesDocument(row).body.includes('&lt;unsafe&gt;'));assert.ok(!salesDocument(row,false).body.includes('رمز QR'));
 assert.ok(!warrantyDocument({...row,draft:true}).includes('<svg'));assert.ok(warrantyDocument({}).includes('بدون ضمان'));
});
