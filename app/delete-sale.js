import {supabase} from './supabase';
export async function deleteSale(id){
 const preview=await supabase.rpc('solar_sale_delete_preview',{invoice_id:id});
 if(preview.error)throw new Error('تعذر مراجعة الفاتورة أو لا تملك صلاحية حذفها.');
 const p=preview.data;
 if(p.blockedReason)throw new Error(p.blockedReason);
 const refunds=(p.expenseRefunds||[]).filter(r=>Number(r.amount)>0).map(r=>'إرجاع '+Number(r.amount).toLocaleString('en-US')+' د.ع إلى قاصة '+(r.name||'صاحب المصروف')).join('\n');
 if(!confirm('حذف فاتورة '+(p.kind==='system'?'منظومة':'بيع جملة')+' #'+p.receiptNo+' للزبون '+(p.party||'نقدي')+' بمبلغ '+Number(p.total).toLocaleString('en-US')+' د.ع؟\nترجع المواد إلى المخزون ويُلغى أثر الفاتورة على الحساب والقاصة.'+(refunds?'\nمصاريف التنصيب المدفوعة:\n'+refunds:'')+'\nالتسديدات السابقة تبقى بحساب الزبون'+(p.retainedPayments?'، ويصير تخصيص '+Number(p.retainedPayments)+' تسديد على الحساب العام.':'.')))return false;
 const result=await supabase.rpc('solar_sale_delete',{invoice_id:id,expected_token:p.token});
 if(result.error)throw new Error(['40001','PT409'].includes(result.error.code)?'تغيّرت الفاتورة أثناء المراجعة. حدّث القائمة وحاول مجدداً.':result.error.code==='P0002'?'رصيد قاصة صاحب الفاتورة لا يكفي لإلغاء المبلغ النقدي. سوِّ القاصة أولاً.':result.error.message?.startsWith('لا يمكن')?result.error.message:'لم تُحذف الفاتورة. تحقق من الصلاحية وحدّث القائمة.');
 return true;
}
