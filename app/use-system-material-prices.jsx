'use client';
import {useCallback,useEffect,useMemo,useState} from 'react';
import {supabase} from './supabase';
import {VALUATION_EVENT} from './valuation-events.mjs';
import {systemMaterialPriceMap} from './system-pricing-utils.mjs';

export async function readSystemMaterialPrices(ids,invoiceId,signal){
 const {data,error}=await supabase.rpc('solar_system_material_prices',{product_ids:ids,invoice_id:invoiceId}).abortSignal(signal);
 if(error)throw error;
 return systemMaterialPriceMap(data,ids);
}

export function useSystemMaterialPrices(items,invoiceId,scope){
 const ids=JSON.stringify([...new Set(items.map(item=>Number(item.id)))].sort((a,b)=>a-b));
 const key=JSON.stringify([scope,invoiceId,ids]);
 const [request,setRequest]=useState(0),[snapshot,setSnapshot]=useState(null);
 const refresh=useCallback(()=>setRequest(n=>n+1),[]);
 useEffect(()=>{
  const visible=()=>{if(!document.hidden)refresh();};
  const events=['focus','online','solar-wholesale-pricing','solar-notification',VALUATION_EVENT];
  for(const name of events)window.addEventListener(name,visible);
  document.addEventListener('visibilitychange',visible);
  const polling=setInterval(visible,30000);
  return ()=>{clearInterval(polling);document.removeEventListener('visibilitychange',visible);for(const name of events)window.removeEventListener(name,visible);};
 },[refresh]);
 useEffect(()=>{
  const productIds=JSON.parse(ids);
  if(!productIds.length)return;
  const controller=new AbortController();let current=true;
  const timeout=setTimeout(()=>controller.abort(),15000);
  async function load(){
   try{
    const {prices,tokens}=await readSystemMaterialPrices(productIds,invoiceId,controller.signal);
    if(current)setSnapshot({key,request,prices,tokens});
   }catch(error){
    if(current)setSnapshot({key,request,error:controller.signal.aborted?'تعذّر تحديث أسعار المواد. أعد المحاولة.':error.message||'تعذّر تحميل أسعار المواد.'});
   }finally{clearTimeout(timeout);}
  }
  void load();
  return ()=>{current=false;clearTimeout(timeout);controller.abort();};
 },[key,ids,invoiceId,request]);
 const active=snapshot?.key===key&&snapshot.request===request?snapshot:null;
 const priced=useMemo(()=>items.map(item=>({...item,materialPrice:active?.prices?.get(String(item.id))??null})),[items,active]);
 return {items:priced,tokens:invoiceId==null?active?.tokens:undefined,ready:ids==='[]'||!!active?.prices,error:active?.error,refresh};
}
