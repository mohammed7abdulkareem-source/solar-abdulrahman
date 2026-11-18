// Bind a read-only correction preview to the exact invoice draft. Its token is
// an optimistic concurrency guard, not part of the user's financial input.
export function purchaseCorrectionSignature(payload){
 const {purchaseCorrectionToken,...input}=payload||{};
 return JSON.stringify(input);
}
const number=value=>(typeof value==='number'||typeof value==='string'&&value.trim()!=='')&&Number.isFinite(Number(value));
const currency=value=>value==='IQD'||value==='USD';
const amounts=value=>value&&['total','sourceSubtotal','expenses','accountAmount','cashAmount'].every(key=>number(value[key]))&&currency(value.accountCurrency)&&currency(value.cashCurrency);
const stock=value=>value&&number(value.qty)&&number(value.cost);
export function purchaseCorrectionReady(data,payload,originalProductIds=[]){
 if(!data||!payload||String(data.invoiceId)!==String(payload.invoiceId)||Number(data.pricingRevision)!==Number(payload.expectedRevision)||typeof data.token!=='string'||!data.token)return false;
 if(['changed','requiresCorrection','canApply'].some(key=>typeof data[key]!=='boolean'))return false;
 if(!data.locks||['supplier','warehouse','paymentMode','sourceCurrency','exchangeRate','cashCurrency'].some(key=>typeof data.locks[key]!=='boolean'))return false;
 // A rejected plan may not have a reconstructible inventory value. Show its
 // real reason without inventing a zero-valued replacement preview.
 if(!data.canApply)return typeof data.blockedReason==='string'&&!!data.blockedReason.trim();
 if(!amounts(data.before)||!amounts(data.after)||!data.delta||!['total','accountAmount','cashAmount'].every(key=>number(data.delta[key])))return false;
 if(!Array.isArray(data.items)||data.items.some(row=>!row||row.id==null||!stock(row.before)||!stock(row.after)||!['quantityDelta','bookValueDelta','availableBefore','availableAfter'].every(key=>number(row[key]))))return false;
 const ids=data.items.map(row=>String(row.id));
 const allowed=new Set([...originalProductIds,...(payload.items||[]).map(row=>row.id)].map(String));
 if(data.materialScope!=='changed'||!Array.isArray(data.changedProductIds)||data.changedProductIds.some(id=>!number(id)||!Number.isInteger(Number(id))))return false;
 const changedIds=data.changedProductIds.map(String);
 if(new Set(ids).size!==ids.length||new Set(changedIds).size!==changedIds.length||ids.length!==changedIds.length||ids.some(id=>!allowed.has(id)||!changedIds.includes(id))||!data.changed&&ids.length)return false;
 if(!data.affectedSales||!Number.isInteger(data.affectedSales.count)||data.affectedSales.count<0||!['profitBefore','profitAfter','profitDelta'].every(key=>number(data.affectedSales[key])))return false;
 if(data.paymentsPreserved!==true||data.unrelatedMaterialsPreserved!==true)return false;
 return true;
}
export function purchaseCorrectionMatches(review,payload,scope,originalProductIds=[]){
 return !!review&&review.scope===scope&&review.signature===purchaseCorrectionSignature(payload)&&purchaseCorrectionReady(review.data,payload,originalProductIds);
}
export function purchaseCorrectionLines(original,payload){
 const previous=new Map((original?.items||[]).map(row=>[String(row.id),row]));
 const next=new Map((payload?.items||[]).map(row=>[String(row.id),row]));
 const ids=[...new Set([...previous.keys(),...next.keys()])];
 return ids.map(id=>{
  const before=previous.get(id),after=next.get(id),beforeQty=Number(before?.qty||0),afterQty=Number(after?.qty||0);
  const beforePrice=before?Number(before.sourcePrice??before.price):null,afterPrice=after?Number(after.price):null;
  return {id,name:before?.name||after?.name||'',beforeQty,afterQty,beforePrice,afterPrice,changed:beforeQty!==afterQty||beforePrice!==afterPrice};
 });
}
export function purchaseCorrectionError(error){
 if(error?.invoiceRecoveryHandled)return error.message||'راجع حالة الحفظ السابق قبل تأكيد تعديل آخر.';
 if(error?.code==='PT409')return (error.message||'تغيّر الوصل أو رصيد المادة.')+' أعد معاينة التعديل على أحدث البيانات.';
 return error?.message||'تعذر تأكيد التعديل. راجع الاتصال وأعد تأكيد الطلب نفسه.';
}
// Quantities and price differences can be fractional; never turn a small,
// non-zero correction into a displayed zero.
export function purchaseCorrectionNumber(value){
 if(!number(value))return '—';
 const numeric=Number(value);
 return new Intl.NumberFormat('en-US',{maximumFractionDigits:20}).format(Object.is(numeric,-0)?0:numeric);
}
export function purchaseCorrectionSigned(value){
 if(!number(value))return '—';
 const numeric=Number(value);
 return (numeric>0?'+ ':numeric<0?'− ':'')+purchaseCorrectionNumber(Math.abs(numeric));
}
export function purchaseEditRate(invoice,fallback){
 if(number(invoice?.marketRate)&&Number(invoice.marketRate)>0)return String(invoice.marketRate);
 if(invoice?.sourceCurrency==='USD'&&number(invoice.exchangeRate)&&Number(invoice.exchangeRate)>0)return String(invoice.exchangeRate);
 return number(fallback)&&Number(fallback)>0?String(fallback):'';
}
