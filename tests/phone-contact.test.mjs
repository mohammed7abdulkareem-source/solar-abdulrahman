import test from 'node:test';
import assert from 'node:assert/strict';
import {contactPhoneLinks,splitContactPhones,phoneContactDocument} from '../app/phone-contact-utils.mjs';
import {salesDocument} from '../app/sales-document.mjs';
test('Iraqi mobile numbers open the same WhatsApp recipient for local, international and Arabic digits',()=>{
 for(const input of ['07744442802','٠٧٧٤٤٤٤٢٨٠٢','۰۷۷۴۴۴۴۲۸۰۲','+964 774 444 2802','00964 7744442802','7744442802','+964 (0)7744442802'])assert.equal(contactPhoneLinks(input).whatsapp,'https://wa.me/9647744442802',input);
 assert.equal(contactPhoneLinks('07744442802').call,'tel:07744442802');assert.equal(contactPhoneLinks('+44 7700 900123').whatsapp,'https://wa.me/447700900123');
});
test('separate saved numbers stay separate and unsafe/incomplete values never become contact links',()=>{
 assert.deepEqual(splitContactPhones('07744442802 / 07801234567، +447700900123'),['07744442802','07801234567','+447700900123']);for(const x of ['',null,'07','00000000','javascript:alert(1)','07744<script>42802'])assert.equal(contactPhoneLinks(x),null);
 const html=phoneContactDocument('07744442802 / 07801234567');assert.equal((html.match(/https:\/\/wa.me\//g)||[]).length,2);assert.ok(!html.includes('?text='));assert.ok(phoneContactDocument('<script>').includes('&lt;script&gt;'));assert.ok(!phoneContactDocument('<script>').includes('<script>'));
});
test('original invoice phones retain customer/responsible placement and gain compact contact symbols',()=>{
 const d=salesDocument({kind:'sale',party_name:'الزبون',customer_phone:'07744442802',creatorName:'المسؤول',creatorPhone:'07801234567',total:1000,items:[]});
 const customer=d.body.match(/<div class="invoiceCustomerContact">([\s\S]*?)<div class="invoiceSellerContact">/)[1],seller=d.body.split('<div class="invoiceSellerContact">')[1];assert.ok(customer.includes('tel:07744442802'));assert.ok(customer.includes('https://wa.me/9647744442802'));assert.ok(!customer.includes('07801234567'));assert.ok(seller.includes('tel:07801234567'));assert.ok(seller.includes('https://wa.me/9647801234567'));assert.ok(d.body.includes('width="13" height="13"'));
});
