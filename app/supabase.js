import {createClient} from '@supabase/supabase-js';

const url='https://afxxaafsuscwyjzrnagc.supabase.co';
const key='sb_publishable_NWfk9al_gjcSnI6NBQX6GA_CGiQ2-Jy';
export const supabase=createClient(url,key);

const mapProduct=r=>({id:r.id,code:r.code,name:r.name,brand:r.brands?.name||'',brandId:r.brand_id,category:r.category||'',qty:Number(r.qty||0),cost:Number(r.cost||0)});
const mapCustomer=r=>({id:r.id,name:r.name,phone:r.phone||'',customerType:r.customer_type==='wholesale'?'جملة - بيع جملة':'مفرد - منظومات',ownerId:r.owner_id||null});
const mapSupplier=r=>({id:r.id,name:r.name,phone:r.phone||''});
const mapTx=(r,items=[])=>({id:r.id,kind:r.kind,party:r.party_name||'',partyId:r.party_id,createdBy:r.created_by||null,cashboxUserId:r.cashbox_user_id||null,capitalEffect:!!r.capital_effect,total:Number(r.total||0),subtotal:Number(r.subtotal||0),expenses:Number(r.expenses||0),cost:Number(r.cost||0),profit:Number(r.profit||0),cash:!!r.cash,notes:r.notes||'',mode:r.payment_mode||'',date:r.created_at,items:items.filter(i=>i.transaction_id===r.id).map(i=>({id:i.product_id,name:i.product_name,brand:i.brand_name||'',category:i.category||'',qty:Number(i.qty||0),price:Number(i.price||0),cost:Number(i.cost||0),landedCost:Number(i.landed_cost||0)}))});

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
async function replace(table,rows){const d=await supabase.from(table).delete().gte('id',0);if(d.error)throw d.error;if(rows.length){const i=await supabase.from(table).insert(rows);if(i.error)throw i.error}}
export async function saveCloud(k,v){
 if(k==='solar_brands'){await replace('brands',v.map(x=>({id:x.id,name:x.name})));return}
 if(k==='solar_customers'){await replace('customers',v.map(x=>({id:x.id,name:x.name,phone:x.phone||null,customer_type:String(x.customerType||'').includes('جملة')?'wholesale':'system',owner_id:x.ownerId||null})));return}
 if(k==='solar_suppliers'){await replace('suppliers',v.map(x=>({id:x.id,name:x.name,phone:x.phone||null})));return}
 if(k==='solar_products'){
  const brands=(await supabase.from('brands').select('*')).data||[];
  await replace('products',v.map(x=>({id:x.id,code:String(x.code),name:x.name,brand_id:brands.find(b=>b.name===x.brand)?.id||null,category:x.category||null,qty:+x.qty||0,cost:+x.cost||0})));return
 }
 if(k==='solar_tx'){
  const oldItems=await supabase.from('transaction_items').delete().gte('id',0);if(oldItems.error)throw oldItems.error;
  const oldTx=await supabase.from('transactions').delete().gte('id',0);if(oldTx.error)throw oldTx.error;
  if(!v.length)return;
  const txRows=v.map(x=>({id:x.id,kind:x.kind,party_name:x.party||null,payment_mode:x.mode||null,created_by:x.createdBy||null,cashbox_user_id:x.cashboxUserId||x.createdBy||null,capital_effect:!!x.capitalEffect,subtotal:+x.subtotal||0,expenses:+x.expenses||0,total:+x.total||0,cost:+x.cost||0,profit:+x.profit||0,notes:x.notes||null,cash:!!x.cash,created_at:x.date||new Date().toISOString()}));
  const ins=await supabase.from('transactions').insert(txRows);if(ins.error)throw ins.error;
  const itemRows=v.flatMap(x=>(x.items||[]).map(i=>({transaction_id:x.id,product_id:i.id||null,product_name:i.name||'',brand_name:i.brand||null,category:i.category||null,qty:+i.qty||0,price:+i.price||0,cost:+i.cost||0,landed_cost:+i.landedCost||0})));
  if(itemRows.length){const ii=await supabase.from('transaction_items').insert(itemRows);if(ii.error)throw ii.error}
 }
}
