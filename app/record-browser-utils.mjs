import {normalizeSearch} from './party-search-utils.mjs';

const codes=new Intl.Collator('en',{numeric:true,sensitivity:'base'});
export function materialsByCode(rows){
 return [...rows].sort((a,b)=>codes.compare(normalizeSearch(a.code),normalizeSearch(b.code))||Number(a.id)-Number(b.id));
}
export function baghdadDay(value=new Date()){
 return new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(value));
}
export function canReadPaymentKind(profile,kind){
 if(!profile?.active||['installer','warehouse'].includes(profile.user_type))return false;
 if(profile.is_admin)return true;
 const p=profile.permissions||{};
 return (kind==='supplier_payment'?['supplierPayment','supplierStatement']:kind==='system_payment'?['systemPayment','customerStatement','customers','customerCreate']:kind==='customer_payment'?['customerPayment','customerStatement','customers','customerCreate']:[]).some(key=>p[key]===true);
}
export const paymentKinds=[['customer_payment','تسديد جملة'],['system_payment','تسديد منظومات'],['supplier_payment','تسديد مورد']];
export function recordPage(index,count,size=30){
 const position=Math.max(0,Math.min(Number(index)||0,Math.max(0,count-1)));
 return {position,offset:Math.floor(position/size)*size,index:position%size};
}
