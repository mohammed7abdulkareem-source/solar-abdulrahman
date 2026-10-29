// Integer decimal arithmetic follows PostgreSQL's round(material_cost, 2),
// followed by ceil(total_cost * (100 + percent)) / 100 for the minimum price.
function decimal(value){
 const match=String(value??0).trim().match(/^\+?(\d+)(?:\.(\d*))?(?:e([+-]?\d+))?$/i);
 if(!match)return null;
 const exponent=Number(match[3]||0),fraction=match[2]||'';let scale=fraction.length-exponent;
 if(Math.abs(scale)>24)return null;
 let units=BigInt(match[1]+fraction);if(scale<0){units*=10n**BigInt(-scale);scale=0;}
 return {units,scale};
}
function add(a,b){const scale=Math.max(a.scale,b.scale);return {units:a.units*10n**BigInt(scale-a.scale)+b.units*10n**BigInt(scale-b.scale),scale};}
export function systemMinimumQuote(items,percent,expenses=0,installationExpenses=0){
 if(![15,25].includes(Number(percent)))return null;
 let sum={units:0n,scale:0};
 for(const item of items){const qty=decimal(item.qty||0),cost=decimal(item.cost||0);if(!qty||!cost)return null;sum=add(sum,{units:qty.units*cost.units,scale:qty.scale+cost.scale});}
 const denominator=10n**BigInt(sum.scale),materialCents=(sum.units*100n*2n+denominator)/(2n*denominator);
 let base={units:materialCents,scale:2};
 for(const value of[expenses,installationExpenses]){const part=decimal(value||0);if(!part)return null;base=add(base,part);}
 const divisor=10n**BigInt(base.scale),minimumCents=(base.units*BigInt(100+Number(percent))+divisor-1n)/divisor;
 return {percent:Number(percent),materialCost:Number(materialCents)/100,totalCost:Number(base.units)/Number(divisor),minimum:Number(minimumCents)/100};
}
export function belowSystemMinimum(value,minimum){
 const amount=decimal(value),limit=decimal(minimum);if(!amount||!limit)return true;
 return amount.units*10n**BigInt(limit.scale)<limit.units*10n**BigInt(amount.scale);
}
export function systemEditPricingPercent(status,original,items,total){
 if(status?.systemFreePricing!==false)return null;
 const lines=rows=>JSON.stringify(rows.map(i=>[String(i.id??i.productId),Number(i.qty||0),Number(i.cost||0)]).sort((a,b)=>a[0].localeCompare(b[0])));
 const changed=Number(total)!==Number(original.total)||lines(items)!==lines(original.items||[]);
 return changed?Number(status.systemMarkupPercent):original.systemMarkupPercent==null?null:Number(original.systemMarkupPercent);
}
