import {supabase} from './supabase';
export async function deleteSale(id){
 const preview=await supabase.rpc('solar_sale_delete_preview',{invoice_id:id});
 if(preview.error)throw new Error('تعذر مراجعة الفاتورة أو لا تملك صلاحية حذفها.');
 const p=preview.data;
 if(p.blockedReason)throw new Error(p.blockedReason);
 if(!confirm('حذف فاتورة '+(p.kind==='system'?'منظومة':'بيع جملة')+' #'+p.receiptNo+' للزبون '+(p.party||'نقدي')+' بمبلغ '+Number(p.total).toLocaleString('en-US')+' د.ع؟\nترجع المواد إلى المخزون ويُلغى أثر الفاتورة على الحساب والقاصة. التسديدات السابقة تبقى بحساب الزبون.'))return false;
 const result=await supabase.rpc('solar_sale_delete',{invoice_id:id,expected_token:p.token});
 if(result.error)throw new Error(result.error.code==='40001'?'تغيّرت الفاتورة أثناء المراجعة. حدّث القائمة وحاول مجدداً.':result.error.code==='P0002'?'رصيد قاصة صاحب الفاتورة لا يكفي لإلغاء المبلغ النقدي. سوِّ القاصة أولاً.':result.error.message?.startsWith('لا يمكن')?result.error.message:'لم تُحذف الفاتورة. تحقق من الصلاحية وحدّث القائمة.');
 return true;
}
