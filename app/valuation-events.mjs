export const VALUATION_EVENT='solar-exchange-rate-updated';
let revision=null;
export function publishValuation(settings){
 if(typeof window==='undefined'||settings?.revision==null||Number(settings.revision)===revision)return;
 revision=Number(settings.revision);
 window.dispatchEvent(new CustomEvent(VALUATION_EVENT,{detail:settings}));
}
export function refreshValuation(){
 if(typeof window!=='undefined')window.dispatchEvent(new CustomEvent(VALUATION_EVENT));
}


export function watchStockPriceChanges(refresh){
 const refreshVisible=()=>{if(document.visibilityState==='visible')refresh();};
 const events=[VALUATION_EVENT,'solar-wholesale-pricing','solar-warehouse-changed','solar-notification','focus','online'];
 for(const event of events)window.addEventListener(event,refreshVisible);
 document.addEventListener('visibilitychange',refreshVisible);
 const timer=setInterval(refreshVisible,60000);
 return ()=>{
  clearInterval(timer);
  for(const event of events)window.removeEventListener(event,refreshVisible);
  document.removeEventListener('visibilitychange',refreshVisible);
 };
}
