import test from 'node:test';
import assert from 'node:assert/strict';
import {profitBalanceReport,companySaleExpenses} from '../app/profit-balance-report.mjs';

test('PDF distinguishes the zero current balance from historical profit settled in full',()=>{
 const html=profitBalanceReport({balance:{remaining:0,period:{earned:7535136.32,settled:7535136.32,available:0}},ownerName:'سفيان <script>',from:'2026-10-01',to:'2026-10-29',rows:[{date:'2026-10-20T09:00:00Z',kind:'sale',party:'الزبون & شركاؤه',sales:10000000,cost:2464863.68,earned:7535136.32,settled:7535136.32,available:0}],expenses:0,fx:0,externalProfit:0});
 assert.match(html,/الأرباح المتبقية بعد التسوية: <bdi dir="ltr" class="reportNumber">0<\/bdi> د.ع/);
 assert.match(html,/ربح الفترة قبل التسويات<\/span><strong><bdi dir="ltr" class="reportNumber">7,535,136\.32/);
 assert.match(html,/المسوّى من أرباح الفترة<\/span><strong><bdi dir="ltr" class="reportNumber">7,535,136\.32/);
 assert.match(html,/غير المسوّى من أرباح الفترة<\/span><strong><bdi dir="ltr" class="reportNumber">0/);
 assert.match(html,/المسوّى<\/th><th>غير المسوّى/);
 assert.ok(html.includes('&lt;script&gt;')&&html.includes('&amp;'));
 assert.ok(!html.includes('<script>'));
});
test('unconfirmed balances produce no report; negative actual profits remain visible',()=>{
 assert.equal(profitBalanceReport({balance:null}),'');
 const html=profitBalanceReport({balance:{remaining:-40000,period:{earned:100000,settled:140000,available:-40000}},ownerName:'المستخدم',rows:[],expenses:0,fx:0,externalProfit:0});
 assert.match(html,/بعد التسوية: <bdi dir="ltr" class="reportNumber">-40,000<\/bdi> د.ع/);
});

test('company invoice expenses are disclosed as already deducted without reducing earned or settlement balances twice',()=>{
 const balance={remaining:-100000,period:{earned:200000,settled:300000,available:-100000}};
 const rows=[{kind:'sale',expenses:100000,expensesOnCustomer:false,sales:1000000,cost:700000,earned:200000,settled:300000,available:-100000,date:'2026-11-17'},
  {kind:'sale',expenses:50000,expensesOnCustomer:true},{kind:'sale',expenses:7000},{kind:'system',expenses:9000,expensesOnCustomer:false}];
 assert.equal(companySaleExpenses(rows),100000);
 assert.equal(companySaleExpenses([{kind:'sale',expenses:100000,expenses_on_customer:false}]),100000);
 const snapshot=JSON.stringify(balance),html=profitBalanceReport({balance,rows:rows.slice(0,1),ownerName:'مالك',expenses:0,fx:0,externalProfit:0});
 assert.match(html,/مصاريف وصولات الجملة على الشركة: <bdi dir="ltr" class="reportNumber">100,000/);
 assert.match(html,/مخصومة ضمن ربح المبيعات المعروض، ولا تُطرح مرة أخرى/);
 assert.match(html,/ربح الفترة قبل التسويات<\/span><strong><bdi dir="ltr" class="reportNumber">200,000/);
 assert.match(html,/بعد التسوية: <bdi dir="ltr" class="reportNumber">-100,000/);
 assert.equal(JSON.stringify(balance),snapshot);
});
