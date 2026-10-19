export function normalizeUserPhone(value){
 let phone=String(value??'').trim().replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-1776)).replace(/[\s()\-‎‏]/g,'');
 if(phone.startsWith('00'))phone='+'+phone.slice(2);
 return phone;
}
export const validUserPhone=value=>/^\+?[0-9]{7,15}$/.test(normalizeUserPhone(value));
