'use client';
import {useEffect,useMemo,useRef,useState} from 'react';
import {useWarehouseInventory,WarehouseField} from './warehouse-data';
import PartySearch from './party-search';
import {InvoiceShell,InvoiceField,InvoiceCatalog,InvoiceItems,InvoiceSummary,InvoiceActions} from './invoice-workspace';
import {exchangeRateError,purchaseAmounts,weightedCost} from './currency-utils.mjs';
import {loadExchangeRate} from './currency-store.mjs';
import {supplierDocument,money,moneyInput,receiptNumber} from './supplier-utils.mjs';
import {salesDocument} from './sales-document.mjs';
import {invoiceError} from './review-utils.mjs';
import {convertAmount,currencyLabel} from './fx-utils.mjs';
import {purchaseDisplayTotal} from './money-format.mjs';
import MoneyInput from './money-input';
import WarrantyEditor from './warranty-editor';
import ReportActions from './report-actions';
import {blankWarranty,warrantyPolicy,warrantyError,warrantyUrl} from './warranty-utils.mjs';

const blank=kind=>({party:'',currency:'IQD',exchangeRate:'',cashCurrency:'IQD',mode:'credit',notes:'',expenses:'',warranty:blankWarranty()});
export default function CurrencyInvoice({contact,kind,products:catalogProducts,parties,items,setItems,search,setSearch,onSave,onUpdateInvoice,history=[],renderHistory,initialInvoice,initialParty='',onCancel,canEditRate=false,a4,openA4,saveA4,shareA4}){
 const [meta,setMeta]=useState(()=>{const party=parties.find(p=>p.name===initialParty);return {...blank(kind),party:initialParty,...(kind==='purchase'&&party?{currency:party.accountCurrency||'IQD',cashCurrency:party.accountCurrency||'IQD'}:{})};}),[saving,setSaving]=useState(false),[editing,setEditing]=useState(null),[backup,setBackup]=useState(null),[error,setError]=useState(''),[settings,setSettings]=useState(null),[saved,setSaved]=useState(null);
 const catalogVersion=useMemo(()=>JSON.stringify(catalogProducts||[]),[catalogProducts]);
 const inventory=useWarehouseInventory({versionKey:catalogVersion}),products=inventory.products;
 const opened=useRef(false),partySeeded=useRef(!initialParty||kind!=='purchase'||parties.some(p=>p.name===initialParty));
 useEffect(()=>{if(partySeeded.current)return;const party=parties.find(p=>p.name===initialParty);if(!party)return;partySeeded.current=true;setMeta(m=>({...m,currency:party.accountCurrency||'IQD',cashCurrency:party.accountCurrency||'IQD'}));},[initialParty,kind,parties]);
 useEffect(()=>{let live=true;if(kind==='purchase')loadExchangeRate().then(data=>{if(live){setSettings(data);setMeta(m=>({...m,exchangeRate:m.exchangeRate|| (data.rate==null?'':String(data.rate))}));}}).catch(()=>{if(live)setError('تعذر تحميل الصرف المعتمد؛ حدّث البيانات قبل حفظ الشراء.');});return()=>{live=false;};},[kind]);
 useEffect(()=>{if(initialInvoice&&!opened.current){opened.current=true;beginEdit(initialInvoice);}},[initialInvoice]);
 function beginEdit(invoice){
  if(saving)return;
  if(editing&&!confirm('ترك التعديل الحالي وفتح فاتورة أخرى؟'))return;
  if(!editing)setBackup({items:items.map(i=>({...i})),meta:{...meta},search,warehouseId:inventory.warehouseId});
  setEditing(invoice);inventory.setWarehouse(String(invoice.warehouseId||invoice.warehouse_id||''));setError('');
  setItems((invoice.items||[]).map(i=>({...i,price:kind==='purchase'?(i.sourcePrice??i.price):i.price,code:(products.find(p=>p.id===i.id)||catalogProducts?.find(p=>p.id===i.id))?.code||i.code||''})));
  setMeta({warranty:invoice.warranty||blankWarranty(),party:parties.find(p=>p.id===invoice.partyId)?.name||invoice.party||'',currency:invoice.sourceCurrency||'IQD',exchangeRate:String(invoice.marketRate>1?invoice.marketRate:invoice.sourceCurrency==='USD'?invoice.exchangeRate:settings?.rate||''),cashCurrency:invoice.cashCurrency||'IQD',mode:invoice.cash?'cash':'credit',notes:invoice.notes||'',expenses:String(invoice.expenses||'')});setSearch('');
  window.scrollTo({top:0,behavior:'instant'});
 }
 function restore(){if(onCancel){onCancel();return;}inventory.setWarehouse(backup?.warehouseId||inventory.warehouseId);setItems(backup?.items||[]);setMeta(backup?.meta||blank(kind));setSearch(backup?.search||'');setEditing(null);setBackup(null);setError('');}
 const rate=meta.currency==='USD'?Number(meta.exchangeRate):1;
 const supplier=parties.find(s=>s.name===meta.party),accountCurrency=supplier?.accountCurrency||'IQD';
 const validation=kind==='purchase'?exchangeRateError('USD',meta.exchangeRate):'';
 let amounts={items:[],sourceSubtotal:0,subtotal:0,total:0,expenses:Number(meta.expenses||0)};
 try{amounts=purchaseAmounts(items,kind==='purchase'?meta.currency:'IQD',rate,meta.expenses||0);}catch{}
 const landed=i=>amounts.items.find(x=>x.id===i.id)?.landedCost||0;
 const average=i=>{const product=products.find(p=>p.id===i.id);if(validation||i.price===''||!Number.isFinite(Number(i.price))||Number(i.price)<0||Number(i.qty)<=0||!product||product.companyQty==null)return null;return weightedCost(product.companyQty,product.cost,i.qty,landed(i));};
 const change=(key,value)=>setMeta(m=>({...m,[key]:value}));
 const chooseParty=value=>setMeta(m=>{const selected=parties.find(p=>p.name===value);return {...m,party:value,...(kind==='purchase'&&!editing&&!items.length&&selected?{currency:selected.accountCurrency||'IQD',cashCurrency:selected.accountCurrency||'IQD'}:{})};});
 const availableProducts=editing&&kind==='sale'?products.map(p=>({...p,qty:Number(p.qty)+(editing.items||[]).filter(i=>i.id===p.id).reduce((sum,i)=>sum+Number(i.qty),0)})):products;
 const fxMeta={marketRate:Number(meta.exchangeRate),accountRevision:supplier?.currencyRevision||0,cashCurrency:meta.cashCurrency,partyId:supplier?.id};
 const draft={customerPhone:supplier?.phone||'',creatorName:editing?(editing.creatorName||'—'):(contact?.display_name||contact?.username),creatorPhone:editing?editing.creatorPhone:contact?.phone,warehouseId:Number(inventory.warehouseId),warehouseName:editing?.warehouseName||inventory.warehouseName,warranty:warrantyPolicy(meta.warranty,items),id:editing?.id,receiptNo:editing?.receiptNo,kind,draft:true,party:meta.party,cash:meta.mode==='cash',date:editing?.date||new Date().toISOString(),...amounts,sourceCurrency:kind==='purchase'?meta.currency:'IQD',exchangeRate:rate,...fxMeta,accountCurrency,accountAmount:convertAmount(amounts.total,'IQD',accountCurrency,meta.exchangeRate||1),cashAmount:convertAmount(amounts.total,'IQD',meta.cashCurrency,meta.exchangeRate||1),notes:meta.notes};
 const display=kind==='purchase'?purchaseDisplayTotal(draft):{currency:'IQD',value:amounts.total};
 function document(priced=true){const d=kind==='purchase'?supplierDocument(draft):salesDocument({...draft,party_name:draft.party,created_at:draft.date,items:amounts.items.map(i=>({...i,product_name:i.name,brand_name:i.brand}))},priced);return a4(d.title,d.body,d.total,editing?'تعديل فاتورة #'+receiptNumber(editing)+' — غير محفوظ':d.subtitle);}
 async function save(){
  if(saving)return;setError('');
  if(!inventory.ready||!inventory.warehouseId){setError(inventory.error||'اختر المخزن وانتظر تحميل رصيده');return;}
  const invalid=(kind==='sale'?warrantyError(meta.warranty,items):'')||validation||invoiceError(items,availableProducts,kind);
  if(invalid){setError(invalid);return;}
  if(kind==='purchase'&&!supplier){setError('اختر المورد المسجّل لتحديد عملة حسابه');return;}
  if(meta.mode==='credit'&&!meta.party){setError('اختر العميل أو المورد للفاتورة الآجلة');return;}
  if(!Number.isFinite(Number(meta.expenses||0))||Number(meta.expenses||0)<0){setError('أدخل مصاريف صحيحة بالدينار');return;}
  if(kind==='purchase'&&!amounts.sourceSubtotal&&Number(meta.expenses)>0){setError('لا يمكن توزيع المصاريف على أسعار مجموعها صفر');return;}
  setSaving(true);
  try{
   if(editing){const original=editing;const ok=await onUpdateInvoice(original,{...original,...meta,warehouseId:Number(inventory.warehouseId),warranty:warrantyPolicy(meta.warranty,items),...fxMeta,sourceCurrency:meta.currency,exchangeRate:rate,items,expenses:Number(meta.expenses||0)});if(ok){inventory.refresh();restore();}}
   else{const ok=await onSave({...meta,warehouseId:Number(inventory.warehouseId),warranty:warrantyPolicy(meta.warranty,items),...fxMeta,sourceCurrency:kind==='purchase'?meta.currency:'IQD',exchangeRate:rate},items);if(ok){inventory.refresh();if(kind==='sale'&&ok.receiptNo){const d=salesDocument({...draft,...ok,draft:false,party_name:meta.party,created_at:ok.date||draft.date,items:amounts.items.map(i=>({...i,product_name:i.name,brand_name:i.brand}))});setSaved({html:a4(d.title,d.body,d.total,d.subtitle),number:ok.receiptNo,token:ok.warrantyToken});}setItems([]);setMeta(m=>({...blank(kind),currency:m.currency,exchangeRate:m.exchangeRate}));setSearch('');}}
  }catch(e){setError(e.message||'تعذر حفظ الفاتورة؛ أعد المحاولة بنفس البيانات.');}
  finally{setSaving(false);}
 }
 return <><InvoiceShell title={kind==='purchase'?'فاتورة شراء':'فاتورة بيع جملة'} currency={kind==='purchase'?meta.currency:'IQD'} saving={saving} className={kind==='sale'?'saleWorkspace':''} editing={editing?{number:receiptNumber(editing),date:editing.date}:null}>
  {kind==='purchase'&&<WarehouseField inventory={inventory} disabled={saving||!!editing} label="مخزن استلام المشتريات"/>}
  <div className={'deskMeta '+(kind==='sale'?'deskSaleMeta':'')}><InvoiceField label={kind==='purchase'?'المورد':'العميل'}><PartySearch rows={parties} value={meta.party} onChange={chooseParty}/></InvoiceField><InvoiceField label="طريقة الدفع" className={'deskPaymentField '+meta.mode}><select aria-label="طريقة الدفع" disabled={!!editing&&kind!=='sale'} value={meta.mode} onChange={e=>change('mode',e.target.value)}><option value="credit">آجل</option><option value="cash">نقدي</option></select></InvoiceField>{kind==='purchase'?<InvoiceField label="عملة الفاتورة"><select aria-label="عملة الشراء" value={meta.currency} onChange={e=>setMeta(m=>({...m,currency:e.target.value,exchangeRate:e.target.value==='USD'&&(!m.exchangeRate||m.exchangeRate==='1')?String(settings?.rate||''):m.exchangeRate}))}><option value="IQD">دينار · IQD</option><option value="USD">دولار · USD</option></select></InvoiceField>:<WarehouseField inventory={inventory} disabled={saving||!!editing} label="مخزن تجهيز الفاتورة"/>}</div>
  {editing&&kind==='sale'&&<div className="salePaymentChange" role="status"><b>طريقة الدفع: {meta.mode==='cash'?'نقدي':'آجل'}</b>{editing.cash!==(meta.mode==='cash')?<><p>فرق قاصة صاحب الفاتورة عند الحفظ: <bdi>{money((meta.mode==='cash'?amounts.total:0)-(editing.cash?Number(editing.total):0))} د.ع</bdi></p><p>{meta.mode==='cash'?'النقدي يعني قبض كامل قيمة الفاتورة.':'الآجل ينقل قيمة الفاتورة إلى حساب الزبون ويعكس قبضها من القاصة.'} التسديدات المسجّلة بصورة مستقلة تبقى في الحساب؛ راجعها لتجنّب تكرار القبض.</p></>:<p>يمكنك تغيير طريقة الدفع، ويُحدَّث حساب الزبون وقاصة صاحب الفاتورة مع الحفظ.</p>}</div>}
  {kind==='purchase'&&<section className="deskExchange"><InvoiceField label="الصرف المثبّت · د.ع لكل دولار"><MoneyInput aria-label="صرف فاتورة الشراء" value={meta.exchangeRate} disabled={!canEditRate} onChange={value=>change('exchangeRate',value)} placeholder="سعر الصرف المعتمد"/><small>100 دولار = {money(Number(meta.exchangeRate)*100)} د.ع</small></InvoiceField><div><p>عملة حساب المورد: <b>{accountCurrency}</b> · <bdi>{money(draft.accountAmount,accountCurrency)} {currencyLabel(accountCurrency)}</bdi>. تُحفظ الكلفة بالدينار والصرف داخل الوصل.{!canEditRate&&' تغيير الصرف يحتاج صلاحية.'}</p>{meta.mode==='cash'&&<InvoiceField label="عملة الدفع من القاصة"><select aria-label="عملة دفع الشراء" disabled={!!editing} value={meta.cashCurrency} onChange={e=>change('cashCurrency',e.target.value)}><option value="IQD">دينار عراقي IQD</option><option value="USD">دولار أمريكي USD</option></select><small>يُخصم {money(draft.cashAmount,meta.cashCurrency)} {currencyLabel(meta.cashCurrency)}</small></InvoiceField>}</div></section>}
  <div className="deskBody"><InvoiceCatalog availableOnly={kind!=='purchase'} products={availableProducts} items={items} query={search} onQuery={setSearch} onAdd={p=>{if(!items.some(i=>i.id===p.id))setItems(current=>current.some(i=>i.id===p.id)?current:[{...p,qty:'',price:''},...current]);}}/><InvoiceItems currency={kind==='purchase'?meta.currency:'IQD'} items={items} products={availableProducts} kind={kind} average={kind==='purchase'&&!editing?average:undefined} onEdit={(id,key,value)=>setItems(items.map(i=>i.id===id?{...i,[key]:value}:i))} onRemove={id=>setItems(items.filter(i=>i.id!==id))} landed={landed}/></div>
  <div className="deskFooterFields"><InvoiceField label="المصاريف الإضافية · د.ع"><MoneyInput aria-label="المصاريف الإضافية" value={meta.expenses} onChange={value=>change('expenses',value)}/>{kind==='purchase'&&<small>توزّع على المواد قبل احتساب متوسط كلفة المخزون.</small>}</InvoiceField><InvoiceField label="ملاحظات الفاتورة"><textarea aria-label="ملاحظات الفاتورة" value={meta.notes} maxLength={4000} onChange={e=>change('notes',e.target.value)}/></InvoiceField></div>
  {kind==='sale'&&<WarrantyEditor value={meta.warranty} items={items} onChange={w=>change('warranty',w)}/>}
  <InvoiceSummary entries={[["عدد الأصناف",items.length],["مجموع الكميات",money(items.reduce((sum,i)=>sum+Number(i.qty||0),0))],["مجموع المواد",money(amounts.sourceSubtotal,meta.currency)+(kind==='purchase'&&meta.currency==='USD'?' $':' د.ع')],...(kind==='purchase'&&meta.currency==='USD'?[["المواد بالدينار",money(amounts.subtotal)+' د.ع']]:[]),["المصاريف",money(amounts.expenses)+' د.ع']]} total={display.value} currency={display.currency} secondary={display.currency==='USD'?'كلفة المخزون بالدينار: '+money(amounts.total)+' د.ع':''}/>
  {error&&<p className="workflowError" role="alert">{error}</p>}
  <InvoiceActions documentHtml={document()} documentName={'فاتورة-'+kind+(editing?'-'+receiptNumber(editing):'-مسودة')} saving={saving} onSave={save} saveLabel={editing?'حفظ التعديل':'حفظ الوصل'} onCancel={editing?restore:undefined} onPreview={()=>openA4(document())} onPdf={()=>saveA4(document(),'فاتورة-'+kind)} onShare={()=>shareA4('فاتورة-'+kind,'الإجمالي: '+money(display.value,display.currency)+' '+currencyLabel(display.currency),document())} onClear={()=>{if(confirm('تفريغ مواد الفاتورة الحالية؟'))setItems([]);}}>{kind==='sale'&&<><button onClick={()=>openA4(document(false))}>معاينة نسخة المخزن</button><button onClick={()=>saveA4(document(false),'فاتورة-مخزنية')}>حفظ نسخة المخزن</button></>}</InvoiceActions>
 </InvoiceShell>{saved&&<section className="warrantySaved"><h2>تم حفظ فاتورة #{saved.number}</h2>{saved.token&&<a target="_blank" rel="noopener noreferrer" href={warrantyUrl(saved.token)}>فتح شهادة الضمان</a>}<ReportActions enabled html={saved.html} filename={'فاتورة-بيع-'+saved.number}/><button onClick={()=>setSaved(null)}>إغلاق</button></section>}{renderHistory?.(beginEdit)}</>;
}
