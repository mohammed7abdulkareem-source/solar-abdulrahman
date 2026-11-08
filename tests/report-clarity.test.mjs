import test from 'node:test';
import assert from 'node:assert/strict';
import {a4} from '../app/document-template.mjs';
import {isReportDocument} from '../app/report-clarity-style.mjs';
import {profitStatementDocument,profitStatementRows} from '../app/profit-statement-report.mjs';
import {profitBalanceReport} from '../app/profit-balance-report.mjs';

test('report typography covers report families and preserves specialized documents',()=>{
 for(const title of ['كشف حساب عميل','كشف الصندوق','تقرير رأس المال','أرصدة الموردين','كشف المخزون','حركة المواد','مبيعات الفترة','تفاصيل أرباح جملة','المنظومات غير المغلقة وحسابات العملاء']){
  assert.ok(isReportDocument(title));assert.match(a4(title,'<table></table>'),/class="sheet reportSheet"/);
 }
 for(const body of ['<section class="quoteDocument">','<section class="salesDocument">','<section class="customerReceiptDocument">']){
  assert.equal(isReportDocument('تقرير',body),false);
  assert.doesNotMatch(a4('تقرير',body),/class="sheet reportSheet/);
 }
 assert.match(a4('كشف حساب',''),/<html lang="ar" dir="rtl">/);
 assert.match(a4('مشتريات المورد','<section class="invoiceReport">'),/class="sheet reportSheet"/);
 assert.match(a4('مبيعات العميل','<section class="invoiceReport">'),/class="sheet reportSheet"/);
});

test('profit statement keeps zero current balance distinct from historical settled profit and escapes labels',()=>{
 const body=profitStatementDocument({ownerName:'<مالك & مشارك>',retainedProfit:0,available:0,rows:[{date:'2026-10-01',label:'فاتورة <مادة>',receiptNo:12,value:7535136.32,settled:7535136.32,available:0}]},'2026-10-01','2026-10-31');
 assert.match(body,/الرصيد المتبقي بعد التسوية: 0 د.ع/);
 assert.match(body,/ربح الفترة قبل التسويات<\/span><strong>7,535,136.32 د.ع/);
 assert.match(body,/المسوّى من أرباح الفترة<\/span><strong>7,535,136.32 د.ع/);
 assert.match(body,/غير المسوّى من أرباح الفترة<\/span><strong>0 د.ع/);
 assert.ok(body.includes('&lt;مالك &amp; مشارك&gt;'));assert.ok(body.includes('فاتورة &lt;مادة&gt; #12'));
 assert.match(body,/الدينار العراقي · IQD/);assert.match(body,/2026-10-01 — 2026-10-31/);
 const empty=profitStatementDocument({ownerName:'مالك',retainedProfit:-40,available:0,rows:[]},'','');
 assert.match(empty,/-40 د.ع/);assert.match(empty,/لا توجد حركات ضمن الفترة/);
});

test('settlement snapshot is explicitly historical and does not imply its stored available amount remains available now',()=>{
 const body=profitStatementRows([{label:'فاتورة',date:'2026-10-01',value:100,settled:0,available:100}],100,{snapshot:true});
 assert.match(body,/الربح المطلوب تسويته وقت الطلب/);assert.match(body,/هذه لقطة محفوظة للطلب، وليست الرصيد الحالي/);assert.match(body,/<b>100 د.ع<\/b>/);
});

test('company profit PDF records the sales filter and unavailable settlement amounts without inventing zero',()=>{
 const body=profitBalanceReport({balance:{remaining:-500,period:{earned:600,settled:100,available:500}},ownerName:'مالك',type:'system',from:'2026-01-01',to:'2026-02-01',rows:[{date:'2026-01-10',kind:'system',party:'عميل',receiptNo:99,sales:800,cost:200,earned:600,settled:null,available:null}],expenses:0,fx:-50,externalProfit:0});
 assert.match(body,/المبيعات: المنظومات المغلقة/);assert.match(body,/وصل #99/);assert.match(body,/<td><bdi dir="ltr" class="reportNumber">600<\/bdi><\/td><td>—<\/td><td>—<\/td>/);assert.match(body,/بعد التسوية: <bdi dir="ltr" class="reportNumber">-500<\/bdi> د.ع/);assert.match(body,/فرق الصرف المحقق<\/span><strong><bdi dir="ltr" class="reportNumber">-50<\/bdi> د.ع/);
});
