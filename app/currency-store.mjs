import {supabase} from './supabase';
import {invoicePayload} from './currency-utils.mjs';

export async function loadExchangeRate(){
  const {data,error}=await supabase.rpc('solar_exchange_rate_get');
  if(error)throw error;
  return data;
}
export async function saveExchangeRate(rate,revision){
  const {data,error}=await supabase.rpc('solar_exchange_rate_set',{rate:Number(rate),expected_revision:revision});
  if(error)throw error;
  return data;
}
// A retained attempt is used after network failures. Replaying an identical
// request returns the prior receipt without changing stock or cash again.
export async function saveCurrencyInvoice(attempt,kind,meta,items,original){
  const payload=invoicePayload(kind,meta,items,original);
  const signature=JSON.stringify(payload);
  if(attempt.current&&attempt.current.signature!==signature)throw new Error('تعذر تأكيد محاولة الحفظ السابقة. أعد المحاولة بنفس البيانات أولاً.');
  if(!attempt.current)attempt.current={requestId:crypto.randomUUID(),signature};
  const {data,error}=await supabase.rpc('solar_invoice_save',{request_id:attempt.current.requestId,payload});
  if(error){if(error.code)attempt.current=null;throw error;}
  attempt.current=null;
  return data;
}
export async function deleteCurrencyPurchase(invoice){
  const {error}=await supabase.rpc('solar_purchase_delete',{invoice_id:invoice.id,expected_revision:invoice.pricingRevision||0});
  if(error)throw error;
}
