'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import {wholesalePricingReady} from './wholesale-invoice-pricing.mjs';

export function useWholesaleSalePricing({userId,enabled=true}){
 const [snapshot,setSnapshot]=useState(null),[error,setError]=useState(''),[loading,setLoading]=useState(false),sequence=useRef(0),controller=useRef(null);
 const reload=useCallback(async()=>{
  if(!enabled||!userId)return null;
  const request=++sequence.current,abort=new AbortController();controller.current?.abort();controller.current=abort;
  setLoading(true);setError('');
  const timeout=setTimeout(()=>abort.abort(),15000);
  try{
   const {data,error}=await supabase.rpc('solar_wholesale_pricing',{action:'state',request_id:null,payload:{}}).abortSignal(abort.signal);
   if(error)throw error;
   if(!wholesalePricingReady(data))throw new Error('تعذر تأكيد بيانات أسعار بيع الجملة.');
   if(request!==sequence.current)return null;
   setSnapshot({userId,data});return data;
  }catch(failure){if(request===sequence.current){setError(abort.signal.aborted?'تعذر تحديث أسعار بيع الجملة الآن. أعد المحاولة.':failure.message||'تعذر تحميل أسعار بيع الجملة.');}return null;}
  finally{clearTimeout(timeout);if(request===sequence.current)setLoading(false);}
 },[enabled,userId]);
 useEffect(()=>{
  setSnapshot(null);setError('');
  if(!enabled||!userId){setLoading(false);return;}
  void reload();
  const refresh=()=>{if(document.visibilityState==='visible')void reload();};
  const offline=()=>{++sequence.current;controller.current?.abort();setLoading(false);setError('الاتصال غير متاح. حدّث أسعار بيع الجملة عند عودة الاتصال.');};
  window.addEventListener('focus',refresh);window.addEventListener('online',refresh);window.addEventListener('offline',offline);window.addEventListener('solar-wholesale-pricing',refresh);window.addEventListener('solar-notification',refresh);
  const timer=setInterval(refresh,30000);
  return()=>{++sequence.current;controller.current?.abort();clearInterval(timer);window.removeEventListener('focus',refresh);window.removeEventListener('online',refresh);window.removeEventListener('offline',offline);window.removeEventListener('solar-wholesale-pricing',refresh);window.removeEventListener('solar-notification',refresh);};
 },[enabled,userId,reload]);
 const data=enabled&&snapshot?.userId===userId?snapshot.data:null;
 return {data,error,loading,ready:!enabled||!!data&&!error&&!loading,reload};
}
