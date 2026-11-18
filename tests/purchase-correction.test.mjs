import test from 'node:test';
import assert from 'node:assert/strict';
import {purchaseCorrectionReady,purchaseCorrectionMatches,purchaseCorrectionSignature,purchaseCorrectionLines,purchaseCorrectionError,purchaseCorrectionNumber,purchaseCorrectionSigned,purchaseEditRate} from '../app/purchase-correction.mjs';
import {invoicePayload} from '../app/currency-utils.mjs';
import {saveInvoiceAttempt,restoreInvoiceAttempt} from '../app/invoice-attempt.mjs';

const original={id:419,pricingRevision:2,sourceCurrency:'USD',items:[{id:7,name:'لوح',qty:10,price:150000,sourcePrice:100},{id:8,name:'بطارية',qty:2,price:300000,sourcePrice:200}]};
const payload=invoicePayload('purchase',{party:'مورد',partyId:8,mode:'credit',sourceCurrency:'USD',exchangeRate:1500,marketRate:1500,cashCurrency:'IQD',warehouseId:3,expenses:0,notes:''},[{id:7,qty:8,price:90},{id:8,qty:2,price:200}],original);
const amount={total:2100000,sourceSubtotal:1400,expenses:0,accountAmount:1400,accountCurrency:'USD',cashAmount:0,cashCurrency:'IQD'};
const response=()=>({invoiceId:419,receiptNo:41,pricingRevision:2,token:'server-preview-token',changed:true,materialScope:'changed',changedProductIds:[7,8],requiresCorrection:true,canApply:true,blockedReason:null,locks:{supplier:true,warehouse:true,paymentMode:true,sourceCurrency:true,exchangeRate:true,cashCurrency:true},before:amount,after:{...amount,total:1680000,sourceSubtotal:1120,accountAmount:1120},delta:{total:-420000,accountAmount:-280,cashAmount:0},items:[{id:7,name:'لوح',before:{qty:6,cost:150000},after:{qty:4,cost:135000},quantityDelta:-2,bookValueDelta:-360000,availableBefore:6,availableAfter:4},{id:8,name:'بطارية',before:{qty:2,cost:300000},after:{qty:2,cost:300000},quantityDelta:0,bookValueDelta:0,availableBefore:2,availableAfter:2}],affectedSales:{count:1,profitBefore:100000,profitAfter:160000,profitDelta:60000},paymentsPreserved:true,unrelatedMaterialsPreserved:true});

test('preview is bound to exact original revision, draft, actor authorization and invoice',()=>{
 const data=response(),review={data,scope:'actor-A:admin',signature:purchaseCorrectionSignature(payload)};
 assert.equal(purchaseCorrectionReady(data,payload),true);
 assert.equal(purchaseCorrectionMatches(review,payload,'actor-A:admin'),true);
 for(const candidate of [{...payload,invoiceId:420},{...payload,expectedRevision:3},{...payload,notes:'تغيير'},{...payload,items:[{id:7,qty:9,price:90},{id:8,qty:2,price:200}]}])assert.equal(purchaseCorrectionMatches(review,candidate,'actor-A:admin'),false);
 assert.equal(purchaseCorrectionMatches(review,payload,'actor-A:ordinary'),false);
 assert.equal(purchaseCorrectionMatches(review,payload,'actor-B:admin'),false);
});
test('a blocked plan shows its true reason without invented inventory or invoice amounts',()=>{
 const data={...response(),canApply:false,blockedReason:'المتاح لا يكفي لتخفيض الكمية.',after:null,items:[]};
 assert.equal(purchaseCorrectionReady(data,payload),true);
 assert.equal(purchaseCorrectionReady({...data,blockedReason:''},payload),false);
 assert.equal(purchaseCorrectionReady({...data,invoiceId:500},payload),false);
});
test('successful plans fail closed on missing effects, mismatched materials or unsafe preservation promises',()=>{
 for(const change of [{after:null},{items:[response().items[0]]},{items:[response().items[0],response().items[0]]},{changedProductIds:[7,8,9]},{materialScope:null},{affectedSales:null},{affectedSales:{count:1,profitBefore:null,profitAfter:2,profitDelta:2}},{paymentsPreserved:false},{unrelatedMaterialsPreserved:false},{delta:{total:0,accountAmount:0,cashAmount:null}}])assert.equal(purchaseCorrectionReady({...response(),...change},payload),false);
 for(const cashAmount of [false,[],' '])assert.equal(purchaseCorrectionReady({...response(),delta:{total:0,accountAmount:0,cashAmount}},payload),false);
});
test('changed-material scope accepts empty pristine context, a declared affected subset and removed original materials only',()=>{
 const empty={...response(),changed:false,changedProductIds:[],items:[]};
 assert.equal(purchaseCorrectionReady(empty,payload),true);
 const subset={...response(),changedProductIds:[7],items:[response().items[0]]};
 assert.equal(purchaseCorrectionReady(subset,payload),true);
 const removed={...payload,items:[{id:8,qty:2,price:200}]};
 assert.equal(purchaseCorrectionReady(subset,removed),false);
 assert.equal(purchaseCorrectionReady(subset,removed,[7,8]),true);
 const foreign={...subset,changedProductIds:[9],items:[{...subset.items[0],id:9}]};
 assert.equal(purchaseCorrectionReady(foreign,payload,[7,8]),false);
 assert.equal(purchaseCorrectionReady({...subset,changed:false},payload),false);
});
test('quantity/price comparisons use original invoice snapshots, not present inventory cost or quantities',()=>{
 const lines=purchaseCorrectionLines(original,payload);
 assert.deepEqual(lines[0],{id:'7',name:'لوح',beforeQty:10,afterQty:8,beforePrice:100,afterPrice:90,changed:true});
 assert.equal(lines[1].changed,false);
 const removed=purchaseCorrectionLines(original,{items:[{id:9,qty:.125,price:22}]});
 assert.equal(removed[0].afterQty,0);assert.equal(removed[0].afterPrice,null);
 assert.equal(removed[2].beforeQty,0);assert.equal(removed[2].beforePrice,null);assert.equal(removed[2].afterQty,.125);
});
test('canonical purchase token is forwarded only for an edited purchase and does not alter its business signature',()=>{
 const meta={purchaseCorrectionToken:'new-token',sourceCurrency:'IQD',mode:'credit'};
 const edit=invoicePayload('purchase',meta,[],original);
 assert.equal(edit.purchaseCorrectionToken,'new-token');
 assert.equal(invoicePayload('purchase',meta,[]).purchaseCorrectionToken,undefined);
 assert.equal(invoicePayload('sale',meta,[],original).purchaseCorrectionToken,undefined);
 assert.equal(purchaseCorrectionSignature({...payload,purchaseCorrectionToken:'first'}),purchaseCorrectionSignature({...payload,purchaseCorrectionToken:'second'}));
});
test('lost correction acknowledgment replays identical original token and request ID after refreshed preview and reload',async()=>{
 const values=new Map(),storage={getItem:key=>values.get(key),setItem:(key,value)=>values.set(key,value),removeItem:key=>values.delete(key)};
 const uid='purchase-owner',requestId='00000000-0000-0000-0000-000000000419',sent=[];
 const options={storage,currentUser:async()=>uid,uuid:()=>requestId,resolve:()=>assert.fail('same correction must replay'),send:async record=>{sent.push(structuredClone(record));return sent.length===1?{error:{code:'',message:'Lost ACK'}}:{data:{id:419,receiptNo:41}};}};
 const attempt={current:null};await assert.rejects(saveInvoiceAttempt(attempt,uid,{...payload,purchaseCorrectionToken:'original-token'},options));
 const reloaded={current:null};restoreInvoiceAttempt(reloaded,uid,storage);
 await saveInvoiceAttempt(reloaded,uid,{...payload,purchaseCorrectionToken:'refreshed-token'},options);
 assert.equal(sent.length,2);assert.equal(sent[0].requestId,sent[1].requestId);assert.deepEqual(sent[0].payload,sent[1].payload);assert.equal(sent[1].payload.purchaseCorrectionToken,'original-token');assert.equal(values.size,0);
});
test('revision conflicts provide inline recovery guidance and preserve small numeric deltas',()=>{
 assert.match(purchaseCorrectionError({code:'PT409',message:'تغير المخزون.'}),/تغير المخزون.*أعد معاينة/);
 assert.equal(purchaseCorrectionNumber(null),'—');assert.equal(purchaseCorrectionNumber(-0),'0');assert.equal(purchaseCorrectionNumber(.0004),'0.0004');
 assert.equal(purchaseCorrectionSigned(-.125),'− 0.125');assert.equal(purchaseCorrectionSigned(.0004),'+ 0.0004');
});
test('editing preserves every valid saved market rate including IQD rate one',()=>{
 assert.equal(purchaseEditRate({sourceCurrency:'IQD',marketRate:1},1660),'1');
 assert.equal(purchaseEditRate({sourceCurrency:'USD',marketRate:1500,exchangeRate:1500},1660),'1500');
 assert.equal(purchaseEditRate({sourceCurrency:'USD',exchangeRate:1400},1660),'1400');
 assert.equal(purchaseEditRate({sourceCurrency:'IQD'},1660),'1660');
 assert.equal(purchaseEditRate({sourceCurrency:'IQD'},null),'');
});
