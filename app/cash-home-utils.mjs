import {isAdministrator,canOpenPage} from './access-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';

const failure=()=>new Error('تعذر تأكيد بيانات الصندوق. أعد التحديث.');
const amount=value=>{
 if(!['number','string'].includes(typeof value)||String(value).trim()==='')throw failure();
 const n=Number(value);if(!Number.isFinite(n))throw failure();return n;
};
export function cashAvailableTotals(data){
 return {IQD:amount(data?.summary?.availableIQD),USD:amount(data?.summary?.availableUSD)};
}
export function cashPendingSnapshot(data,profile,ownerId=''){
 if(!profile?.id||profile.active!==true||!canOpenPage(profile,'cash')||!Array.isArray(data?.pendingTransfers))throw failure();
 const total=amount(data.summary?.pendingIQD),count=data.summary?.pendingCount;
 if(total<0||!Number.isInteger(count)||count!==data.pendingTransfers.length)throw failure();
 const admin=isAdministrator(profile),scope=admin?(ownerId||null):profile.id,seen=new Set();
 const rows=data.pendingTransfers.map(row=>{
  if(!row||typeof row.id!=='string'||!row.id||seen.has(row.id)||typeof row.sender_id!=='string'||typeof row.recipient_id!=='string'||!row.sender_id||!row.recipient_id||row.status!=='pending'||row.currency!=='IQD'||typeof row.senderName!=='string'||!row.senderName.trim()||typeof row.recipientName!=='string'||!row.recipientName.trim()||typeof row.created_at!=='string'||!Number.isFinite(Date.parse(row.created_at)))throw failure();
  if(scope&&row.sender_id!==scope&&row.recipient_id!==scope)throw failure();
  const value=amount(row.amount);if(value<=0)throw failure();seen.add(row.id);
  return {id:row.id,sender_id:row.sender_id,recipient_id:row.recipient_id,senderName:row.senderName,recipientName:row.recipientName,amount:value,currency:'IQD',created_at:row.created_at,status:'pending'};
 });
 // Compensated addition checks the complete server summary without changing
 // any stored amount, imposing currency rounding, or mixing it into cash.
 let sum=0,correction=0;for(const row of rows){const n=row.amount-correction,next=sum+n;correction=(next-sum)-n;sum=next;}
 if(Math.abs(sum-total)>Math.max(1,Math.abs(sum),Math.abs(total))*Number.EPSILON*8)throw failure();
 return {rows,total,count};
}
export function filterCashOwners(owners,query=''){
 const words=normalizeSearch(query).split(/\s+/).filter(Boolean);
 return owners.filter(owner=>words.every(word=>normalizeSearch(owner.name).includes(word)));
}

export const cashOwnerCanPost=owner=>!!owner?.id&&owner.active!==false&&!['warehouse','installer'].includes(owner.userType||owner.user_type);
export function cashOwnerDescription(owner,profile){
 const role=owner?.userType||profile?.user_type;
 return [owner?.active===false?'حساب موقوف':'',({warehouse:'مسؤول مخزن',installer:'مهندس تنصيب',admin_staff:'إداري',accountant:'محاسب',finance:'مسؤول المالية'}[role])||profile?.honorific||(profile?.is_admin?'الإدارة':'')].filter(Boolean).join(' · ');
}
