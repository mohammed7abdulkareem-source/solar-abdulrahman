import test from 'node:test';
import assert from 'node:assert/strict';
import {filterBalances,balancesTotal,balancesDocument,balanceDate} from '../app/party-balances-utils.mjs';
import {canOpenPage} from '../app/access-utils.mjs';
const rows=[{id:1,name:'أحمد',phone:'07701234567',customer_type:'wholesale',balance:1200,last_payment:500,last_payment_at:'2026-10-04T22:00:00Z'}, {id:2,name:'منظومة',customer_type:'system',balance:400}, {id:3,name:'رصيد دائن',customer_type:'system',balance:-100}];
test('checkboxes independently include wholesale and systems; totals match visible rows',()=>{
 assert.equal(balancesTotal(filterBalances(rows)),1600);
 assert.equal(balancesTotal(filterBalances(rows,{systems:false})),1200);
 assert.equal(balancesTotal(filterBalances(rows,{wholesale:false})),400);
 assert.deepEqual(filterBalances(rows,{wholesale:false,systems:false}),[]);
 assert.equal(filterBalances(rows,{query:'احمد'})[0].id,1);
 assert.equal(filterBalances(rows,{query:'٠٧٧٠١٢٣٤٥٦٧'})[0].id,1);
});
test('supplier negative advances are available only with due filter unchecked',()=>{
 assert.equal(filterBalances(rows,{mode:'suppliers'}).length,2);
 assert.equal(balancesTotal(filterBalances(rows,{mode:'suppliers',dueOnly:false})),1500);
});
test('PDF shares exactly selected rows/columns and safely escapes names',()=>{
 const options={asOf:'2026-10-05',scope:'عملاؤك',systems:false};
 const html=balancesDocument(filterBalances(rows,options),options);
 assert.ok(html.includes('أحمد'));assert.ok(!html.includes('منظومة'));assert.ok(!html.includes('<th>الهاتف</th>'));assert.ok(!html.includes('<th>النوع</th>'));
 const extra=balancesDocument([{...rows[0],name:'<script>x</script>'}],{...options,showPhone:true,showType:true});
 assert.ok(extra.includes('&lt;script&gt;'));assert.ok(!extra.includes('<script>'));assert.ok(extra.includes('07701234567'));assert.ok(extra.includes('05/10/2026'));
});
test('reports require their own permissions and never allow warehouse/engineer or inactive profiles',()=>{
 const p={active:true,user_type:'admin_staff',permissions:{customerDebts:true}};
 assert.equal(canOpenPage(p,'customerDebts'),true);assert.equal(canOpenPage(p,'supplierBalances'),false);
 for(const user_type of ['installer','warehouse'])for(const page of ['customerDebts','supplierBalances'])assert.equal(canOpenPage({...p,user_type,is_admin:true},page),false);
 assert.equal(canOpenPage({...p,active:false},'customerDebts'),false);
 assert.equal(balanceDate(null),'—');
});
