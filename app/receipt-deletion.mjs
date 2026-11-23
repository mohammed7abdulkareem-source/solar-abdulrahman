import {canRequestReceiptDeletion,canAccessSupplier} from './access-utils.mjs';
import {supabase} from './supabase';
import {saveRequest} from './save-request.mjs';
import {runDeletionAttempt} from './receipt-deletion-attempt.mjs';
export const deletionKind=kind=>({sale:'بيع جملة',system:'بيع منظومة',purchase:'شراء',customer_payment:'تسديد عميل',system_payment:'تسديد منظومة',supplier_payment:'تسديد مورد',cash_income:'إيداع / أرباح خارجية',cash_expense:'مصروف / سحب نقدي',profit_distribution:'توزيع أرباح'}[kind]||'وصل');
async function currentUser(){const {data,error}=await supabase.auth.getSession();if(error)throw error;const uid=data.session?.user?.id;if(!uid)throw new Error('سجّل الدخول لتأكيد الحذف.');return uid;}
export const deletionResultMessage=result=>result?.direct||result?.status==='deleted'?'تم حذف الوصل وتصحيح أثره على المخزون والحساب والقاصة، مع حفظ سجل التدقيق.':'تم إرسال طلب الحذف للإدارة؛ الوصل يبقى محفوظًا لحين الموافقة.';
export async function requestReceiptDeletion(invoiceId,requestId=crypto.randomUUID(),profile){
 const userId=await currentUser();
 const canResume=row=>row.kind==='supplier_payment'?canRequestReceiptDeletion(profile,row.kind,row):row.kind!=='purchase'||canAccessSupplier(profile,row);
 return runDeletionAttempt(userId,{currentUser,invoiceId,canResume,prepare:async()=>{
  const context=await supabase.rpc('solar_receipt_delete_requests',{action:'context',payload:{invoiceId}});
  if(context.error)throw context.error;const c=context.data;
  if(!canResume(c))throw new Error('لا تملك صلاحية حذف هذا الوصل.');
  const canRequest=canRequestReceiptDeletion(profile,c.kind,c);
  if(c.blockedReason)throw new Error(c.blockedReason);
  const direct=c.deletionMode==='direct'&&c.directEligible===true;
  if(c.kind==='purchase'&&!direct)throw new Error(c.directBlockedReason||'لا يمكن حذف الشراء بحالته الحالية. حدّث الوصل وراجع المخزون.');
  if(!direct&&(!canRequest||c.canRequest===false))throw new Error(c.directBlockedReason||'تحتاج إلى صلاحية طلبات حذف الوصولات لإرسال هذا الوصل للإدارة.');
  const cash=['cash_income','cash_expense','profit_distribution'].includes(c.kind),label='وصل '+deletionKind(c.kind)+' #'+c.receiptNo;
  const prompt=direct?'حذف '+label+' وتصحيح أثره على المخزون والحساب والقاصة؟\nيُحفظ الوصل في سجل التدقيق.':(c.directBlockedReason?c.directBlockedReason+'\n':'')+'إرسال طلب حذف '+label+(cash?' من قاصة '+c.ownerName:' للزبون / المورد '+(c.party||'نقدي'))+' إلى الإدارة؟\nيبقى الوصل والحساب والقاصة كما هي لحين الموافقة.';
  if(!confirm(prompt))return null;
  return {id:requestId,invoiceId:Number(invoiceId),receiptNo:c.receiptNo,kind:c.kind,adminOnly:c.adminOnly===true||c.admin_only===true,action:direct?'delete_direct':'request',token:c.token};
 },send:row=>{
  if(row.action==='request'&&!canRequestReceiptDeletion(profile,row.kind,row))throw new Error('تحتاج إلى صلاحية طلبات حذف الوصولات لتأكيد الطلب السابق.');
  return saveRequest(signal=>supabase.rpc('solar_receipt_delete_requests',{action:row.action,request_id:row.id,payload:{invoiceId:row.invoiceId,expectedToken:row.token}}).abortSignal(signal));
 }});
}
