import test from 'node:test';
import assert from 'node:assert/strict';
import {userDisplayName,normalizeHonorific,validHonorific} from '../app/user-name-utils.mjs';
import {warrantyDocument} from '../app/warranty-utils.mjs';
test('honorifics prefix names, remain optional, and never repeat an existing title',()=>{
 assert.equal(userDisplayName({display_name:'صفاء',username:'safaa',honorific:'المهندس'}),'المهندس صفاء');
 assert.equal(userDisplayName({display_name:'المهندس صفاء',honorific:'المهندس'}),'المهندس صفاء');
 assert.equal(userDisplayName({username:'safaa',honorific:''}),'safaa');assert.equal(userDisplayName(null),'مستخدم');
 assert.equal(normalizeHonorific('  المهندس  الاستشاري  '),'المهندس الاستشاري');
 assert.ok(validHonorific('الإداري'));assert.ok(validHonorific(''));assert.ok(!validHonorific('<img>'));assert.ok(!validHonorific('أ'.repeat(51)));
});
test('warranty rows carry the same brand/category as invoice items; unset maintenance has no row or no-warranty label',()=>{
 for(const maintenance of [undefined,{duration:0,unit:'months'},{duration:'',unit:'months'}]){
  const html=warrantyDocument({created_at:'2026-10-27',items:[{product_id:1,product_name:'انفيرتر',brand_name:'DEYE <test>',category:'انفيرتر'}],warranty:{enabled:true,items:[{id:1,duration:5,unit:'years'}],maintenance}});
  assert.match(html,/DEYE &lt;test&gt; • انفيرتر/);assert.match(html,/5 سنة/);assert.ok(!html.includes('ضمان الصيانة'));assert.ok(!html.includes('بدون ضمان'));assert.ok(!html.includes('<test>'));
 }
 const html=warrantyDocument({created_at:'2026-10-27',items:[{id:1,name:'بطارية',brand:'FULLMAX',category:'بطارية'}],warranty:{enabled:true,items:[{id:1,duration:1,unit:'years'}],maintenance:{duration:6,unit:'months'}}});
 assert.match(html,/FULLMAX • بطارية/);assert.match(html,/ضمان الصيانة/);assert.match(html,/6 شهر/);
});
