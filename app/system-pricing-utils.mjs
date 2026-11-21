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
function materialPriceCents(items,unitKey){
 let sum={units:0n,scale:0};
 for(const item of items){const qty=decimal(item.qty||0),cost=item[unitKey]==null?null:decimal(item[unitKey]);if(!qty||!cost)return null;sum=add(sum,{units:qty.units*cost.units,scale:qty.scale+cost.scale});}
 const denominator=10n**BigInt(sum.scale);
 return (sum.units*100n*2n+denominator)/(2n*denominator);
}
export function systemMaterialTotal(items){
 const cents=materialPriceCents(items,'materialPrice');
 return cents===null?null:Number(cents)/100;
}
export function systemMinimumQuote(items,percent,expenses=0,installationExpenses=0,unitKey='cost'){
 if(![15,25].includes(Number(percent)))return null;
 const materialCents=materialPriceCents(items,unitKey);
 if(materialCents===null)return null;
 let base={units:materialCents,scale:2};
 for(const value of[expenses,installationExpenses]){const part=decimal(value||0);if(!part)return null;base=add(base,part);}
 const divisor=10n**BigInt(base.scale),minimumCents=(base.units*BigInt(100+Number(percent))+divisor-1n)/divisor;
 return {percent:Number(percent),materialCost:Number(materialCents)/100,totalCost:Number(base.units)/Number(divisor),minimum:Number(minimumCents)/100};
}
export function belowSystemMinimum(value,minimum){
 const amount=decimal(value),limit=decimal(minimum);if(!amount||!limit)return true;
 return amount.units*10n**BigInt(limit.scale)<limit.units*10n**BigInt(amount.scale);
}
export function systemEconomicsChanged(original,items,total){
 const signature=rows=>JSON.stringify(rows.map(i=>[String(i.id??i.productId),Number(i.qty||0)]).sort((a,b)=>a[0].localeCompare(b[0])));
 return Number(total)!==Number(original.total)||signature(items)!==signature(original.items||[]);
}
export function systemEditPricingPercent(status,original,items,total){
 if(status?.systemFreePricing!==false)return null;
 return systemEconomicsChanged(original,items,total)?Number(status.systemMarkupPercent):original.systemMarkupPercent==null?null:Number(original.systemMarkupPercent);
}
export function systemMaterialPriceMap(result,ids){
 const prices=new Map(),tokens={};
 const unusable=()=>Error('تعذّر تأكيد سعر إحدى المواد. حدّث الأسعار.');
 if(!Array.isArray(result?.items)||result.items.length!==ids.length)throw unusable();
 for(const row of result.items){
  const id=String(row?.productId),price=row?.materialPrice;
  if(prices.has(id)||!['configured','cost','historical'].includes(row?.priceSource)||typeof row.priceHidden!=='boolean'||
   (row.priceHidden?price!==null:price==null||price===''||!Number.isFinite(Number(price))||Number(price)<0))throw unusable();
  prices.set(id,row.priceHidden?null:Number(price));
  if(typeof row.priceToken==='string'&&row.priceToken)tokens[id]=row.priceToken;
 }
 if(!ids.every(id=>prices.has(String(id))))throw unusable();
 return {prices,tokens:ids.length&&Object.keys(tokens).length===ids.length?tokens:undefined};
}

// The saved quantities are already reserved. A warehouse feed can omit a
// zero-stock product; its existing receipt line is still valid for editing.
export function systemEditStock(products,originalItems){
 const rows=new Map(products.map(p=>[String(p.id),{...p,qty:Number(p.qty)}]));
 for(const item of originalItems||[]){
  const id=String(item.id),row=rows.get(id)||{id:item.id,name:item.name,brand:item.brand,qty:0};
  row.qty+=Number(item.qty);
  rows.set(id,row);
 }
 return [...rows.values()];
}
