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
