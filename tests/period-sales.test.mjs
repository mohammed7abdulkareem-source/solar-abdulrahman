import test from 'node:test';
import assert from 'node:assert/strict';
import {periodSalesDocument,periodKindLabel,periodDate} from '../app/period-sales-report.mjs';
test('period quantity document has no monetary columns and preserves three-decimal quantities',()=>{
 const doc=periodSalesDocument({asOf:'2026-10-24T12:00:00Z',from:'2026-10-01',to:'2026-10-24',scope:'own',kind:'',summary:{invoiceCount:44,materialCount:2,quantitySold:4.126},rows:[{name:'لوح <script>bad</script>',code:'0001',brand:'FULLMAX',category:'ألواح',quantitySold:1.126,remainingQty:.001},{name:'انفيرتر',code:'0002',brand:'',category:'',quantitySold:3,remainingQty:null}]});
 assert.equal(doc.total,'');assert.ok(doc.body.includes('العدد المبيوع'));assert.ok(doc.body.includes('المتبقي الحالي'));assert.ok(doc.body.includes('1.126'));assert.ok(doc.body.includes('0.001'));assert.ok(doc.body.includes('—'));assert.ok(doc.body.includes('&lt;script&gt;bad&lt;/script&gt;'));assert.ok(!doc.body.includes('<script>bad'));
 for(const label of ['سعر البيع','المبلغ','الكلفة','د.ع'])assert.ok(!doc.body.includes(label),label);
 assert.ok(doc.body.includes('data-pdf-paginate'));assert.ok(doc.body.includes('رصيد نهاية الفترة'));
});
test('report period labels identify the same sale filters without inferred dates',()=>{
 assert.equal(periodDate('2026-10-24'),'24/10/2026');assert.equal(periodKindLabel('sale'),'بيع جملة');assert.equal(periodKindLabel('system'),'بيع منظومات');assert.equal(periodKindLabel(''),'الجملة والمنظومات');
});
test('period PDF identifies and escapes the selected user',()=>{
 const doc=periodSalesDocument({asOf:'2026-10-27T10:00Z',ownerName:'الحاج سفيان <تجربة>',scope:'own',rows:[],summary:{}});assert.ok(doc.body.includes('المستخدم: الحاج سفيان &lt;تجربة&gt;'));assert.ok(!doc.body.includes('<تجربة>'));
});
