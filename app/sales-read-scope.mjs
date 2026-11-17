import {isAdministrator} from './access-utils.mjs';

export const salesReadAllowed=profile=>!!profile?.id&&profile.active===true&&!['warehouse','installer'].includes(profile.user_type);

// A role change must discard snapshots, report HTML and editors loaded under
// the previous authorization, even when the signed-in account stays the same.
export function salesAuthorizationKey(profile){
 const permissions=Object.entries(profile?.permissions||{}).sort(([left],[right])=>left.localeCompare(right));
 return JSON.stringify([profile?.id||'',profile?.active===true,profile?.user_type||'',profile?.is_admin===true,permissions]);
}

export function salesReadOwner(profile,selectedOwner=null){
 return isAdministrator(profile)?selectedOwner||null:profile?.id||null;
}

const scopeFailure=()=>Object.assign(new Error('تعذر تأكيد أن المبيعات تخص الحساب المحدد. أعد التحديث.'),{code:'SALES_SCOPE_MISMATCH'});

export function verifySalesResponse(data,profile,selectedOwner=null,{period=false}={}){
 const ownerId=salesReadOwner(profile,selectedOwner);
 if(!salesReadAllowed(profile)||!data||!Array.isArray(data.rows)||data.ownerId!==ownerId)throw scopeFailure();
 if(!isAdministrator(profile)&&Array.isArray(data.users)&&data.users.some(user=>user?.id!==profile.id))throw scopeFailure();
 if(period){
  if(data.scope!==(ownerId===null?'company':'own')||!data.summary||typeof data.summary!=='object')throw scopeFailure();
 }else{
  // Reject the whole page, including totals and document actions, instead of
  // trimming foreign records but retaining a different owner's total count.
  if(!Number.isFinite(data.count)||data.count<0||ownerId!==null&&data.rows.some(row=>row?.created_by!==ownerId))throw scopeFailure();
 }
 return data;
}
