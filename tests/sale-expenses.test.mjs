import test from 'node:test';
import assert from 'node:assert/strict';
import {saleExpenseAmounts,saleExpensesOnCustomer,invoicePayload,purchaseAmounts} from '../app/currency-utils.mjs';
import {archiveInvoiceDraft} from '../app/invoice-edit-utils.mjs';
import {invoiceAttemptSignature,currentSaleItems} from '../app/inventory-valuation.mjs';
import {saveInvoiceAttempt,restoreInvoiceAttempt} from '../app/invoice-attempt.mjs';

const items=[{id:1,qty:2,price:500000,cost:350000}];
test('customer-paid wholesale expenses increase customer total with zero effect on invoice profit',()=>{
 const original=structuredClone(items),amounts=saleExpenseAmounts(items,40000,true);
 assert.equal(amounts.subtotal,1000000);assert.equal(amounts.total,1040000);assert.equal(amounts.cost,700000);assert.equal(amounts.profit,300000);
 assert.equal(amounts.billedExpenses,40000);assert.equal(amounts.internalExpenses,0);assert.equal(amounts.items[0].cost,350000);
 assert.equal(Object.hasOwn(amounts.items[0],'landedCost'),false);assert.deepEqual(items,original);
});
test('internal wholesale expenses leave customer total unchanged and reduce profit exactly once',()=>{
 const amounts=saleExpenseAmounts(items,40000,false);
 assert.equal(amounts.total,1000000);assert.equal(amounts.profit,260000);assert.equal(amounts.billedExpenses,0);assert.equal(amounts.internalExpenses,40000);
 assert.equal(saleExpenseAmounts(items,350000,false).profit,-50000);
});
test('decimal values, blank and zero expense keep explicit unchecked allocation',()=>{
 const decimal=[{id:1,qty:1.5,price:100.25,cost:60.5}];
 assert.equal(saleExpenseAmounts(decimal,10.25,true).total,160.63);assert.equal(saleExpenseAmounts(decimal,10.25,true).profit,59.63);
 assert.equal(saleExpenseAmounts(decimal,10.25,false).total,150.38);assert.equal(saleExpenseAmounts(decimal,10.25,false).profit,49.38);
 for(const expense of ['',0]){const value=saleExpenseAmounts(items,expense,false);assert.equal(value.expensesOnCustomer,false);assert.equal(value.total,1000000);assert.equal(value.profit,300000);}
 for(const invalid of [-1,Infinity,NaN,'oops'])assert.throws(()=>saleExpenseAmounts(items,invalid,false));
});
test('legacy and malformed stored flags keep original customer allocation, explicit false survives archive mapping',()=>{
 for(const record of [undefined,{}, {expenses_on_customer:null},{expensesOnCustomer:null},{expenses_on_customer:'false'},{expensesOnCustomer:0}])assert.equal(saleExpensesOnCustomer(record),true);
 for(const record of [{expensesOnCustomer:false},{expenses_on_customer:false}])assert.equal(saleExpensesOnCustomer(record),false);
 assert.equal(archiveInvoiceDraft({kind:'sale',expenses_on_customer:false,expenses:40,items:[]}).expensesOnCustomer,false);
 assert.equal(archiveInvoiceDraft({kind:'sale',expenses:40,items:[]}).expensesOnCustomer,true);
 assert.equal(Object.hasOwn(archiveInvoiceDraft({kind:'system',items:[]}), 'expensesOnCustomer'),false);
});
test('sale payload includes checked or unchecked responsibility and preserves stored allocation on an omitted edit',()=>{
 assert.equal(invoicePayload('sale',{expenses:40,expensesOnCustomer:false},items).expensesOnCustomer,false);
 assert.equal(invoicePayload('sale',{expenses:0,expensesOnCustomer:false},items).expensesOnCustomer,false);
 assert.equal(invoicePayload('sale',{},items).expensesOnCustomer,true);
 assert.equal(invoicePayload('sale',{expenses:40},items,{id:7,expenses_on_customer:false}).expensesOnCustomer,false);
 assert.equal(invoicePayload('sale',{expensesOnCustomer:true},items,{id:7,expenses_on_customer:false}).expensesOnCustomer,true);
 for(const kind of ['purchase','system'])assert.equal(Object.hasOwn(invoicePayload(kind,{expensesOnCustomer:false,expenses:40},items),'expensesOnCustomer'),false);
 const purchase=purchaseAmounts(items,'IQD',1,40000);assert.equal(purchase.total,1040000);assert.equal(purchase.items[0].landedCost,520000);
});
test('expense toggles retain frozen historical item costs and are distinct financial retry payloads',()=>{
 const historical=currentSaleItems(items,[{id:1,cost:999999}],items);
 assert.equal(saleExpenseAmounts(historical,40000,false).cost,700000);
 const checked=invoicePayload('sale',{expenses:40000,expensesOnCustomer:true},items),unchecked=invoicePayload('sale',{expenses:40000,expensesOnCustomer:false},items);
 assert.notEqual(invoiceAttemptSignature(checked),invoiceAttemptSignature(unchecked));
});
test('lost save acknowledgement replays the original expense flag; toggling requires resolving the prior receipt',async()=>{
 const values=new Map(),storage={getItem:key=>values.get(key)||null,setItem:(key,value)=>values.set(key,value),removeItem:key=>values.delete(key)},attempt={current:null};
 const checked=invoicePayload('sale',{expenses:40000,expensesOnCustomer:true},items),unchecked=invoicePayload('sale',{expenses:40000,expensesOnCustomer:false},items),nonce='00000000-0000-0000-0000-000000004140';
 await assert.rejects(saveInvoiceAttempt(attempt,'owner',checked,{storage,uuid:()=>nonce,send:async()=>({error:{code:'',message:'Lost response'}})}));
 const restored={current:null};restoreInvoiceAttempt(restored,'owner',storage);assert.equal(restored.current.payload.expensesOnCustomer,true);
 await assert.rejects(saveInvoiceAttempt(restored,'owner',unchecked,{storage,resolve:async record=>{assert.equal(record.payload.expensesOnCustomer,true);return {data:{state:'saved',invoice:{id:7,receiptNo:12,total:1040000}}};},send:()=>assert.fail('Changed allocation must not duplicate the committed sale')}),error=>error.invoiceRecovery?.invoice?.total===1040000);
 assert.equal(restored.current.requestId,nonce);assert.equal(restored.current.payload.expensesOnCustomer,true);
});
