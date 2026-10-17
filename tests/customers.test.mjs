import test from 'node:test';
import assert from 'node:assert/strict';
import {customerNameKey,customerPhoneKey,customerMatches,formatAmountInput,amountInput,filteredCustomers,validOpening} from '../app/customer-utils.mjs';
test('opening amounts use thousands separators and retain typed decimals',()=>{
 assert.equal(formatAmountInput('2000000'),'2,000,000');assert.equal(formatAmountInput('1200000.50'),'1,200,000.50');assert.equal(formatAmountInput('1200.'),'1,200.');assert.equal(formatAmountInput(''),'');
 assert.equal(amountInput('٢٬٠٠٠٬٠٠٠٫٥٠'),'2000000.50');assert.equal(amountInput('۲,۰۰۰,۰۰۰'),'2000000');
 assert.ok(validOpening(-2500000));assert.ok(!validOpening(Infinity));assert.ok(!validOpening('NaN'));assert.ok(!validOpening(1.001));
});
test('customer names ignore spacing, harakat, Arabic variants and hidden characters',()=>{
 assert.equal(customerNameKey('أَحْمَد  عَلي'),customerNameKey('احمد علي'));assert.equal(customerNameKey('عبد الرحمن'),customerNameKey('عبدالرحمن'));assert.equal(customerNameKey('علي\u200f حسن'),customerNameKey('علي حسن'));
});
test('Iraqi telephone formats map to the same customer without matching empty phones',()=>{
 for(const phone of ['07701234567','٠٧٧٠١٢٣٤٥٦٧','+964 770 123 4567','00964 0770 1234567','7701234567'])assert.equal(customerPhoneKey(phone),'9647701234567');
 assert.equal(customerPhoneKey(''),'');assert.equal(customerPhoneKey('123'),'');
});
test('duplicate lookup excludes the customer currently being edited',()=>{
 const rows=[{id:1,name:'احمد علي',phone:'07701234567'},{id:2,name:'سيف حسن',phone:''}];
 assert.equal(customerMatches(rows,'أحمد علي','').length,1);assert.equal(customerMatches(rows,'اسم مختلف','+9647701234567').length,1);assert.equal(customerMatches(rows,'أحمد علي','07701234567',1).length,0);assert.equal(customerMatches(rows,'','').length,0);
});
test('directory searches Arabic names, phone aliases and correct account directions',()=>{
 const rows=[{name:'أحمد علي',phone:'07701234567',customerType:'system',balance:2000000},{name:'سيف حسن',phone:'',customerType:'wholesale',balance:-150000},{name:'مؤيد',customerType:'system',balance:0}];
 assert.equal(filteredCustomers(rows,'احمد').length,1);assert.equal(filteredCustomers(rows,'+9647701234567').length,1);assert.equal(filteredCustomers(rows,'','all','credit')[0].name,'سيف حسن');assert.equal(filteredCustomers(rows,'','system','zero')[0].name,'مؤيد');
});
