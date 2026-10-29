import test from'node:test';
import assert from'node:assert/strict';
import{cashHandoverDocument}from'../app/cash-handover-document.mjs';
import{cashMovementBody}from'../app/cash-movement-utils.mjs';
test('handover receipt identifies both cashboxes and shows the actual before/after currency',()=>{
 const doc=cashHandoverDocument({receiptNo:8,date:'2026-10-29T12:00Z',senderName:'A & B',recipientName:'<img>',actorName:'مدير',currency:'USD',amount:20,beforeUSD:100,afterUSD:80,beforeRecipientUSD:5,afterRecipientUSD:25,note:'تحويل <script>'});
 for(const word of['A &amp; B','&lt;img&gt;','&lt;script&gt;','100','80','25','20 $'])assert.ok(doc.includes(word),word);assert.ok(!doc.includes('<img>'));
});
test('USD transfer detail uses dollars while the historical IQD transfer remains dinars',()=>{
 const base={currency:'USD',date:'2026-10-29T12:00Z',before:100,amount:20,after:80,delta:-20,transfer:{sender:'A',recipient:'B',amount:20,currency:'USD',status:'accepted',note:'تسليم'}};
 assert.ok(cashMovementBody(base,'تسليم مباشر صادر').includes('مبلغ التسليم: 20 $'));
 assert.ok(cashMovementBody({...base,transfer:{...base.transfer,currency:undefined}},'تحويل صادر').includes('مبلغ التسليم: 20 د.ع'));
});
