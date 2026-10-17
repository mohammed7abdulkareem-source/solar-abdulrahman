import {normalizeSearch} from './party-search-utils.mjs';
export const customerNameKey=value=>normalizeSearch(value).replace(/[\s\u200B-\u200F\u202A-\u202E\uFEFF]/g,'');
export function customerPhoneKey(value){
 let digits=normalizeSearch(value).replace(/[^0-9]/g,'');
 if(digits.startsWith('00'))digits=digits.slice(2);
 if(digits.startsWith('9640'))digits='964'+digits.slice(4);
 if(/^07\d{9}$/.test(digits))digits='964'+digits.slice(1);
 else if(/^7\d{9}$/.test(digits))digits='964'+digits;
 return digits.length>=7?digits:'';
}
export function customerMatches(rows,name,phone,excludeId){
 const nk=customerNameKey(name),pk=customerPhoneKey(phone);
 return rows.filter(c=>String(c.id)!==String(excludeId)&&((nk&&customerNameKey(c.name)===nk)||(pk&&customerPhoneKey(c.phone)===pk)));
}
export function amountInput(value){
 return normalizeSearch(value).replace(/[٬,\s]/g,'').replace(/٫/g,'.');
}
export function formatAmountInput(raw){
 const [whole,decimals]=String(raw??'').split('.');
 const grouped=whole?whole.replace(/^0+(?=\d)/,'').replace(/\B(?=(\d{3})+(?!\d))/g,','):'';
 return grouped+(decimals!==undefined?'.'+decimals:'');
}
export const validOpening=value=>Number.isFinite(Number(value))&&Math.abs(Number(value))<=1e15&&Math.abs(Number(value)*100-Math.round(Number(value)*100))<0.0001;
export function filteredCustomers(rows,query='',type='all',balance='all'){
 const words=normalizeSearch(query).split(/\s+/).filter(Boolean),phone=customerPhoneKey(query);
 return rows.filter(c=>{const text=normalizeSearch([c.name,c.phone,c.ownerName].join(' '));return (words.every(w=>text.includes(w))||(phone&&customerPhoneKey(c.phone)===phone))&&(type==='all'||c.customerType===type)&&(balance==='all'||(balance==='due'?c.balance>0:balance==='credit'?c.balance<0:Number(c.balance)===0));});
}
