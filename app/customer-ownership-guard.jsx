'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';

export default function CustomerOwnershipGuard({customerId,userId,onBack,backLabel,onLost,children}){
 const [status,setStatus]=useState('checking');
 const [verified,setVerified]=useState(false);
 const generation=useRef(0),lost=useRef(false),onLoss=useRef(onLost);
 onLoss.current=onLost;
 const check=useCallback(async()=>{
  const turn=++generation.current;
  setStatus('checking');
  try{
   const {data,error}=await supabase.from('customers').select('id,owner_id').eq('id',customerId).maybeSingle();
   if(turn!==generation.current)return;
   if(error&&error.code!=='42501')throw error;
   if(!error&&data?.owner_id===userId&&String(data.id)===String(customerId)){
    lost.current=false;setVerified(true);setStatus('ready');return;
   }
   setVerified(false);setStatus('denied');
   if(!lost.current){lost.current=true;void Promise.resolve(onLoss.current?.()).catch(()=>{});}
  }catch{if(turn===generation.current)setStatus('error');}
 },[customerId,userId]);
 useEffect(()=>{
  const recheck=()=>{if(document.visibilityState!=='hidden')void check();};
  const visibility=()=>{
   if(document.visibilityState==='hidden'){generation.current++;setStatus('checking');}
   else recheck();
  };
  const resume=event=>{if(event.persisted)recheck();};
  recheck();
  window.addEventListener('focus',recheck);window.addEventListener('pageshow',resume);document.addEventListener('visibilitychange',visibility);
  return()=>{generation.current++;window.removeEventListener('focus',recheck);window.removeEventListener('pageshow',resume);document.removeEventListener('visibilitychange',visibility);};
 },[check]);
 return <>
  {verified&&<div hidden={status!=='ready'}>{children}</div>}
  {status!=='ready'&&<section className="miniParty">
   {status==='checking'?<p role="status">جارٍ التحقق من صلاحية كشف الحساب…</p>:<p role="alert">{status==='denied'?'لم يعد هذا الحساب متاحاً لك.':'تعذّر التحقق من صلاحية كشف الحساب.'}</p>}
   {status==='error'&&<button type="button" className="uiButton" onClick={check}>إعادة المحاولة</button>}
   <button type="button" className="uiButton" onClick={onBack}>{backLabel||'رجوع إلى العملاء'}</button>
  </section>}
 </>;
}
