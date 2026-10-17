import {installationCost} from './review-utils.mjs';
import {dateKey} from './supplier-utils.mjs';
export function buildSalesSeries(rows,from='',to=''){
 const end=to||dateKey(new Date()),start=from||new Date(new Date(end+'T12:00:00Z').getTime()-13*86400000).toISOString().slice(0,10),startMs=Date.parse(start+'T12:00:00Z'),days=Math.max(1,Math.floor((Date.parse(end+'T12:00:00Z')-startMs)/86400000)+1),count=Math.min(18,days);
 const buckets=Array.from({length:count},(_,i)=>({date:new Date(startMs+Math.floor(i*days/count)*86400000).toISOString().slice(0,10),sales:0,cost:0}));
 for(const t of rows){if(!['sale','system'].includes(t.kind))continue;const date=dateKey(t.date);if(date<start||date>end)continue;const index=Math.min(count-1,Math.floor(((Date.parse(date+'T12:00:00Z')-startMs)/86400000)*count/days)),sales=Number(t.sales??(t.kind==='system'?t.total:t.subtotal??t.total)??0),cost=t.sales!=null?Number(t.cost||0):t.kind==='system'?installationCost(t):Number(t.cost||0)||(t.items||[]).reduce((s,i)=>s+Number(i.qty||0)*Number(i.cost||0),0);buckets[index].sales+=sales;buckets[index].cost+=cost;}
 return buckets;
}
