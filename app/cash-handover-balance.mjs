export const CASH_HANDOVER_BALANCE_MAX_AGE=30000;

export const cashHandoverBalanceKey=(actor,sender,currency)=>JSON.stringify([actor,sender,currency]);

export function cashHandoverOwnerBalance(owners,ownerId,currency){
 if(!['IQD','USD'].includes(currency)||!Array.isArray(owners))return null;
 const raw=owners.find(owner=>owner.id===ownerId)?.[currency];
 if(typeof raw!=='number'&&(typeof raw!=='string'||!raw.trim()))return null;
 const amount=Number(raw);
 return Number.isFinite(amount)?amount:null;
}

// A snapshot belongs to the exact source/currency selection. Missing and expired
// reads must stay unknown rather than becoming a zero or another owner's money.
export function cashHandoverBalance(snapshot,key,ownerId,currency,now=Date.now()){
 if(!snapshot||snapshot.key!==key||!Number.isFinite(snapshot.readAt)||now<snapshot.readAt||now-snapshot.readAt>=CASH_HANDOVER_BALANCE_MAX_AGE)return null;
 return cashHandoverOwnerBalance(snapshot.owners,ownerId,currency);
}

export function cashHandoverFullAmount(balance){
 if(typeof balance!=='number'||!Number.isFinite(balance)||balance<=0||balance>1e12)return null;
 const rounded=Math.round(balance*100)/100;
 if(Math.abs(balance-rounded)>0.000001)return null;
 return String(rounded);
}
