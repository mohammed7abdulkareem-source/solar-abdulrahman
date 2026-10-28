import {supabase} from './supabase';
import {saveRequest} from './save-request.mjs';
export const deletionKind=kind=>({sale:'بيع جملة',system:'بيع منظومة',purchase:'شراء',customer_payment:'تسديد عميل',system_payment:'تسديد منظومة',supplier_payment:'تسديد مورد'}[kind]||'وصل');
export async function requestReceiptDeletion(invoiceId,requestId=crypto.randomUUID()){
 const context=await supabase.rpc('solar_receipt_delete_requests',{action:'context',payload:{invoiceId}});
 if(context.error)throw context.error;const c=context.data;
 if(c.blockedReason)throw new Error(c.blockedReason);
 if(!confirm('إرسال طلب حذف وصل '+deletionKind(c.kind)+' #'+c.receiptNo+' للزبون / المورد '+(c.party||'نقدي')+' إلى الإدارة؟\nيبقى الوصل والحساب والقاصة كما هي لحين الموافقة. تُصحح المصاريف والمخزون والتسديدات عند اعتماد الحذف.'))return null;
 const response=await saveRequest(signal=>supabase.rpc('solar_receipt_delete_requests',{action:'request',request_id:requestId,payload:{invoiceId,expectedToken:c.token}}).abortSignal(signal));
 if(response.error)throw response.error;return response.data;
}
