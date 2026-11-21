import {refreshMaterialBrands} from './current-brand.mjs';
// Quote unsaved materials at today's rate. Previously saved lines retain their
// original quote, including during a price-only invoice edit.
export function usesPersonalSalePrices(profile){
 return profile?.active===true&&!profile.is_admin&&!['warehouse','installer'].includes(profile.user_type)&&profile.permissions?.profitUsesWholesalePrice===true;
}
export const hasHiddenSaleCost=items=>items.some(item=>item.personalPriceBasis&&item.cost==null);

export function currentSaleItems(items,products,originalItems=[],personalPrices=false,editing=false){
 const catalog=new Map(products.map(p=>[String(p.id),p]));
 const original=new Map(originalItems.map(p=>[String(p.id),p]));
 return refreshMaterialBrands(items,products).map(item=>{
  const saved=original.get(String(item.id));
  const source=saved||catalog.get(String(item.id));
  // A re-added product can retain an earlier receipt snapshot. Only the
  // server can price that edit without exposing the underlying inventory cost.
  if(editing&&!saved&&(personalPrices||originalItems.some(row=>row.personalPriceBasis))){
   const {cost_basis,bookCost,...safe}=item;
   return {...safe,cost:null,personalPriceBasis:true,costBasis:{}};
  }
  if(personalPrices||source?.personalPriceBasis||catalog.get(String(item.id))?.personalPriceBasis||item.personalPriceBasis){
   const {cost_basis,bookCost,...safe}=item;
   return {...safe,personalPriceBasis:true,cost:source?.personalPriceBasis&&source.cost!=null?Number(source.cost):null,costBasis:{}};
  }
  return source?{...item,cost:Number(source.cost||0),costBasis:source.costBasis||source.cost_basis||{}}:item;
 });
}

// An uncertain network save must replay its original valuation revision. The
// server returns the committed receipt or rejects the stale, uncommitted quote.
export function invoiceAttemptSignature(payload){
 const {valuationRevision,wholesalePricingRevision,purchaseCorrectionToken,...businessInput}=payload;
 return JSON.stringify(businessInput);
}
