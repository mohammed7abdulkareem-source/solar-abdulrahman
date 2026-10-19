'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';

export async function inventoryCall(action,payload={},requestId=null){
 const {data,error}=await supabase.rpc('solar_inventory',{action,payload,request_id:requestId});
 if(error)throw error;return data;
}
export function useInventoryRequest(){
 const attempt=useRef(null);
 return async(action,payload)=>{
  const key=JSON.stringify({action,payload});
  if(attempt.current&&attempt.current.key!==key)throw new Error('أعد تأكيد العملية السابقة بنفس البيانات أولاً.');
  if(!attempt.current)attempt.current={key,id:crypto.randomUUID()};
  try{const result=await inventoryCall(action,payload,attempt.current.id);attempt.current=null;return result;}
  catch(error){if(error.code)attempt.current=null;throw error;}
 };
}
export function useWarehouseInventory({aggregate=false,versionKey}={}){
 const [warehouseId,setWarehouse]=useState(''),[version,setVersion]=useState(0),[data,setData]=useState(null),[loaded,setLoaded]=useState(null),[loading,setLoading]=useState(true),[error,setError]=useState('');
 const generation=useRef(0);
 const refresh=useCallback(()=>setVersion(v=>v+1),[]);
 useEffect(()=>{const id=++generation.current;let live=true;setLoading(true);setError('');
  inventoryCall('stock',{warehouseId:warehouseId?Number(warehouseId):null}).then(result=>{
   if(!live||id!==generation.current)return;
   setData(result);
   if(!aggregate&&!warehouseId){const first=result.warehouses.find(w=>w.active);if(first){setWarehouse(String(first.id));return;}}
   setLoaded(warehouseId);setLoading(false);
  }).catch(e=>{if(live&&id===generation.current){setError(e.message||'تعذر تحميل المخازن');setLoading(false);setLoaded(null);}});
  return()=>{live=false;};
 },[warehouseId,version,aggregate,versionKey]);
 const ready=!loading&&loaded===warehouseId&&!error;
 const products=loaded===warehouseId&&!error?(data?.products||[]).map(p=>({...p,brand:p.brand||p.brands?.name||'',brandId:p.brand_id,costBasis:p.cost_basis||{},costingRevision:p.costing_revision||0})):[];
 return {...data,products,warehouses:data?.warehouses||[],warehouseId,warehouseName:data?.warehouses.find(w=>String(w.id)===warehouseId)?.name||'',setWarehouse,loading:loading||(!error&&loaded!==warehouseId),error,ready,refresh};
}
export function WarehouseField({inventory,disabled=false,label='مخزن الفاتورة',allowAll=false}){
 return <label className="warehouseLocationField">{label}<select aria-label={label} disabled={disabled||(!inventory.warehouses.length&&inventory.loading)} value={inventory.warehouseId} onChange={e=>inventory.setWarehouse(e.target.value)}>
  <option value="" disabled={!allowAll}>{allowAll?'جميع المخازن المسموحة':'اختر المخزن'}</option>
  {inventory.warehouses.filter(w=>w.active||String(w.id)===inventory.warehouseId).map(w=><option key={w.id} value={w.id}>{w.name}</option>)}
 </select>{inventory.loading&&<small role="status">جاري تحديث رصيد المخزن…</small>}{inventory.error&&<small role="alert">{inventory.error} <button type="button" onClick={inventory.refresh}>إعادة المحاولة</button></small>}</label>;
}
