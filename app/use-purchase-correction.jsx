'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import {purchaseCorrectionReady,purchaseCorrectionSignature} from './purchase-correction.mjs';

export function usePurchaseCorrection({enabled,scope,invoiceId,originalProductIds=[]}){
 const [snapshot,setSnapshot]=useState(null),[loading,setLoading]=useState(false),[error,setError]=useState('');
 const sequence=useRef(0),controller=useRef(null),liveScope=useRef('');
 const key=enabled&&scope&&invoiceId!=null?scope+'|'+invoiceId:'';
 const originalIdsKey=JSON.stringify(originalProductIds.map(String).sort());
 liveScope.current=key;
 useEffect(()=>{++sequence.current;controller.current?.abort();setSnapshot(null);setLoading(false);setError('');return()=>{++sequence.current;controller.current?.abort();};},[key]);
 const load=useCallback(async payload=>{
  if(!key||liveScope.current!==key)return null;
  const request=++sequence.current,abort=new AbortController();controller.current?.abort();controller.current=abort;
  setLoading(true);setError('');
  const timer=setTimeout(()=>abort.abort(),15000);
  try{
   const {data,error:failure}=await supabase.rpc('solar_purchase_correction_preview',{payload}).abortSignal(abort.signal);
   if(failure)throw failure;
   if(!purchaseCorrectionReady(data,payload,JSON.parse(originalIdsKey)))throw new Error('لم تكتمل بيانات معاينة تعديل الشراء. أعد المحاولة.');
   if(request!==sequence.current||liveScope.current!==key)return null;
   const result={scope,signature:purchaseCorrectionSignature(payload),data};setSnapshot({key,...result});return result;
  }catch(failure){
   if(request===sequence.current&&liveScope.current===key)setError(abort.signal.aborted?'تعذر تحميل معاينة التعديل الآن. أعد المحاولة.':failure.message||'تعذر تحميل معاينة تعديل الشراء.');
   return null;
  }finally{clearTimeout(timer);if(request===sequence.current&&liveScope.current===key)setLoading(false);}
 },[key,scope,originalIdsKey]);
 const current=snapshot?.key===key?snapshot:null;
 return {data:current?.data||null,loading,error,ready:!!current&&!loading&&!error,load};
}
