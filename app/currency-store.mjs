import {supabase} from './supabase';
import {saveRequest} from './save-request.mjs';
import {invoicePayload} from './currency-utils.mjs';
import {saveInvoiceAttempt,resolveInvoiceAttempt} from './invoice-attempt.mjs';
import {publishValuation,refreshValuation} from './valuation-events.mjs';

export async function loadExchangeRate(){
  const {data,error}=await supabase.rpc('solar_exchange_rate_get');
  if(error)throw error;
  return data;
}
export async function saveExchangeRate(rate,revision){
  const {data,error}=await supabase.rpc('solar_exchange_rate_set',{rate:Number(rate),expected_revision:revision});
  if(error)throw error;
  publishValuation(data);
  return data;
}
async function invoiceUser(){
 const {data,error}=await supabase.auth.getSession();if(error)throw error;
 const uid=data.session?.user?.id;if(!uid)throw new Error('سجّل الدخول لتأكيد حفظ الفاتورة.');return uid;
}
const resolveAttempt=record=>saveRequest(signal=>supabase.rpc('solar_invoice_attempt_resolve',{request_id:record.requestId,payload:record.payload}).abortSignal(signal));
export async function recoverCurrencyInvoice(attempt){
 const uid=await invoiceUser();return resolveInvoiceAttempt(attempt,uid,{resolve:resolveAttempt,currentUser:invoiceUser});
}
export async function saveCurrencyInvoice(attempt,kind,meta,items,original){
 const uid=await invoiceUser();
 try{return await saveInvoiceAttempt(attempt,uid,invoicePayload(kind,meta,items,original),{
  currentUser:invoiceUser,resolve:resolveAttempt,
  send:record=>saveRequest(signal=>supabase.rpc('solar_invoice_save',{request_id:record.requestId,payload:record.payload}).abortSignal(signal))
 });}catch(error){if(error.code==='PT409')refreshValuation();if(!error.invoiceRecovery&&!/^[0-9A-Z]{5}$/.test(error.code||'')&&!/[\u0600-\u06ff]/.test(error.message||''))throw new Error('لم يصل تأكيد الحفظ. استخدم «التحقق من الحفظ السابق» قبل إعادة المحاولة.',{cause:error});throw error;}
}
export async function deleteCurrencyPurchase(invoice){
  const {error}=await supabase.rpc('solar_purchase_delete',{invoice_id:invoice.id,expected_revision:invoice.pricingRevision||0});
  if(error)throw error;
}
