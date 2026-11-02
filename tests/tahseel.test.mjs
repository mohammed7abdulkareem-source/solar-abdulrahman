import test from 'node:test';
import assert from 'node:assert/strict';
import {newQuote,calculateQuote,quoteDocument,normalizeNumber} from '../app/tahseel-utils.mjs';
import {canOpenPage,canManageQuotes} from '../app/access-utils.mjs';
const complete=()=>({...newQuote(),day:'15',night:'15',batteryCapacity:'15',panel:{id:1,name:'لوح 600W',cost:'100000'},battery:{id:2,name:'بطارية 15 كيلو',cost:'2000000'},inverter:{id:3,name:'انفيرتر 6kW',cost:'500000'}});
const legacy=()=>({...complete(),schema:3,perPanel:'30000',expenses:{crane:'25000',worker:'20000',programmer:'35000',delivery:'25000',electrical:'150000'}});
test('15×15: 7 panels, one battery, 720,000 expenses including commission; 5% includes all costs',()=>{
 const q=calculateQuote(complete());
 assert.deepEqual([q.panelQty,q.batteryQty,q.materialsTotal,q.expensesTotal,q.cost,q.markup,q.price],[7,1,3200000,720000,3920000,196000,4116000]);
 assert.deepEqual(q.errors,[]);
});
test('quantities round UP without floating point error at a panel boundary',()=>{
 assert.equal(calculateQuote({...complete(),day:'15.05'}).panelQty,7);
 assert.equal(calculateQuote({...complete(),day:'15.06',night:'16'}).panelQty,8);
 assert.equal(calculateQuote({...complete(),night:'16'}).batteryQty,2);
});
test('zero night is allowed and has no battery cost, but an empty/invalid demand cannot be quoted',()=>{
 const q=calculateQuote({...complete(),night:'0',battery:null});assert.equal(q.batteryQty,0);assert.equal(q.materialsTotal,1200000);assert.equal(q.errors.length,0);
 for(const day of ['', '-1','NaN','Infinity','1001'])assert.ok(calculateQuote({...complete(),day}).errors.length);
 assert.ok(calculateQuote({...complete(),day:'0',night:'0'}).errors.length);
});
test('missing, negative or zero product cost cannot produce a final quotation',()=>{
 for(const cost of ['', '-1','0','Infinity'])assert.ok(calculateQuote({...complete(),panel:{name:'لوح',cost}}).errors.length);
 assert.throws(()=>quoteDocument(newQuote()));
});
test('editable expenses are counted and cannot be negative',()=>{
 const f=complete();f.expenses.crane='0';assert.equal(calculateQuote(f).expensesTotal,680000);
 f.expenses.crane='-1';assert.ok(calculateQuote(f).errors.length);
});
test('customer copy hides costs and markup, internal copy shows them; all free text escaped',()=>{
 const f=complete();f.customer='<script>alert(1)</script>';f.notes='<img src=x onerror=alert(1)>';f.panel.name='<b>panel</b>';
 const customer=quoteDocument(f),internal=quoteDocument(f,true);
 assert.ok(!customer.includes('<script>'));assert.ok(!customer.includes('<img'));assert.ok(customer.includes('&lt;b&gt;'));
 assert.ok(!customer.includes('196,000'));assert.ok(!customer.includes('2,000,000'));assert.ok(internal.includes('196,000'));assert.ok(internal.includes('2,000,000'));
});
test('Arabic decimal inputs normalize without changing value',()=>assert.equal(normalizeNumber('١٬٢٣٤٫٥'),'1234.5'));
test('quote permissions exclude engineers/warehouse/inactive and respect explicit false',()=>{
 const p={active:true,user_type:'admin_staff',permissions:{system:true}};
 assert.equal(canOpenPage(p,'tahseel'),true);
 assert.equal(canOpenPage({...p,permissions:{system:true,tahseel:false}},'tahseel'),false);
 assert.equal(canOpenPage({...p,permissions:{tahseel:true}},'tahseel'),true);
 for(const user_type of ['installer','warehouse'])assert.equal(canOpenPage({...p,user_type,is_admin:true},'tahseel'),false);
 assert.equal(canOpenPage({...p,active:false},'tahseel'),false);
});

test('new quotations start with empty day, night and capacity',()=>{
 const f=newQuote();assert.equal(f.day,'');assert.equal(f.night,'');assert.equal(f.batteryCapacity,'');assert.ok(calculateQuote(f).errors.length);
});
test('all shop battery combinations and rounding use the selected capacity',()=>{
 for(const [night,batteryCapacity,qty] of [[5,5,1],[7.5,7.5,1],[20,10,2],[50,25,2],[30,30,1],[30,15,2],[45,15,3],[16,7.5,3]]){
  const q=calculateQuote({...complete(),night:String(night),batteryCapacity:String(batteryCapacity)});
  assert.equal(q.batteryQty,qty);assert.equal(q.materials[1].total,qty*2000000);assert.deepEqual(q.errors,[]);
 }
});
test('capacity must be selected for night demand; zero night needs no battery',()=>{
 for(const batteryCapacity of ['', '0','-5','12','Infinity'])assert.ok(calculateQuote({...complete(),batteryCapacity}).errors.length);
 assert.deepEqual(calculateQuote({...complete(),night:'0',batteryCapacity:'',battery:null}).errors,[]);
});
test('legacy drafts retain their 15-kilo calculation and new drafts retain capacity on reload',()=>{
 const old={...legacy(),schema:1};delete old.batteryCapacity;assert.equal(calculateQuote(old).price,3848250);
 const f=JSON.parse(JSON.stringify({...complete(),night:'50',batteryCapacity:'25'}));assert.equal(calculateQuote(f).batteryQty,2);assert.ok(quoteDocument(f).includes('بطارية 25 كيلو'));
});

test('profit percentage supports presets, custom values, zero and legacy 5%',()=>{
 for(const rate of [0,5,10,12.5,15]){const form={...complete(),markupPercent:String(rate)},q=calculateQuote(form);assert.equal(q.price,3920000+Math.round(3920000*rate)/100);assert.deepEqual(q.errors,[]);assert.match(quoteDocument(form,true),new RegExp('إضافة '+rate+'%'));}
 const old=complete();delete old.markupPercent;assert.equal(calculateQuote(old).markupPercent,5);
 for(const rate of ['',-1,'NaN',Infinity,1001])assert.ok(calculateQuote({...complete(),markupPercent:rate}).errors.length);
});
test('full quote access is separate, explicit and excludes denied or special roles',()=>{
 const p={active:true,user_type:'admin_staff',permissions:{tahseel:true}};assert.equal(canManageQuotes(p),false);
 assert.equal(canManageQuotes({...p,permissions:{tahseel:true,tahseelFull:true}}),true);
 assert.equal(canManageQuotes({...p,is_admin:true}),true);
 for(const changes of [{active:false},{user_type:'warehouse'},{user_type:'installer'},{permissions:{tahseel:false,tahseelFull:true}}])assert.equal(canManageQuotes({...p,is_admin:false,permissions:{tahseel:true,tahseelFull:true},...changes}),false);
});

test('two or three selected inverters multiply unit cost, overall cost and markup in the quotation',()=>{
 for(const qty of [2,3]){
  const form={...complete(),inverterQty:String(qty)},q=calculateQuote(form),line=q.materials.find(x=>x.key==='inverter');
  assert.equal(line.qty,qty);assert.equal(line.total,500000*qty);
  assert.equal(q.cost,3920000+500000*(qty-1));assert.equal(q.price,q.cost+Math.round(q.cost*5)/100);assert.deepEqual(q.errors,[]);
  assert.match(quoteDocument(form),new RegExp('انفيرتر 6kW[\\s\\S]*?<td>'+qty+'</td>'));
  assert.match(quoteDocument(form,true),new RegExp('انفيرتر 6kW[\\s\\S]*?<td>'+qty+'</td><td>500,000</td><td>'+moneyForTest(500000*qty)+'</td>'));
 }
});
function moneyForTest(value){return Number(value).toLocaleString('en-US',{maximumFractionDigits:2});}
test('older missing inverter quantity remains one, while explicit invalid quantities cannot be exported',()=>{
 const old=legacy();delete old.inverterQty;assert.equal(calculateQuote(old).price,3848250);assert.equal(calculateQuote(old).inverterQty,1);
 for(const inverterQty of ['',0,-1,1.5,'NaN','Infinity',1001,null,true,[2],{},'2e0']){
  const form={...complete(),inverterQty};assert.ok(calculateQuote(form).errors.some(e=>e.includes('عدد الانفيرترات')),String(inverterQty));assert.throws(()=>quoteDocument(form));
 }
 const form=JSON.parse(JSON.stringify({...complete(),inverterQty:normalizeNumber('٣'),notes:'ثلاثة انفيرترات\nملاحظة <script> & تفاصيل'}));
 assert.equal(calculateQuote(form).inverterQty,3);
 for(const internal of[false,true]){const html=quoteDocument(form,internal);assert.ok(html.includes('ملاحظات العرض'));assert.ok(html.includes('ثلاثة انفيرترات<br>ملاحظة &lt;script&gt; &amp; تفاصيل'));}
});


test('ALL IN ONE uses only panels and integrated devices, with the same expenses and markup',()=>{
 const form={...complete(),systemType:'all_in_one',allInOneQty:'2',batteryCapacity:'',battery:null,inverter:null,allInOne:{id:5,name:'5KW/ALLINONE',brand:'FULLMAX',cost:'3500000'}};
 const q=calculateQuote(form);
 assert.deepEqual([q.panelQty,q.batteryQty,q.inverterQty,q.allInOneQty,q.materialsTotal,q.expensesTotal,q.price],[7,0,0,2,7700000,720000,8841000]);
 assert.deepEqual(q.materials.map(x=>x.key),['panel','allInOne']);assert.deepEqual(q.errors,[]);
 for(const html of [quoteDocument(form),quoteDocument(form,true)]){assert.match(html,/5KW\/ALLINONE[\s\S]*?<td>2<\/td>/);assert.ok(!html.includes('بطارية 15 كيلو'));}
 assert.ok(!quoteDocument(form).includes('3,500,000'));assert.ok(quoteDocument(form,true).includes('3,500,000'));
 for(const n of ['',0,-1,1.5,1001,'2e0',null])assert.ok(calculateQuote({...form,allInOneQty:n}).errors.some(e=>e.includes('ALL IN ONE')));
 assert.ok(calculateQuote({...form,allInOne:null}).errors.some(e=>e.includes('ALL IN ONE')));
 const manual={...form,day:'',night:'',allInOnePanelQty:'10'},m=calculateQuote(manual);
 assert.deepEqual([m.panelQty,m.expensesTotal,m.materialsTotal,m.price],[10,855000,8000000,9297750]);assert.deepEqual(m.errors,[]);
 assert.ok(quoteDocument(manual).includes('<bdi>—</bdi>'));
 const dayOnly=calculateQuote({...form,day:'15',night:'',allInOnePanelQty:''});assert.equal(dayOnly.panelQty,7);assert.deepEqual(dayOnly.errors,[]);
 assert.ok(calculateQuote({...form,day:'15',night:'-1',allInOnePanelQty:''}).errors.length);

 for(const allInOnePanelQty of ['0','-1','1.5','1001',true,[1]])assert.ok(calculateQuote({...manual,allInOnePanelQty}).errors.some(e=>e.includes('عدد الألواح')));
 assert.equal(calculateQuote({...manual,day:'0',night:'0',allInOnePanelQty:''}).errors.length>0,true);
 const standard={...complete()};delete standard.systemType;assert.equal(calculateQuote(standard).price,4116000);
});
