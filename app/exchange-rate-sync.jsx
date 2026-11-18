'use client';
import {canOpenPage,isEngineer,isWarehouse} from './access-utils.mjs';
import {useEffect} from 'react';
import {loadExchangeRate} from './currency-store.mjs';
import {publishValuation} from './valuation-events.mjs';

export default function ExchangeRateSync({profile}){
 const permitted=!isEngineer(profile)&&!isWarehouse(profile)&&['exchangeRate','purchase','stock','cash','supplierPayment'].some(page=>canOpenPage(profile,page));
 useEffect(()=>{
  if(!permitted)return;
  let live=true,busy=false;
  const check=async()=>{if(!live||busy||document.hidden)return;busy=true;try{const settings=await loadExchangeRate();if(live)publishValuation(settings);}catch{/* Saving still validates the authoritative revision. */}finally{busy=false;}};
  check();const timer=setInterval(check,10000);
  window.addEventListener('focus',check);document.addEventListener('visibilitychange',check);
  return()=>{live=false;clearInterval(timer);window.removeEventListener('focus',check);document.removeEventListener('visibilitychange',check);};
 },[profile.id,permitted]);
 return null;
}
