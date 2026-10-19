import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeUserPhone,validUserPhone} from '../app/user-phone-utils.mjs';
import {salesDocument} from '../app/sales-document.mjs';
import {systemPaymentDocument} from '../app/system-payment-utils.mjs';
import {supplierDocument} from '../app/supplier-utils.mjs';
test('user phones accept local/international and Arabic digits without allowing markup or invalid lengths',()=>{
 for(const value of ['07701234567','٠٧٧٠ ١٢٣-٤٥٦٧','۰۷۷۰۱۲۳۴۵۶۷'])assert.equal(normalizeUserPhone(value),'07701234567');
 assert.equal(normalizeUserPhone('00964 (770) 123-4567'),'+9647701234567');
 for(const value of ['123','abc07701234567','<img>07701234567','077012345678901234','0770+1234567',''])assert.equal(validUserPhone(value),false);
});
test('customer, system and supplier receipts print the original creator contact with safe bidirectional text',()=>{
 const row={id:1,receiptNo:5,created_at:'2026-10-19',date:'2026-10-19',creatorName:'صاحب الوصل',creatorPhone:'+9647701234567',party:'عميل',party_name:'عميل',items:[],total:100000,sourceCurrency:'IQD'};
 for(const kind of ['sale','system'])for(const priced of [true,false])assert.match(salesDocument({...row,kind},priced).body,/<bdi dir="ltr">\+9647701234567<\/bdi>/);
 for(const ledgerType of ['system','wholesale'])assert.match(systemPaymentDocument({...row,ledgerType}).body,/\+9647701234567/);
 assert.match(supplierDocument({...row,kind:'supplier_payment'}).body,/\+9647701234567/);
 assert.doesNotMatch(salesDocument({...row,creatorPhone:'<script>bad</script>'}).body,/<script>/);
});
