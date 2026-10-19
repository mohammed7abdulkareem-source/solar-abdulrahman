import {fxCloudRows} from './fx-utils.mjs';
import {createLatestLoader} from './data-refresh.mjs';
import {changedRows} from './review-utils.mjs';
import {createClient} from '@supabase/supabase-js';

const url='https://afxxaafsuscwyjzrnagc.supabase.co';
const key='sb_publishable_NWfk9al_gjcSnI6NBQX6GA_CGiQ2-Jy';
export const supabase=createClient(url,key);

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
async function allRows(table,select='*',order='id'){
 const rows=[];
 for(let offset=0;;offset+=1000){
  const result=await supabase.from(table).select(select).order(order).range(offset,offset+999);
  if(result.error)return result;
  rows.push(...result.data);
  if(result.data.length<1000)return {data:rows,error:null};
 }
}

const mapProduct=r=>({id:r.id,companyQty:r.companyQty,bookQty:Number(r.bookQty??r.qty??0),reservedQty:Number(r.reservedQty||0),stockRevision:r.stockRevision,code:r.code,name:r.name,brand:r.brands?.name||'',brandId:r.brand_id,category:r.category||'',qty:Number(r.qty||0),cost:Number(r.cost||0),costBasis:r.cost_basis||{},costingRevision:Number(r.costing_revision||0)});
const mapCustomer=r=>({id:r.id,name:r.name,phone:r.phone||'',customerType:r.customer_type==='wholesale'?'جملة - بيع جملة':'مفرد - منظومات',ownerId:r.owner_id||null});
const mapSupplier=r=>({id:r.id,name:r.name,phone:r.phone||'',accountCurrency:r.account_currency||'IQD',currencyRevision:Number(r.currency_revision||0)});
const mapTx=(r,items=[])=>({id:r.id,warehouseId:r.warehouse_id,warehouseName:r.warehouse_name,invoiceAccount:r.invoice_account||null,warehouseQrToken:r.warehouse_qr_token||null,warehouseStatus:r.warehouse_status||'pending',warehouseRevision:Number(r.warehouse_revision||0),warehousePreparedAt:r.warehouse_prepared_at||null,warranty:r.warranty||{enabled:false},warrantyToken:r.warranty_token||null,warrantyRevision:Number(r.warranty_revision||0),cashPurpose:r.cash_purpose||null,receiptNo:r.receipt_no,sourceCurrency:r.source_currency||'IQD',exchangeRate:Number(r.exchange_rate||1),sourceSubtotal:r.source_subtotal==null?null:Number(r.source_subtotal),fxPricing:!!r.fx_pricing,pricingRevision:Number(r.pricing_revision||0),accountCurrency:r.account_currency||'IQD',accountAmount:Number(r.account_amount||0),accountRevision:Number(r.account_revision||0),marketRate:Number(r.market_rate||1),cashCurrency:r.cash_currency||'IQD',cashAmount:Number(r.cash_amount||0),fxAccounted:!!r.fx_accounted,systemInvoiceId:r.system_invoice_id??null,kind:r.kind,party:r.party_name||'',partyId:r.party_id,createdBy:r.created_by||null,installerId:r.installer_id||null,installDate:r.install_date||'',installTime:r.install_time||'',customerPhone:r.customer_phone||'',customerAddress:r.customer_address||'',installationStatus:r.installation_status||'none',installationCompletedAt:r.installation_completed_at||null,installationClosedAt:r.installation_closed_at||null,installationExpenses:Number(r.installation_expenses||0),installationExpenseNotes:r.installation_expense_notes||'',cashboxUserId:r.cashbox_user_id||null,capitalEffect:!!r.capital_effect,total:Number(r.total||0),subtotal:Number(r.subtotal||0),expenses:Number(r.expenses||0),cost:Number(r.cost||0),profit:Number(r.profit||0),cash:!!r.cash,notes:r.notes||'',mode:r.payment_mode||'',date:r.created_at,items:items.map(i=>({id:i.product_id,name:i.product_name,brand:i.brand_name||'',category:i.category||'',qty:Number(i.qty||0),price:Number(i.price||0),cost:Number(i.cost||0),landedCost:Number(i.landed_cost||0),sourcePrice:i.source_price==null?null:Number(i.source_price),costBasis:i.cost_basis||{}}))});

const loadSnapshot=createLatestLoader(async userId=>{
 const {data:profile,error:profileError}=await supabase.from('profiles').select('active,user_type').eq('id',userId).single();
 if(profileError)throw profileError;
 if(!profile.active||['installer','warehouse'].includes(profile.user_type))return {userId,brands:[],products:[],customers:[],suppliers:[],tx:[]};

 const [b,p,c,s,t,ti,ce,fx]=await Promise.all([
  allRows('brands'),
  supabase.rpc('solar_inventory',{action:'catalog'}),
  allRows('customers'),
  allRows('suppliers'),
  allRows('transactions'),
  allRows('transaction_items'),
  allRows('solar_cash_entries'),
  supabase.rpc('solar_fx',{action:'state'})
 ]);
 for(const x of [b,p,c,s,t,ti,ce,fx])if(x.error)throw x.error;
 const entries=ce.data.map(r=>({id:'cash:'+r.id,systemCash:true,kind:r.entry_type,cash:true,cashDelta:Number(r.delta),total:Math.abs(Number(r.delta)),cashboxUserId:r.owner_id,createdBy:r.owner_id,notes:r.notes||'',date:r.created_at,jobId:r.job_id}));
 const byInvoice=new Map();for(const item of ti.data){const list=byInvoice.get(item.transaction_id)||[];list.push(item);byInvoice.set(item.transaction_id,list);}
 return {userId,brands:b.data.map(x=>({id:x.id,name:x.name})),products:p.data.map(mapProduct),customers:c.data.map(mapCustomer),suppliers:s.data.map(mapSupplier),tx:[...t.data.map(x=>mapTx(x,byInvoice.get(x.id)||[])),...entries,...fxCloudRows(fx.data)].sort((a,b)=>new Date(a.date)-new Date(b.date))};
});
export async function loadCloud(options={}){
 const {data,error}=await supabase.auth.getSession();if(error)throw error;
 if(!data.session)return {userId:null,brands:[],products:[],customers:[],suppliers:[],tx:[]};
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
