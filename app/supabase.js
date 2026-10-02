import {changedRows} from './review-utils.mjs';
import {createClient} from '@supabase/supabase-js';

const url='https://afxxaafsuscwyjzrnagc.supabase.co';
const key='sb_publishable_NWfk9al_gjcSnI6NBQX6GA_CGiQ2-Jy';
export const supabase=createClient(url,key);

const mapProduct=r=>({id:r.id,code:r.code,name:r.name,brand:r.brands?.name||'',brandId:r.brand_id,category:r.category||'',qty:Number(r.qty||0),cost:Number(r.cost||0)});
const mapCustomer=r=>({id:r.id,name:r.name,phone:r.phone||'',customerType:r.customer_type==='wholesale'?'جملة - بيع جملة':'مفرد - منظومات',ownerId:r.owner_id||null});
const mapSupplier=r=>({id:r.id,name:r.name,phone:r.phone||''});
const mapTx=(r,items=[])=>({id:r.id,kind:r.kind,party:r.party_name||'',partyId:r.party_id,createdBy:r.created_by||null,installerId:r.installer_id||null,installDate:r.install_date||'',installTime:r.install_time||'',customerPhone:r.customer_phone||'',customerAddress:r.customer_address||'',installationStatus:r.installation_status||'none',installationCompletedAt:r.installation_completed_at||null,installationClosedAt:r.installation_closed_at||null,installationExpenses:Number(r.installation_expenses||0),installationExpenseNotes:r.installation_expense_notes||'',cashboxUserId:r.cashbox_user_id||null,capitalEffect:!!r.capital_effect,total:Number(r.total||0),subtotal:Number(r.subtotal||0),expenses:Number(r.expenses||0),cost:Number(r.cost||0),profit:Number(r.profit||0),cash:!!r.cash,notes:r.notes||'',mode:r.payment_mode||'',date:r.created_at,items:items.filter(i=>i.transaction_id===r.id).map(i=>({id:i.product_id,name:i.product_name,brand:i.brand_name||'',category:i.category||'',qty:Number(i.qty||0),price:Number(i.price||0),cost:Number(i.cost||0),landedCost:Number(i.landed_cost||0)}))});

export async function loadCloud(){
 const [b,p,c,s,t,ti]=await Promise.all([
  supabase.from('brands').select('*').order('id'),
  supabase.from('products').select('*,brands(name)').order('id'),
  supabase.from('customers').select('*').order('id'),
  supabase.from('suppliers').select('*').order('id'),
  supabase.from('transactions').select('*').order('created_at'),
  supabase.from('transaction_items').select('*').order('id')
 ]);
 for(const x of [b,p,c,s,t,ti])if(x.error)throw x.error;
 return {brands:b.data.map(x=>({id:x.id,name:x.name})),products:p.data.map(mapProduct),customers:c.data.map(mapCustomer),suppliers:s.data.map(mapSupplier),tx:t.data.map(x=>mapTx(x,ti.data))};
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
     if(changes.length){const {error}=await supabase.rpc('solar_save_rows_v31',{changes});if(error)throw error}
     batch.forEach(job=>job.resolve());
    }catch(error){batch.forEach(job=>job.reject(error))}
   };
   saveQueue=saveQueue.then(run,run);
  },0);
 });
}
async function buildChanges(k,next,previous){
 const changes=[];const replace=async(table,rows,removed=[])=>{changes.push({table,rows,removed})};
 if(!Array.isArray(previous))throw new Error('Missing save baseline');
 const {changed:v,removed}=changedRows(previous,next);
 if(!v.length&&!removed.length)return changes;
 if(k==='solar_brands'){await replace('brands',v.map(x=>({id:x.id,name:x.name})),removed);return changes}
 if(k==='solar_customers'){await replace('customers',v.map(x=>({id:x.id,name:x.name,phone:x.phone||null,customer_type:String(x.customerType||'').includes('جملة')?'wholesale':'system',owner_id:x.ownerId||null})),removed);return changes}
 if(k==='solar_suppliers'){await replace('suppliers',v.map(x=>({id:x.id,name:x.name,phone:x.phone||null})),removed);return changes}
 if(k==='solar_products'){
  const result=await supabase.from('brands').select('*');if(result.error)throw result.error;const brands=result.data||[];
  await replace('products',v.map(x=>({id:x.id,code:String(x.code),name:x.name,brand_id:brands.find(b=>b.name===x.brand)?.id||null,category:x.category||null,qty:+x.qty||0,cost:+x.cost||0})),removed);return changes
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
