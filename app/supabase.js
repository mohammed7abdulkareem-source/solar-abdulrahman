import {saleExpensesOnCustomer} from './currency-utils.mjs';
import {purchaseUnitPrice} from './money-format.mjs';
import {transactionColumns} from './cloud-snapshot-columns.mjs';
import {fxCloudRows} from './fx-utils.mjs';
import {refreshMaterialBrands} from './current-brand.mjs';
import {createLatestLoader} from './data-refresh.mjs';
import {changedRows} from './review-utils.mjs';
import {createClient} from '@supabase/supabase-js';
import {createSessionFetch,guardSessionAdoption} from './auth-session-fetch.mjs';
import {requestPasswordSession} from './password-login.mjs';
import {cashBalanceSnapshot} from './cash-read-balances.mjs';
import {cloudSnapshotAccess} from './cloud-snapshot-access.mjs';
import {canManageQuotes} from './access-utils.mjs';
import {usesPersonalSalePrices} from './inventory-valuation.mjs';
import {salesAuthorizationKey} from './sales-read-scope.mjs';

const url='https://afxxaafsuscwyjzrnagc.supabase.co';
const key='sb_publishable_NWfk9al_gjcSnI6NBQX6GA_CGiQ2-Jy';
export const supabase=createClient(url,key,{global:{fetch:createSessionFetch()}});

export async function loginWithPassword(login,password,signal){
 const tokens=await requestPasswordSession(url+'/functions/v1/solar-login',key,{login,password},signal);
 if(signal.aborted)return;
 try{
  const {data,error}=await guardSessionAdoption(tokens.access_token,signal,()=>supabase.auth.setSession(tokens));
  if(error||!data?.session)throw new Error();
 }catch{
  if(!signal.aborted)throw new Error('تم التحقق من كلمة المرور، وتعذّر فتح الجلسة على هذا الجهاز. حاول تسجيل الدخول مرة ثانية.');
 }
}

// Verify in an isolated, non-persistent session. The reset endpoint repeats this
// check server-side when executing, after the user's final confirmation.
export async function verifyResetPassword(password){
 const {data:current,error:currentError}=await supabase.auth.getUser();
 if(currentError||!current?.user?.email)throw new Error('تعذر التحقق من الحساب. سجّل الدخول مجدداً.');
 const verifier=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false,storageKey:'solar-reset-password-check'}});
 try{
  const {data,error}=await verifier.auth.signInWithPassword({email:current.user.email,password});
  if(error||data?.user?.id!==current.user.id)throw new Error('الباسورد غير صحيح أو تعذر التحقق منه. لم يتم تصفير أي بيانات.');
 }finally{await verifier.auth.signOut({scope:'local'}).catch(()=>{});}
}


// Financial totals and customer search must not stop at the API's 1,000-row cap.
async function allRows(table,select='*',filter=null){
 const rows=[];
 for(let offset=0;;offset+=1000){
  let query=supabase.from(table).select(select);
  if(filter)query=query.in(filter.column,filter.values);
  const result=await query.order('id').range(offset,offset+999);
  if(result.error)return result;
  rows.push(...result.data);
  if(result.data.length<1000)return {data:rows,error:null};
 }
}

async function personalReceiptRows(kinds){
 const headers=[],items=[];
 let afterId=null;
 while(true){
  const result=await supabase.rpc('solar_personal_receipt_snapshot',{after_id:afterId,kinds});
  if(result.error)return result;
  for(const receipt of result.data){
   headers.push(receipt.header);
   items.push(...receipt.items);
  }
  if(result.data.length<200)return {data:headers,items,error:null};
  afterId=headers.at(-1).id;
 }
}

function visibleProductCost(row){
 return row.personalPriceBasis&&row.cost==null?null:Number(row.cost||0);
}

const mapProduct=r=>({id:r.id,companyQty:r.companyQty,bookQty:Number(r.bookQty??r.qty??0),reservedQty:Number(r.reservedQty||0),stockRevision:r.stockRevision,code:r.code,name:r.name,brand:r.brands?.name||'',brandId:r.brand_id,category:r.category||'',qty:Number(r.qty||0),...(r.personalPriceBasis?{personalPriceBasis:true}:{}),cost:visibleProductCost(r),bookCost:r.personalPriceBasis?visibleProductCost(r):Number(r.bookCost??r.cost??0),costBasis:r.cost_basis||{},costingRevision:Number(r.costing_revision||0)});
const mapCustomer=r=>({id:r.id,name:r.name,phone:r.phone||'',customerType:r.customer_type==='wholesale'?'جملة - بيع جملة':'مفرد - منظومات',ownerId:r.owner_id||null});
const mapSupplier=r=>({id:r.id,name:r.name,phone:r.phone||'',accountCurrency:r.account_currency||'IQD',currencyRevision:Number(r.currency_revision||0)});
const mapTx=(r,items=[])=>({id:r.id,...(r.personalCostHidden?{personalCostHidden:true}:{}),...(r.kind==='sale'?{expensesOnCustomer:saleExpensesOnCustomer(r)}:{}),warehouseId:r.warehouse_id,warehouseName:r.warehouse_name,invoiceAccount:r.invoice_account||null,profitSettlementId:r.profit_settlement_id||null,profitSupplierSettlementId:r.profit_supplier_settlement_id||null,profitSupplierOwnerId:r.profit_supplier_owner_id||null,warehouseQrToken:r.warehouse_qr_token||null,warehouseStatus:r.warehouse_status||'pending',warehouseRevision:Number(r.warehouse_revision||0),warehousePreparedAt:r.warehouse_prepared_at||null,warranty:r.warranty||{enabled:false},warrantyToken:r.warranty_token||null,warrantyRevision:Number(r.warranty_revision||0),cashPurpose:r.cash_purpose||null,receiptNo:r.receipt_no,sourceCurrency:r.source_currency||'IQD',exchangeRate:Number(r.exchange_rate||1),sourceSubtotal:r.source_subtotal==null?null:Number(r.source_subtotal),fxPricing:!!r.fx_pricing,pricingRevision:Number(r.pricing_revision||0),systemMarkupPercent:r.system_min_profit_percent==null?null:Number(r.system_min_profit_percent),systemPricingRevision:r.system_pricing_revision==null?null:Number(r.system_pricing_revision),accountCurrency:r.account_currency||'IQD',accountAmount:Number(r.account_amount||0),accountRevision:Number(r.account_revision||0),marketRate:Number(r.market_rate||1),cashCurrency:r.cash_currency||'IQD',cashAmount:Number(r.cash_amount||0),fxAccounted:!!r.fx_accounted,systemInvoiceId:r.system_invoice_id??null,kind:r.kind,party:r.party_name||'',partyId:r.party_id,createdBy:r.created_by||null,installerId:r.installer_id||null,installDate:r.install_date||'',installTime:r.install_time||'',customerPhone:r.customer_phone||'',customerAddress:r.customer_address||'',installationStatus:r.installation_status||'none',installationCompletedAt:r.installation_completed_at||null,installationClosedAt:r.installation_closed_at||null,installationExpenses:Number(r.installation_expenses||0),installationExpenseNotes:r.installation_expense_notes||'',cashboxUserId:r.cashbox_user_id||null,capitalEffect:!!r.capital_effect,total:Number(r.total||0),subtotal:Number(r.subtotal||0),expenses:Number(r.expenses||0),cost:r.personalCostHidden&&r.cost==null?null:Number(r.cost||0),profit:r.personalCostHidden&&r.profit==null?null:Number(r.profit||0),cash:!!r.cash,notes:r.notes||'',mode:r.payment_mode||'',date:r.created_at,items:items.map(i=>({id:i.product_id,name:i.product_name,brand:i.brand_name||'',category:i.category||'',qty:Number(i.qty||0),...(i.personalCostHidden?{personalCostHidden:true}:{}),...(i.personalPriceBasis?{personalPriceBasis:true}:{}),price:i.personalCostHidden&&i.price==null?null:Number(i.price||0),cost:i.personalCostHidden&&i.cost==null?null:Number(i.cost||0),landedCost:i.personalCostHidden?null:Number(i.landed_cost||0),sourcePrice:r.kind==='purchase'&&i.personalCostHidden?null:r.kind==='purchase'?purchaseUnitPrice(i,r.source_currency,r.exchange_rate):i.source_price==null?null:Number(i.source_price),costBasis:i.cost_basis||{}}))});

const loadSnapshot=createLatestLoader(async userId=>{
 const {data:profile,error:profileError}=await supabase.from('profiles').select('id,active,user_type,is_admin,permissions').eq('id',userId).single();
 if(profileError)throw profileError;
 const access=cloudSnapshotAccess(profile),authorizationKey=salesAuthorizationKey(profile);
 const personal=usesPersonalSalePrices(profile);
 const empty={data:[],error:null};
 const kindFilter=kinds=>kinds?{column:'kind',values:kinds}:null;
 const [b,p,c,s,t,ti,ce,fx,contacts,balances,personalReceipts]=await Promise.all([
  access.brands?allRows('brands','id,name'):empty,
  access.catalog?supabase.rpc('solar_inventory',{action:'catalog'}):empty,
  access.customers?allRows('customers','id,name,phone,customer_type,owner_id'):empty,
  access.suppliers?allRows('suppliers','id,name,phone,account_currency,currency_revision'):empty,
  access.transactions?allRows('transactions',transactionColumns,kindFilter(access.transactionKinds)):empty,
  access.items&&!personal?allRows('transaction_items',access.itemKinds?'*,receipt:transactions!inner(kind)':'*',
   access.itemKinds?{column:'receipt.kind',values:access.itemKinds}:null):empty,
  access.cashEntries?allRows('solar_cash_entries','id,owner_id,entry_type,delta,notes,created_at,job_id'):empty,
  access.fxHistory?supabase.rpc('solar_fx',{action:'state'}):empty,
  access.receiptContacts?supabase.rpc('solar_receipt_contacts'):empty,
  access.cashBalances?supabase.rpc('solar_cash_read_balances'):empty,
  personal&&access.items?personalReceiptRows(access.itemKinds):empty
 ]);
 for(const x of [b,p,c,s,t,ti,ce,fx,contacts,balances,personalReceipts])if(x.error)throw x.error;
 const formerSeller=!personal&&access.items&&contacts.data.some(row=>row.id===userId&&row.hasPersonalReceipts);
 const receipts=formerSeller?await personalReceiptRows(access.itemKinds):personalReceipts;
 if(receipts.error)throw receipts.error;
 const cashBalances=access.cashBalances?cashBalanceSnapshot(balances.data,profile):null;
 const products=access.catalog==='quote'?p.data.map(r=>({
  id:r.id,code:r.code,name:r.name,brand:r.brands?.name||r.brand||'',category:r.category||'',
  ...(canManageQuotes(profile)?{cost:visibleProductCost(r),...(r.personalPriceBasis?{personalPriceBasis:true}:{})}:{})
 })):p.data.map(mapProduct);
 const entries=ce.data.map(r=>({id:'cash:'+r.id,systemCash:true,kind:r.entry_type,cash:true,cashDelta:Number(r.delta),total:Math.abs(Number(r.delta)),cashboxUserId:r.owner_id,createdBy:r.owner_id,notes:r.notes||'',date:r.created_at,jobId:r.job_id}));
 const contactsByCreator=new Map(contacts.data.map(r=>[r.id,{creatorName:r.creatorName,creatorPhone:r.creatorPhone}]));
 const transactions=[...t.data,...receipts.data];
 const byInvoice=new Map();for(const item of refreshMaterialBrands([...ti.data,...(receipts.items||[])],p.data)){const list=byInvoice.get(item.transaction_id)||[];list.push(item);byInvoice.set(item.transaction_id,list);}
 return {userId,authorizationKey,cashBalances,brands:b.data.map(x=>({id:x.id,name:x.name})),products,customers:c.data.map(mapCustomer),suppliers:s.data.map(mapSupplier),tx:[...transactions.map(x=>({...mapTx(x,byInvoice.get(x.id)||[]),...(contactsByCreator.get(x.created_by||x.cashbox_user_id)||{})})),...entries,...fxCloudRows(fx.data)].sort((a,b)=>new Date(a.date)-new Date(b.date))};
});
export async function loadCloud(options={}){
 const {data,error}=await supabase.auth.getSession();if(error)throw error;
 if(!data.session)return {userId:null,authorizationKey:salesAuthorizationKey(null),brands:[],products:[],customers:[],suppliers:[],tx:[],cashBalances:null};
 return loadSnapshot(data.session.user.id,options);
}
let pendingSaves=[];
let saveQueue=Promise.resolve();
export function saveCloud(k,next,previous){
 return new Promise((resolve,reject)=>{
  pendingSaves.push({prepare:()=>buildChanges(k,next,previous),resolve,reject});
  if(pendingSaves.length!==1)return;
  setTimeout(()=>{
   const batch=pendingSaves;pendingSaves=[];
   const run=async()=>{
    try{const changes=(await Promise.all(batch.map(job=>job.prepare()))).flat();
     for(const change of changes.filter(x=>x.table==='products')){
      const result=await supabase.rpc('solar_inventory',{action:'catalog_save',request_id:crypto.randomUUID(),payload:{rows:change.rows||[],removed:change.removed||[]}});if(result.error)throw result.error;
     }
     const regular=changes.filter(x=>x.table!=='products');
     let receipts=[];
     if(regular.length){const {data,error}=await supabase.rpc('solar_save_rows_with_receipts',{changes:regular});if(error)throw error;receipts=data||[]}
     batch.forEach(job=>job.resolve(receipts));
    }catch(error){batch.forEach(job=>job.reject(error))}
   };
   saveQueue=saveQueue.then(run,run);
  },0);
 });
}
async function buildChanges(k,next,previous){
 const changes=[];const replace=async(table,rows,removed=[])=>{changes.push({table,rows,removed})};
 if(!Array.isArray(previous))throw new Error('Missing save baseline');
 const {changed:v,removed}=changedRows(previous.filter(x=>!x.systemCash),next.filter(x=>!x.systemCash));
 if(!v.length&&!removed.length)return changes;
 if(k==='solar_brands'){await replace('brands',v.map(x=>({id:x.id,name:x.name})),removed);return changes}
 if(k==='solar_customers'){await replace('customers',v.map(x=>({id:x.id,name:x.name,phone:x.phone||null,customer_type:String(x.customerType||'').includes('جملة')?'wholesale':'system',owner_id:x.ownerId||null})),removed);return changes}
 if(k==='solar_suppliers'){await replace('suppliers',v.map(x=>({id:x.id,name:x.name,phone:x.phone||null})),removed);return changes}
 if(k==='solar_products'){
  const result=await supabase.from('brands').select('*');if(result.error)throw result.error;const brands=result.data||[];
  await replace('products',v.map(x=>({id:x.id,code:String(x.code),name:x.name,brand_id:brands.find(b=>b.name===x.brand)?.id||null,category:x.category||null,...(!previous.some(p=>p.id===x.id)||Number(previous.find(p=>p.id===x.id)?.qty)!==Number(x.qty)?{qty:+x.qty||0}:{}),...(!previous.some(p=>p.id===x.id)||Number(previous.find(p=>p.id===x.id)?.cost)!==Number(x.cost)?{cost:+x.cost||0}:{})})),removed);return changes
 }
 if(k==='solar_tx'){
  if(removed.length){changes.push({table:'transaction_items',removeTransactionIds:removed});changes.push({table:'transactions',removed})}
  if(!v.length)return changes;
  const txRows=v.map(x=>({id:x.id,kind:x.kind,party_name:x.party||null,payment_mode:x.mode||null,created_by:x.createdBy||null,installer_id:x.installerId||null,install_date:x.installDate||null,install_time:x.installTime||null,customer_phone:x.customerPhone||null,customer_address:x.customerAddress||null,installation_status:x.installationStatus||'none',installation_completed_at:x.installationCompletedAt||null,installation_closed_at:x.installationClosedAt||null,installation_expenses:Number(x.installationExpenses||0),installation_expense_notes:x.installationExpenseNotes||null,cashbox_user_id:x.cashboxUserId||x.createdBy||null,capital_effect:!!x.capitalEffect,subtotal:+x.subtotal||0,expenses:+x.expenses||0,total:+x.total||0,cost:+x.cost||0,profit:+x.profit||0,notes:x.notes||null,cash:!!x.cash,created_at:x.date||new Date().toISOString()}));
  changes.push({table:'transactions',rows:txRows});
  const itemChanges=v.filter(x=>JSON.stringify(x.items||[])!==JSON.stringify(previous.find(p=>p.id===x.id)?.items||[]));
  // Status/notes changes do not touch invoice lines.
  const existingIds=itemChanges.filter(x=>previous.some(p=>p.id===x.id)).map(x=>x.id);

  const itemRows=itemChanges.flatMap(x=>(x.items||[]).map(i=>({transaction_id:x.id,product_id:i.id||null,product_name:i.name||'',brand_name:i.brand||null,category:i.category||null,qty:+i.qty||0,price:+i.price||0,cost:+i.cost||0,landed_cost:+i.landedCost||0})));
  if(itemRows.length||existingIds.length)changes.push({table:'transaction_items',rows:itemRows,removeTransactionIds:existingIds});
 }
 return changes;
}
