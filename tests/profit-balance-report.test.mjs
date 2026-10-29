import test from 'node:test';
import assert from 'node:assert/strict';
import {profitBalanceReport} from '../app/profit-balance-report.mjs';

test('PDF distinguishes the zero current balance from historical profit settled in full',()=>{
 const html=profitBalanceReport({balance:{remaining:0,period:{earned:7535136.32,settled:7535136.32,available:0}},ownerName:'سفيان <script>',from:'2026-10-01',to:'2026-10-29',rows:[{date:'2026-10-20T09:00:00Z',kind:'sale',party:'الزبون & شركاؤه',sales:10000000,cost:2464863.68,earned:7535136.32,settled:7535136.32,available:0}],expenses:0,fx:0,externalProfit:0});
 assert.match(html,/الأرباح المتبقية بعد التسوية: 0 د.ع/);
 assert.match(html,/ربح الفترة قبل التسويات: 7,535,136\.32/);
 assert.match(html,/المسوّى من أرباح الفترة: 7,535,136\.32/);
 assert.match(html,/غير المسوّى من أرباح الفترة: 0/);
 assert.match(html,/المسوّى<\/th><th>غير المسوّى/);
 assert.ok(html.includes('&lt;script&gt;')&&html.includes('&amp;'));
 assert.ok(!html.includes('<script>'));
});
test('unconfirmed balances produce no report; negative actual profits remain visible',()=>{
 assert.equal(profitBalanceReport({balance:null}),'');
 const html=profitBalanceReport({balance:{remaining:-40000,period:{earned:100000,settled:140000,available:-40000}},ownerName:'المستخدم',rows:[],expenses:0,fx:0,externalProfit:0});
 assert.match(html,/بعد التسوية: -40,000 د.ع/);
});
