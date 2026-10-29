'use client';
import {useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
export default function WarehouseBadge({status,compact=false}){return <span className={'invoiceWarehouseBadge '+(status==='ready'?'ready':'pending')+(compact?' compact':'')} data-warehouse-status={status==='ready'?'ready':'pending'}>{status==='ready'?'✓ تم التجهيز':'بانتظار التجهيز'}</span>}
export function useWarehouseStatuses(rows,onChanged){
 const [statuses,setStatuses]=useState({}),inputs=useRef(rows),callback=useRef(onChanged),observed=useRef({});inputs.current=rows;callback.current=onChanged;
 const ids=rows.filter(r=>['sale','system'].includes(r.kind)).map(r=>r.id),key=ids.join(',');
 useEffect(()=>{let live=true,busy=false;
  const load=async()=>{if(busy||!ids.length||document.visibilityState==='hidden')return;busy=true;try{
   const responses=await Promise.allSettled(Array.from({length:Math.ceil(ids.length/500)},(_,i)=>supabase.rpc('solar_warehouse_statuses',{invoice_ids:ids.slice(i*500,(i+1)*500)})));
   if(!live)return;const updates={};let changed=false;
   for(const response of responses){if(response.status!=='fulfilled'||response.value.error)continue;for(const r of response.value.data||[]){updates[r.id]=r.status;const original=inputs.current.find(x=>String(x.id)===String(r.id)),prior=observed.current[r.id];if((prior!=null&&prior!==r.revision)||(prior==null&&original&&(original.warehouseStatus||original.warehouse_status||'pending')!==r.status))changed=true;observed.current[r.id]=r.revision;}}
   setStatuses(s=>({...s,...updates}));if(changed)await callback.current?.();
  }catch{}finally{busy=false;}};
  load();const timer=setInterval(load,15000);window.addEventListener('solar-warehouse-changed',load);window.addEventListener('focus',load);window.addEventListener('solar-notification',load);document.addEventListener('visibilitychange',load);
  return()=>{live=false;clearInterval(timer);window.removeEventListener('solar-warehouse-changed',load);window.removeEventListener('focus',load);window.removeEventListener('solar-notification',load);document.removeEventListener('visibilitychange',load);};
 // The invoice IDs define the subscription; callbacks and current rows are refs.
 },[key]);
 return statuses;
}
