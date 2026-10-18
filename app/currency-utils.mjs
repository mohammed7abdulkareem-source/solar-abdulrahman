export const roundMoney = value => Math.round((Number(value) + Number.EPSILON) * 100) / 100;
export const roundCost = value => Math.round((Number(value) + Number.EPSILON) * 1000000) / 1000000;
export const canEditExchangeRate = profile => !!profile?.active && !['installer','warehouse'].includes(profile.user_type) && (!!profile.is_admin || profile.permissions?.exchangeRateEdit === true);
export function exchangeRateError(currency, rate) {
  if (!['IQD','USD'].includes(currency)) return 'اختر عملة الشراء';
  if (currency === 'USD' && (!Number.isFinite(Number(rate)) || Number(rate) <= 0 || Number(rate) > 1000000)) return 'أدخل سعر صرف صحيحاً: عدد الدنانير مقابل دولار واحد';
  return '';
}
export function purchaseAmounts(items, currency = 'IQD', exchangeRate = 1, expenses = 0) {
  const error = exchangeRateError(currency, exchangeRate);
  if (error) throw new Error(error);
  const rate = currency === 'USD' ? Number(exchangeRate) : 1;
  if (!Number.isFinite(Number(expenses)) || Number(expenses) < 0) throw new Error('أدخل مصاريف صحيحة بالدينار');
  const sourceSubtotal = items.reduce((sum, item) => sum + Number(item.qty || 0) * Number(item.price || 0), 0);
  const subtotal = roundMoney(sourceSubtotal * rate);
  const lines = items.map(item => ({...item,sourcePrice:Number(item.price || 0),sourceCurrency:currency,exchangeRate:rate,price:roundCost(Number(item.price || 0)*rate),landedCost:roundCost(Number(item.price || 0)*rate + (sourceSubtotal > 0 ? Number(expenses)*Number(item.price || 0)/sourceSubtotal : 0))}));
  return {items:lines,sourceSubtotal:roundCost(sourceSubtotal),subtotal,expenses:Number(expenses),total:roundMoney(subtotal+Number(expenses)),exchangeRate:rate,sourceCurrency:currency};
}
export function weightedCost(existingQty, existingCost, incomingQty, incomingCost) {
  const values = [existingQty,existingCost,incomingQty,incomingCost].map(Number);
  if (values.some(v=>!Number.isFinite(v)||v<0) || values[2] <= 0) throw new Error('كميات أو كلف غير صحيحة');
  return roundCost((values[0]*values[1]+values[2]*values[3])/(values[0]+values[2]));
}
export function invoicePayload(kind, meta, items, original = null) {
  return {kind,...(kind!=='purchase'&&meta.warranty?{warranty:meta.warranty,...(original?{expectedWarrantyRevision:original.warrantyRevision??original.warranty_revision??0}:{})}:{}),...(kind==='purchase'&&meta.marketRate!=null?{marketRate:Number(meta.marketRate),accountRevision:Number(meta.accountRevision||0),cashCurrency:meta.cashCurrency||'IQD'}:{}),party:meta.party || '',partyId:meta.partyId ?? null,mode:meta.mode || 'cash',notes:meta.notes || '',expenses:Number(meta.expenses || 0),sourceCurrency:kind==='purchase'?(meta.sourceCurrency || meta.currency || 'IQD'):'IQD',exchangeRate:kind==='purchase'?Number(meta.exchangeRate || 1):1,total:kind==='system'?Number(meta.total):undefined,installerId:meta.installerId || null,installDate:meta.installDate || null,installTime:meta.installTime || null,customerAddress:meta.customerAddress || '',customerPhone:meta.customerPhone || '',invoiceId:original?.id ?? null,expectedRevision:original?.pricingRevision ?? 0,items:items.map(item=>({id:item.id,qty:Number(item.qty),price:kind==='system'?0:Number(item.price)}))};
}
