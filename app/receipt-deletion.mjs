import {supabase} from './supabase';
import {saveRequest} from './save-request.mjs';
export const deletionKind=kind=>({sale:'بيع جملة',system:'بيع منظومة',purchase:'شراء',customer_payment:'تسديد عميل',system_payment:'تسديد منظومة',supplier_payment:'تسديد مورد',cash_income:'إيداع / أرباح خارجية',cash_expense:'مصروف / سحب نقدي',profit_distribution:'توزيع أرباح'}[kind]||'وصل');
export async function requestReceiptDeletion(invoiceId,requestId=crypto.randomUUID()){
 const context=await supabase.rpc('solar_receipt_delete_requests',{action:'context',payload:{invoiceId}});
 if(context.error)throw context.error;const c=context.data;
 if(c.blockedReason)throw new Error(c.blockedReason);
 const cash=['cash_income','cash_expense','profit_distribution'].includes(c.kind);
 if(!confirm('إرسال طلب حذف وصل '+deletionKind(c.kind)+' #'+c.receiptNo+(cash?' من قاصة '+c.ownerName:' للزبون / المورد '+(c.party||'نقدي'))+' إلى الإدارة؟\nيبقى الوصل والحساب والقاصة كما هي لحين الموافقة. '+(cash?'تُلغى آثار الحركة على القاصة والأرباح ورأس المال عند اعتماد الحذف.':'تُصحح المصاريف والمخزون والتسديدات عند اعتماد الحذف.')))return null;
 const response=await saveRequest(signal=>supabase.rpc('solar_receipt_delete_requests',{action:'request',request_id:requestId,payload:{invoiceId,expectedToken:c.token}}).abortSignal(signal));
 if(response.error)throw response.error;return response.data;
}
