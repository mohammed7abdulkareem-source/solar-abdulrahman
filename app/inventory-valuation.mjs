import {refreshMaterialBrands} from './current-brand.mjs';
// Quote unsaved materials at today's rate. Previously saved lines retain their
// original quote, including during a price-only invoice edit.
export function currentSaleItems(items,products,originalItems=[]){
 const catalog=new Map(products.map(p=>[String(p.id),p]));
 const original=new Map(originalItems.map(p=>[String(p.id),p]));
 return refreshMaterialBrands(items,products).map(item=>{
  const source=original.get(String(item.id))||catalog.get(String(item.id));
  return source?{...item,cost:Number(source.cost||0),costBasis:source.costBasis||source.cost_basis||{}}:item;
 });
}

// An uncertain network save must replay its original valuation revision. The
// server returns the committed receipt or rejects the stale, uncommitted quote.
export function invoiceAttemptSignature(payload){
 const {valuationRevision,...businessInput}=payload;
 return JSON.stringify(businessInput);
}
