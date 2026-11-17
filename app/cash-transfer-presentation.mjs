import {canUseCash} from './cash-permissions.mjs';
export const CASH_TRANSFER_FRESH_MS=30000;
export function cashTransferBalance(snapshot,scope,state,now=Date.now()){
 if(state!=='ready'||snapshot?.scope!==scope||!Number.isFinite(snapshot?.readAt)||now<snapshot.readAt||now-snapshot.readAt>=CASH_TRANSFER_FRESH_MS)return null;
 const value=snapshot.data?.balance;
 if(typeof value!=='number'&&(typeof value!=='string'||!value.trim()))return null;
 return Number.isFinite(Number(value))?Number(value):null;
}
export function cashTransferScopedRows(rows,profile){
 if(!canUseCash(profile,'cashTransferSend')&&!canUseCash(profile,'financeReceive'))return [];
 return (Array.isArray(rows)?rows:[]).filter(row=>row&&typeof row.id==='string'&&(profile.is_admin||row.sender_id===profile.id||row.recipient_id===profile.id));
}
export function cashTransferActions(row,profile,canReceive){
 if(row?.status!=='pending')return [];
 const actions=[];
 if(row.recipient_id===profile.id&&canReceive===true&&canUseCash(profile,'financeReceive'))actions.push('accepted','rejected');
 if(row.sender_id===profile.id&&(canUseCash(profile,'cashTransferSend')||canUseCash(profile,'financeReceive')))actions.push('cancelled');
 return actions;
}
function remainder(balance,expense){
 if(typeof balance!=='number'||!Number.isFinite(balance)||balance<0||!Number.isFinite(Number(expense))||Number(expense)<0)return null;
 const decimal=value=>{const match=String(value).match(/^(\d+)(?:\.(\d*))?(?:e([+-]?\d+))?$/i);if(!match)return null;let scale=(match[2]||'').length-Number(match[3]||0),units=BigInt(match[1]+(match[2]||''));if(Math.abs(scale)>324)return null;if(scale<0){units*=10n**BigInt(-scale);scale=0;}return {units,scale};};
 const a=decimal(balance),b=decimal(Number(expense));if(!a||!b)return null;
 const scale=Math.max(a.scale,b.scale),units=a.units*10n**BigInt(scale-a.scale)-b.units*10n**BigInt(scale-b.scale);
 if(units<0n)return null;
 const digits=units.toString().padStart(scale+1,'0');return scale?(digits.slice(0,-scale)+'.'+digits.slice(-scale)).replace(/\.?0+$/,''):digits;
}
export function cashTransferCanCover(balance,amount,expense=0){
 const available=remainder(balance,expense);return available!==null&&Number.isFinite(Number(amount))&&Number(amount)>0&&Number(amount)<=Number(available);
}
export function cashTransferFullAmount(balance,expense=0){
 const amount=remainder(balance,expense);return amount!==null&&Number(amount)>0&&Number(amount)<=1e12?amount:null;
}
