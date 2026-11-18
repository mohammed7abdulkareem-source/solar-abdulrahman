import {salesAuthorizationKey} from './sales-read-scope.mjs';
import {canSeeCash} from './access-utils.mjs';

const failure=()=>Object.assign(new Error('تعذر تأكيد أرصدة القاصات. أعد تحديث البيانات.'),{code:'CASH_BALANCE_SCOPE_MISMATCH'});
const amounts=value=>{
 if(!value||['IQD','USD','usdBook'].some(key=>typeof value[key]!=='number'||!Number.isFinite(value[key])))throw failure();
 return {IQD:value.IQD,USD:value.USD,usdBook:value.usdBook};
};

// Read balances from the protected cash ledger, never from the receipt list:
// a private receipt may still affect the caller's own cashbox.
export function cashBalanceSnapshot(data,profile){
 if(!canSeeCash(profile)||!data||data.ownerId!==(profile.is_admin===true?null:profile.id)||!Array.isArray(data.owners)||!Number.isFinite(Date.parse(data.asOf)))throw failure();
 const seen=new Set(),owners=data.owners.map(row=>{
  if(!row||(row.id!==null&&typeof row.id!=='string')||seen.has(row.id)||(!profile.is_admin&&row.id!==profile.id))throw failure();
  seen.add(row.id);return {id:row.id,...amounts(row)};
 });
 if(!seen.has(profile.id))throw failure();
 return {authorizationKey:salesAuthorizationKey(profile),asOf:data.asOf,ownerId:data.ownerId,summary:amounts(data.summary),owners};
}

export function currentCashBalances(snapshot,profile){
 if(!snapshot||!canSeeCash(profile)||snapshot.authorizationKey!==salesAuthorizationKey(profile))return null;
 const own=snapshot.owners.find(row=>row.id===profile.id);
 if(!own)return null;
 return {own:{IQD:own.IQD,USD:own.USD,usdBook:own.usdBook},total:{...snapshot.summary},asOf:snapshot.asOf};
}
