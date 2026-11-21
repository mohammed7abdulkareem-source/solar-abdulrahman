'use client';
import {userDisplayName} from './user-name-utils.mjs';

import {useEffect,useId,useMemo,useRef,useState} from 'react';
import {useWarehouseInventory,WarehouseField} from './warehouse-data';
import PartySearch from './party-search';
import {InvoiceShell,InvoiceField,InvoiceCatalog,InvoiceItems,InvoiceSummary,InvoiceActions} from './invoice-workspace';
import {exchangeRateError,purchaseAmounts,weightedCost,saleExpenseAmounts,saleExpensesOnCustomer,invoicePayload} from './currency-utils.mjs';
import {loadExchangeRate} from './currency-store.mjs';
import {supplierDocument,money,moneyInput,receiptNumber} from './supplier-utils.mjs';
import {salesDocument} from './sales-document.mjs';
import {invoiceError} from './review-utils.mjs';
import {convertAmount,currencyLabel} from './fx-utils.mjs';
import {purchaseDisplayTotal} from './money-format.mjs';
import MoneyInput from './money-input';
import WarrantyEditor from './warranty-editor';
import {blankWarranty,warrantyPolicy,warrantyError} from './warranty-utils.mjs';
import {unlockNotificationSound,playNotificationSound} from './notification-sound.mjs';
import {savedSaleInvoice} from './invoice-save-result.mjs';
import SavedSaleReceipt from './saved-sale-receipt';
import {currentSaleItems,hasHiddenSaleCost,usesPersonalSalePrices} from './inventory-valuation.mjs';
import {refreshMaterialBrands} from './current-brand.mjs';
import {useWholesaleSalePricing} from './use-wholesale-sale-pricing';
import {wholesaleEconomicsChanged,wholesaleLinePricing,wholesalePriceDefault,refreshWholesaleDefaults,wholesaleFloorTokens,wholesalePricingIssues,wholesaleAppliesToSubject,wholesalePolicyEnforced} from './wholesale-invoice-pricing.mjs';
import AppIcon from './app-icons';
import {salesAuthorizationKey} from './sales-read-scope.mjs';
import {usePurchaseCorrection} from './use-purchase-correction';
import {purchaseCorrectionMatches,purchaseCorrectionError,purchaseEditRate} from './purchase-correction.mjs';
import PurchaseCorrectionReview from './purchase-correction-review';
import './wholesale-invoice-pricing.css';
import './sale-expenses.css';

const blank=kind=>({... (kind==='sale'?{expensesOnCustomer:true}:{}),directPreparation:false,party:'',currency:'IQD',exchangeRate:'',cashCurrency:'IQD',mode:'credit',notes:'',expenses:'',warranty:blankWarranty()});
export default function CurrencyInvoice({contact,onChanged,kind,products:catalogProducts,parties,items:draftItems,setItems,search,setSearch,onSave,onUpdateInvoice,onEditSaved,history=[],renderHistory,initialInvoice,initialParty='',onCancel,canEditRate=false,a4,openA4,saveA4,shareA4}){
 const [meta,setMeta]=useState(()=>{const party=parties.find(p=>p.name===initialParty);return {...blank(kind),party:initialParty,...(kind==='purchase'&&party?{currency:party.accountCurrency||'IQD',cashCurrency:party.accountCurrency||'IQD'}:{})};}),[saving,setSaving]=useState(false),[editing,setEditing]=useState(null),[backup,setBackup]=useState(null),[error,setError]=useState(''),[settings,setSettings]=useState(null),[saved,setSaved]=useState(null);
 const expenseHintId=useId();
 const [correctionBase,setCorrectionBase]=useState(null),[correctionReview,setCorrectionReview]=useState(null);
 const correctionScope=salesAuthorizationKey(contact),purchaseEditing=kind==='purchase'&&!!editing;
 const correctionOriginalIds=(editing?.items||[]).map(item=>item.id);
 const correction=usePurchaseCorrection({enabled:purchaseEditing,scope:contact?.id?correctionScope:'',invoiceId:editing?.id,originalProductIds:correctionOriginalIds});
 const correctionRef=useRef(null),correctionFailureRef=useRef(null),errorRef=useRef(null),liveCorrection=useRef(null);
 const catalogVersion=useMemo(()=>JSON.stringify(catalogProducts||[]),[catalogProducts]);
 const inventory=useWarehouseInventory({versionKey:catalogVersion}),products=inventory.products;
 const wholesale=useWholesaleSalePricing({userId:contact?.id,invoiceId:editing?.id,enabled:kind==='sale'});
 const items=kind==='sale'?currentSaleItems(refreshWholesaleDefaults(draftItems,wholesale.data),products,editing?.items,usesPersonalSalePrices(contact),!!editing):refreshMaterialBrands(draftItems,products);
 const wholesaleHistorical=kind==='sale'&&!!editing&&!wholesaleEconomicsChanged(items,editing.items),wholesaleIssues=kind==='sale'?wholesalePricingIssues(wholesale.data,items,editing?.items):[];
 const wholesaleRules=kind==='sale'&&wholesale.data?new Map(items.map(item=>[String(item.id),wholesaleLinePricing(wholesale.data,item.id,{historical:wholesaleHistorical})])):null;
 const opened=useRef(false),saveLock=useRef(false),partySeeded=useRef(!initialParty||kind!=='purchase'||parties.some(p=>p.name===initialParty));
 useEffect(()=>{if(partySeeded.current)return;const party=parties.find(p=>p.name===initialParty);if(!party)return;partySeeded.current=true;setMeta(m=>({...m,currency:party.accountCurrency||'IQD',cashCurrency:party.accountCurrency||'IQD'}));},[initialParty,kind,parties]);
 useEffect(()=>{let live=true;if(kind==='purchase')loadExchangeRate().then(data=>{if(live){setSettings(data);setMeta(m=>({...m,exchangeRate:m.exchangeRate|| (data.rate==null?'':String(data.rate))}));}}).catch(()=>{if(live)setError('تعذر تحميل الصرف المعتمد؛ حدّث البيانات قبل حفظ الشراء.');});return()=>{live=false;};},[kind]);
 useEffect(()=>{if(initialInvoice&&!opened.current){opened.current=true;beginEdit(initialInvoice);}},[initialInvoice]);
 useEffect(()=>{setCorrectionReview(null);if(purchaseEditing&&correctionBase&&!(correctionBase.sourceCurrency==='IQD'&&!(Number(correctionBase.marketRate)>0)))void correction.load(correctionBase);},[purchaseEditing,correctionBase,correction.load]);
 useEffect(()=>{if(correctionBase?.sourceCurrency==='IQD'&&!(Number(correctionBase.marketRate)>0)&&Number(settings?.rate)>0)setCorrectionBase(base=>({...base,marketRate:Number(settings.rate)}));},[correctionBase,settings?.rate]);
 useEffect(()=>{if(error&&purchaseEditing){errorRef.current?.focus({preventScroll:true});errorRef.current?.scrollIntoView({block:'center',behavior:'smooth'});}},[error,purchaseEditing]);
 useEffect(()=>{if(correction.error&&purchaseEditing){correctionFailureRef.current?.focus({preventScroll:true});correctionFailureRef.current?.scrollIntoView({block:'center',behavior:'smooth'});}},[correction.error,purchaseEditing]);
 function beginEdit(invoice){
  if(saving)return;
  if(editing&&!confirm('ترك التعديل الحالي وفتح فاتورة أخرى؟'))return;
  if(!editing)setBackup({items:items.map(i=>({...i})),meta:{...meta},search,warehouseId:inventory.warehouseId});
  setSaved(null);setEditing(invoice);inventory.setWarehouse(String(invoice.warehouseId||invoice.warehouse_id||''));setError('');setCorrectionReview(null);
  const editItems=(invoice.items||[]).map(i=>({...i,price:kind==='purchase'?(i.sourcePrice??i.price):i.price,code:(products.find(p=>p.id===i.id)||catalogProducts?.find(p=>p.id===i.id))?.code||i.code||''}));
  const editMeta={... (kind==='sale'?{expensesOnCustomer:saleExpensesOnCustomer(invoice)}:{}),warranty:invoice.warranty||blankWarranty(),party:invoice.currentCustomerName||parties.find(p=>String(p.id)===String(invoice.partyId))?.name||invoice.party||'',...(kind==='sale'?{saleCustomerId:invoice.partyId??null}:{}),currency:invoice.sourceCurrency||'IQD',exchangeRate:kind==='purchase'?purchaseEditRate(invoice,settings?.rate):String(invoice.marketRate>1?invoice.marketRate:invoice.sourceCurrency==='USD'?invoice.exchangeRate:settings?.rate||''),cashCurrency:invoice.cashCurrency||'IQD',mode:invoice.cash?'cash':'credit',notes:invoice.notes||'',expenses:String(invoice.expenses||'')};
  setItems(editItems);setMeta(editMeta);setSearch('');
  if(kind==='purchase'){const party=parties.find(p=>p.name===editMeta.party);setCorrectionBase(invoicePayload(kind,{...editMeta,warehouseId:invoice.warehouseId||invoice.warehouse_id,sourceCurrency:editMeta.currency,exchangeRate:editMeta.currency==='USD'?Number(editMeta.exchangeRate):1,marketRate:Number(editMeta.exchangeRate),partyId:party?.id??invoice.partyId,accountRevision:party?.currencyRevision||0},editItems,invoice));}
  window.scrollTo({top:0,behavior:'instant'});
 }
 function restore(){setCorrectionReview(null);setCorrectionBase(null);if(onCancel){onCancel();return;}inventory.setWarehouse(backup?.warehouseId||inventory.warehouseId);setItems(backup?.items||[]);setMeta(backup?.meta||blank(kind));setSearch(backup?.search||'');setEditing(null);setBackup(null);setError('');}
 const rate=meta.currency==='USD'?Number(meta.exchangeRate):1;
 const supplier=meta.saleCustomerId!=null?parties.find(s=>String(s.id)===String(meta.saleCustomerId)):parties.find(s=>s.name===meta.party),accountCurrency=supplier?.accountCurrency||'IQD';
 const validation=kind==='purchase'?exchangeRateError('USD',meta.exchangeRate):'';
 let amounts={items:[],sourceSubtotal:0,subtotal:0,total:0,expenses:Number(meta.expenses||0),billedExpenses:0,internalExpenses:0,profit:0};
 try{amounts=kind==='sale'?saleExpenseAmounts(items,meta.expenses||0,saleExpensesOnCustomer(meta)):purchaseAmounts(items,meta.currency,rate,meta.expenses||0);}catch{}
 const landed=i=>amounts.items.find(x=>x.id===i.id)?.landedCost||0;
 const average=i=>{const product=products.find(p=>p.id===i.id);if(product?.personalPriceBasis||validation||i.price===''||!Number.isFinite(Number(i.price))||Number(i.price)<0||Number(i.qty)<=0||!product||product.companyQty==null)return null;return weightedCost(product.companyQty,product.cost,i.qty,kind==='purchase'&&meta.currency==='USD'&&inventory.valuationRate?Number(i.price)*Number(inventory.valuationRate)+landed(i)-Number(i.price)*rate:landed(i));};
 const change=(key,value)=>setMeta(m=>({...m,[key]:value}));
 const chooseParty=selected=>setMeta(m=>({...m,party:selected?.name||'',...(kind==='sale'?{saleCustomerId:selected?.id??null}:{}),...(kind==='purchase'&&!editing&&!items.length&&selected?{currency:selected.accountCurrency||'IQD',cashCurrency:selected.accountCurrency||'IQD'}:{})}));
 const availableProducts=editing&&kind==='sale'?products.map(p=>({...p,qty:Number(p.qty)+(editing.items||[]).filter(i=>i.id===p.id).reduce((sum,i)=>sum+Number(i.qty),0)})):products;
 const fxMeta={...(kind==='sale'?{valuationRevision:inventory.valuationRevision,wholesalePricingRevision:wholesale.data?.revision,wholesaleFloorTokens:wholesaleFloorTokens(wholesale.data,items,editing?.items)}:{}),marketRate:Number(meta.exchangeRate),accountRevision:supplier?.currencyRevision||0,cashCurrency:meta.cashCurrency,partyId:supplier?.id};
 const draft={createdBy:editing?.createdBy||contact?.id,customerPhone:supplier?.phone||'',creatorName:editing?(editing.creatorName||'—'):(userDisplayName(contact)),creatorPhone:editing?editing.creatorPhone:contact?.phone,warehouseId:Number(inventory.warehouseId),warehouseName:editing?.warehouseName||inventory.warehouseName,warranty:warrantyPolicy(meta.warranty,items),id:editing?.id,receiptNo:editing?.receiptNo,kind,draft:true,party:meta.party,cash:meta.mode==='cash',date:editing?.date||new Date().toISOString(),...amounts,sourceCurrency:kind==='purchase'?meta.currency:'IQD',exchangeRate:rate,...fxMeta,accountCurrency,accountAmount:convertAmount(amounts.total,'IQD',accountCurrency,meta.exchangeRate||1),cashAmount:convertAmount(amounts.total,'IQD',meta.cashCurrency,meta.exchangeRate||1),notes:meta.notes};
 const display=kind==='purchase'?purchaseDisplayTotal(draft):{currency:'IQD',value:amounts.total};
 const editCandidate=editing?{...editing,...meta,warehouseId:Number(inventory.warehouseId),warranty:warrantyPolicy(meta.warranty,items),...fxMeta,sourceCurrency:meta.currency,exchangeRate:rate,items,expenses:Number(meta.expenses||0)}:null;
 const correctionPayload=purchaseEditing?invoicePayload('purchase',editCandidate,items,editing):null;
 const correctionConfirmed=purchaseEditing&&purchaseCorrectionMatches(correctionReview,correctionPayload,correctionScope,correctionOriginalIds);
 const correctionLocks=purchaseEditing?correction.data?.locks:null;
 liveCorrection.current={scope:correctionScope,payload:correctionPayload,originalProductIds:correctionOriginalIds};
 const refreshCorrection=()=>{setCorrectionReview(null);setError('');if(correctionPayload)void correction.load(correctionPayload);};
 function document(priced=true){const d=kind==='purchase'?supplierDocument(draft):salesDocument({...draft,party_name:draft.party,created_at:draft.date,items:amounts.items.map(i=>({...i,product_name:i.name,brand_name:i.brand}))},priced);return a4(d.title,d.body,d.total,editing?'تعديل فاتورة #'+receiptNumber(editing)+' — غير محفوظ':d.subtitle);}
 async function save(){
  if(saveLock.current||saving)return;setError('');
  if(!inventory.ready||!inventory.warehouseId){setError(inventory.error||'اختر المخزن وانتظر تحميل رصيده');return;}
  if(kind==='sale'&&!wholesale.ready){setError(wholesale.error||'انتظر تأكيد أسعار بيع الجملة أو حدّث الأسعار قبل الحفظ.');return;}
  const pricingIssue=kind==='sale'?wholesaleIssues[0]:null;
  if(pricingIssue){setError(pricingIssue.message||'سعر «'+pricingIssue.name+'» أقل من السعر المقرر: '+money(pricingIssue.minimum)+' د.ع. يجوز البيع بهذا السعر أو أعلى.');return;}
  const invalid=(kind==='sale'?warrantyError(meta.warranty,items):'')||validation||invoiceError(items,availableProducts,kind);
  if(invalid){setError(invalid);return;}
  if(kind==='purchase'&&!supplier){setError('اختر المورد المسجّل لتحديد عملة حسابه');return;}
  if(meta.mode==='credit'&&!meta.party){setError('اختر العميل أو المورد للفاتورة الآجلة');return;}
  if(!Number.isFinite(Number(meta.expenses||0))||Number(meta.expenses||0)<0){setError('أدخل مصاريف صحيحة بالدينار');return;}
  if(kind==='purchase'&&!amounts.sourceSubtotal&&Number(meta.expenses)>0){setError('لا يمكن توزيع المصاريف على أسعار مجموعها صفر');return;}
  if(purchaseEditing&&!correction.ready){setError(correction.error||'انتظر تحميل حالة وصل الشراء أو حدّث المعاينة.');return;}
  saveLock.current=true;setSaving(true);
  if(kind==='sale'&&!editing)void unlockNotificationSound();
  try{
   if(editing){
    if(purchaseEditing&&!correctionConfirmed){
     const candidate=JSON.parse(JSON.stringify(editCandidate)),result=await correction.load(correctionPayload);
     if(result&&purchaseCorrectionMatches(result,liveCorrection.current?.payload,liveCorrection.current?.scope,liveCorrection.current?.originalProductIds)){
      setCorrectionReview({...result,candidate});setTimeout(()=>{const panel=correctionRef.current?.querySelector('[data-purchase-correction-review]');panel?.focus({preventScroll:true});panel?.scrollIntoView({block:'start',behavior:'smooth'});},0);
     }
     return;
    }
    if(purchaseEditing&&!correctionReview.data.canApply){setError(correctionReview.data.blockedReason);return;}
    const original=editing,candidate=purchaseEditing?{...correctionReview.candidate,purchaseCorrectionToken:correctionReview.data.token}:editCandidate;
    const ok=await onUpdateInvoice(original,candidate);if(ok){inventory.refresh();if(onEditSaved)await onEditSaved();else restore();}
   }
   else{const ok=await onSave({...meta,warehouseId:Number(inventory.warehouseId),warranty:warrantyPolicy(meta.warranty,items),...fxMeta,sourceCurrency:kind==='purchase'?meta.currency:'IQD',exchangeRate:rate},items);if(ok){inventory.refresh();if(kind==='sale'&&ok.receiptNo){setSaved(savedSaleInvoice(draft,ok));void playNotificationSound();window.scrollTo({top:0,behavior:'instant'});}setItems([]);setMeta(m=>({...blank(kind),currency:m.currency,exchangeRate:m.exchangeRate}));setSearch('');}}
  }catch(e){setError(purchaseEditing?purchaseCorrectionError(e):e.message||'تعذر حفظ الفاتورة؛ أعد المحاولة بنفس البيانات.');if(purchaseEditing&&/^[0-9A-Z]{5}$/.test(e.code||''))setCorrectionReview(null);if(kind==='sale'&&e.code==='PT409')void wholesale.reload();}
  finally{saveLock.current=false;setSaving(false);}
 }
 if(kind==='sale'&&saved)return <><SavedSaleReceipt invoice={saved} profile={contact} onPrepared={data=>{setSaved(s=>({...s,...data}));if(onChanged)void Promise.resolve().then(onChanged).catch(()=>{});}} a4={a4} onNew={()=>{setSaved(null);setError('');window.scrollTo({top:0,behavior:'instant'});}}/>{renderHistory?.(beginEdit)}</>;
 return <><InvoiceShell kind={kind} title={kind==='purchase'?'فاتورة شراء':'فاتورة بيع جملة'} currency={kind==='purchase'?meta.currency:'IQD'} saving={saving||correction.loading} className={kind==='sale'?'saleWorkspace':''} editing={editing?{number:receiptNumber(editing),date:editing.date}:null}>
  {purchaseEditing&&<><section className="purchaseCorrectionIntro"><span className="purchaseCorrectionIcon"><AppIcon name="edit" size={22}/></span><div><h2>تعديل وصل الشراء</h2><p>تقدر تضيف مادة من البحث وتحدّد كميتها وسعرها، أو تعدّل مواد الوصل ومصاريفه.</p><small>يُصحّح سعر الكلفة وربح الكميات المتأثرة فقط. أسعار بيع الزبائن والتسديدات الفعلية لا تتغير.</small>{correction.data?.requiresCorrection&&<small>ارتبطت بالوصل حركات لاحقة؛ يبقى المورد والمخزن والعملات والصرف وطريقة الدفع كما سُجلت.</small>}</div></section>{correction.loading&&<p className="purchaseCorrectionLoading" role="status">جاري تحميل معاينة تعديل الشراء…</p>}{correction.error&&<div ref={correctionFailureRef} tabIndex={-1} className="purchaseCorrectionFailure" role="alert">{correction.error}<button type="button" onClick={refreshCorrection}>تحديث معاينة الشراء</button></div>}</>}
  {kind==='purchase'&&<WarehouseField inventory={inventory} disabled={saving||!!editing} label="مخزن استلام المشتريات"/>}
  <div className={'deskMeta '+(kind==='sale'?'deskSaleMeta':'')}><InvoiceField label={kind==='purchase'?'المورد':'العميل'}><fieldset className="purchaseCorrectionLockedField" disabled={purchaseEditing&&(!correction.data||correctionLocks?.supplier)}><PartySearch rows={parties} value={meta.party} selectedId={meta.saleCustomerId} onSelectRow={chooseParty}/></fieldset></InvoiceField><InvoiceField label="طريقة الدفع" className={'deskPaymentField '+meta.mode}><select aria-label="طريقة الدفع" disabled={!!editing&&kind!=='sale'} value={meta.mode} onChange={e=>change('mode',e.target.value)}><option value="credit">آجل</option><option value="cash">نقدي</option></select></InvoiceField>{kind==='purchase'?<InvoiceField label="عملة الفاتورة"><select aria-label="عملة الشراء" disabled={purchaseEditing&&(!correction.data||correctionLocks?.sourceCurrency)} value={meta.currency} onChange={e=>setMeta(m=>({...m,currency:e.target.value,exchangeRate:e.target.value==='USD'&&(!m.exchangeRate||m.exchangeRate==='1')?String(settings?.rate||''):m.exchangeRate}))}><option value="IQD">دينار · IQD</option><option value="USD">دولار · USD</option></select></InvoiceField>:<WarehouseField inventory={inventory} disabled={saving||!!editing} label="مخزن تجهيز الفاتورة"/>}</div>
  {editing&&kind==='sale'&&<div className="salePaymentChange" role="status"><b>طريقة الدفع: {meta.mode==='cash'?'نقدي':'آجل'}</b>{editing.cash!==(meta.mode==='cash')?<><p>فرق قاصة صاحب الفاتورة عند الحفظ: <bdi>{money((meta.mode==='cash'?amounts.total:0)-(editing.cash?Number(editing.total):0))} د.ع</bdi></p><p>{meta.mode==='cash'?'النقدي يعني قبض كامل قيمة الفاتورة.':'الآجل ينقل قيمة الفاتورة إلى حساب الزبون ويعكس قبضها من القاصة.'} التسديدات المسجّلة بصورة مستقلة تبقى في الحساب؛ راجعها لتجنّب تكرار القبض.</p></>:<p>يمكنك تغيير طريقة الدفع، ويُحدَّث حساب الزبون وقاصة صاحب الفاتورة مع الحفظ.</p>}</div>}
  {kind==='purchase'&&<section className="deskExchange"><InvoiceField label="الصرف المثبّت · د.ع لكل دولار"><MoneyInput aria-label="صرف فاتورة الشراء" value={meta.exchangeRate} disabled={!canEditRate||(purchaseEditing&&(!correction.data||correctionLocks?.exchangeRate))} onChange={value=>change('exchangeRate',value)} placeholder="سعر الصرف المعتمد"/><small>100 دولار = {money(Number(meta.exchangeRate)*100)} د.ع</small></InvoiceField><div><p>عملة حساب المورد: <b>{accountCurrency}</b> · <bdi>{money(draft.accountAmount,accountCurrency)} {currencyLabel(accountCurrency)}</bdi>. تُحفظ الكلفة بالدينار والصرف داخل الوصل.{!canEditRate&&' تغيير الصرف يحتاج صلاحية.'}</p>{meta.mode==='cash'&&<InvoiceField label="عملة الدفع من القاصة"><select aria-label="عملة دفع الشراء" disabled={!!editing} value={meta.cashCurrency} onChange={e=>change('cashCurrency',e.target.value)}><option value="IQD">دينار عراقي IQD</option><option value="USD">دولار أمريكي USD</option></select><small>يُخصم {money(draft.cashAmount,meta.cashCurrency)} {currencyLabel(meta.cashCurrency)}</small>{meta.cashCurrency==='IQD'&&<small className="purchaseOverdraftHint">يمكن أن يصبح رصيد القاصة سالبًا بعد الشراء؛ المقبوضات اللاحقة تضاف إليه تلقائيًا.</small>}</InvoiceField>}</div></section>}
  {kind==='sale'&&<section className={'wholesaleInvoicePolicy'+(wholesale.error?' error':wholesaleHistorical?' historical':'')} aria-label="سياسة أسعار بيع الجملة"><div><strong><AppIcon name="shield" size={18}/>{wholesale.error?'تعذر تأكيد أسعار بيع الجملة':!wholesale.data?'جاري تحميل أسعار بيع الجملة…':!wholesale.data.enabled?'الأسعار المقررة غير مفعّلة':!wholesaleAppliesToSubject(wholesale.data)?(editing?'صاحب الفاتورة غير مشمول بإلزام أسعار الجملة':'حسابك غير مشمول بإلزام أسعار الجملة'):!wholesalePolicyEnforced(wholesale.data)?'صلاحية البيع الحر مفعّلة لهذه الفاتورة':wholesaleHistorical?'الأسعار المحفوظة لهذه الفاتورة':'الحد الأدنى لبيع الجملة'}</strong><p>{wholesale.error||(!wholesale.data?'انتظر تحميل حالة الأسعار قبل الحفظ.':!wholesale.data.enabled?'أسعار المواد المحفوظة تبقى مرجعًا داخليًا، والتطبيق متوقف حاليًا.':!wholesaleAppliesToSubject(wholesale.data)?'تطبق الإدارة الحد الأدنى على حسابات محددة. هذه الفاتورة خارج الاختيار، ويمكن تحديد سعر البيع دون الالتزام بالسعر المقرر.':!wholesalePolicyEnforced(wholesale.data)?'يمكنك تحديد سعر البيع. صلاحية البيع الحر لا تغيّر السعر المقرر المحفوظ للجميع.':wholesaleHistorical?'تعديل البيانات دون تغيير المواد أو الكميات أو الأسعار يحافظ على اتفاق الفاتورة السابق. تغيير المواد أو الكميات أو الأسعار يطبق الحدود الحالية.':'للمواد المؤشّرة حد تحدده الإدارة. لباقي المواد حد يتحدّث مع الكلفة الحالية وسعر الصرف. تقدر تبيع بالحد أو أعلى منه.')}</p>{editing&&wholesale.data?.pricingSubjectName&&<small>سياسة حساب صاحب الفاتورة: {wholesale.data.pricingSubjectName}</small>}{wholesale.loading&&wholesale.data&&<small role="status">جاري تحديث الأسعار…</small>}</div><button type="button" disabled={wholesale.loading} onClick={()=>void wholesale.reload()}>تحديث الأسعار</button></section>}
  <div className="deskBody"><InvoiceCatalog availableOnly={kind!=='purchase'} products={availableProducts} items={items} query={search} onQuery={setSearch} onAdd={p=>{if(!items.some(i=>i.id===p.id))setItems(current=>current.some(i=>i.id===p.id)?current:[{...p,qty:'',price:kind==='sale'&&wholesale.ready?wholesalePriceDefault(wholesale.data,p.id):'',useWholesaleFloor:kind==='sale'},...current]);}}/><InvoiceItems currency={kind==='purchase'?meta.currency:'IQD'} items={items} products={availableProducts} kind={kind} wholesalePricing={wholesaleRules} average={kind==='purchase'&&!editing?average:undefined} onEdit={(id,key,value,useFloor=false)=>setItems(items.map(i=>i.id===id?{...i,[key]:value,...(key==='price'?{useWholesaleFloor:useFloor}:{})}:i))} onRemove={id=>setItems(items.filter(i=>i.id!==id))} landed={landed}/></div>
  <div className="deskFooterFields"><InvoiceField label="المصاريف الإضافية · د.ع"><MoneyInput aria-label="المصاريف الإضافية" value={meta.expenses} onChange={value=>change('expenses',value)}/>{kind==='purchase'?<small>توزّع على المواد قبل احتساب متوسط كلفة المخزون.</small>:<div className={'saleExpenseChoice '+(meta.expensesOnCustomer?'customer':'internal')}><label><input type="checkbox" aria-label="المصاريف على حساب الزبون" aria-describedby={expenseHintId} checked={meta.expensesOnCustomer===true} disabled={saving} onChange={e=>change('expensesOnCustomer',e.target.checked)}/><span>المصاريف على حساب الزبون</span></label><p id={expenseHintId}>{meta.expensesOnCustomer?'تُضاف المصاريف إلى إجمالي الزبون، دون زيادة أو نقصان في ربح الفاتورة.':'لا تُضاف إلى حساب الزبون؛ تُخصم من ربح الفاتورة.'}</p></div>}</InvoiceField><InvoiceField label="ملاحظات الفاتورة"><textarea aria-label="ملاحظات الفاتورة" value={meta.notes} maxLength={4000} onChange={e=>change('notes',e.target.value)}/></InvoiceField></div>
  {kind==='sale'&&<WarrantyEditor value={meta.warranty} items={items} onChange={w=>change('warranty',w)}/>}
  {kind==='sale'&&!editing&&<label className="directPreparationChoice"><input type="checkbox" aria-label="تجهيز مباشر عند حفظ وصل الجملة" checked={meta.directPreparation} onChange={e=>change('directPreparation',e.target.checked)}/><span><b>تجهيز مباشر</b><small>احفظ الوصل بحالة «تم التجهيز» بعد تجهيز جميع مواده من {inventory.warehouseName||'المخزن المحدّد'}.</small></span></label>}
  <InvoiceSummary entries={[...(kind==='sale'?[[items.some(i=>i.personalPriceBasis)?"كلفة المواد المعتمدة":"كلفة المواد حسب الصرف",hasHiddenSaleCost(items)?"—":money(items.reduce((n,i)=>n+Number(i.qty||0)*Number(i.cost||0),0))+' د.ع']]:[]),["عدد الأصناف",items.length],["مجموع الكميات",money(items.reduce((sum,i)=>sum+Number(i.qty||0),0))],["مجموع المواد",money(amounts.sourceSubtotal,meta.currency)+(kind==='purchase'&&meta.currency==='USD'?' $':' د.ع')],...(kind==='purchase'&&meta.currency==='USD'?[["المواد بالدينار",money(amounts.subtotal)+' د.ع']]:[]),...(kind==='sale'?[["مصاريف على الزبون",money(amounts.billedExpenses)+' د.ع'],["مصاريف تخصم من الربح",money(amounts.internalExpenses)+' د.ع'],["صافي ربح الفاتورة",hasHiddenSaleCost(items)?"يُحسب عند الحفظ":money(amounts.profit)+' د.ع']]:[["المصاريف",money(amounts.expenses)+' د.ع']])]} total={display.value} currency={display.currency} secondary={display.currency==='USD'?'كلفة المخزون بالدينار: '+money(amounts.total)+' د.ع':''}/>
  {purchaseEditing&&<div ref={correctionRef}>{correctionConfirmed&&<PurchaseCorrectionReview review={correctionReview} original={editing} payload={correctionPayload}/>}</div>}
  {error&&<p ref={errorRef} tabIndex={-1} className="workflowError purchaseCorrectionInlineError" role="alert">{error}</p>}
  <InvoiceActions saveDisabled={!inventory.ready||(kind==='sale'&&!wholesale.ready)||(purchaseEditing&&(!correction.ready||(correctionConfirmed&&!correctionReview.data.canApply)))} documentHtml={document()} documentName={'فاتورة-'+kind+(editing?'-'+receiptNumber(editing):'-مسودة')} documentEnabled={kind!=='sale'||!!editing} documentNotice={kind==='sale'&&!editing?'احفظ الفاتورة وأرسلها للمخزن لعرض نسخة الزبون الكاملة مع الحساب السابق وآخر تسديد.':''} saving={saving} onSave={save} saveLabel={purchaseEditing?(correctionConfirmed?'تأكيد تعديل الشراء':'معاينة تعديل الشراء'):editing?'حفظ التعديل':kind==='sale'?(meta.directPreparation?'حفظ وتجهيز مباشر':'حفظ وإرسال للمخزن'):'حفظ الوصل'} onCancel={editing?restore:undefined} onPreview={()=>openA4(document())} onPdf={()=>saveA4(document(),'فاتورة-'+kind)} onShare={()=>shareA4('فاتورة-'+kind,'الإجمالي: '+money(display.value,display.currency)+' '+currencyLabel(display.currency),document())} onClear={()=>{if(confirm('تفريغ مواد الفاتورة الحالية؟'))setItems([]);}}>{kind==='sale'&&editing&&<><button onClick={()=>openA4(document(false))}>معاينة نسخة المخزن</button><button onClick={()=>saveA4(document(false),'فاتورة-مخزنية')}>حفظ نسخة المخزن</button></>}</InvoiceActions>
 </InvoiceShell>{renderHistory?.(beginEdit)}</>;
}
