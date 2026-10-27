export const normalizeHonorific=value=>String(value??'').trim().replace(/\s+/g,' ');
export const validHonorific=value=>(value==null||typeof value==='string')&&!/[<>\u0000-\u001f\u007f]/.test(value??'')&&Array.from(normalizeHonorific(value)).length<=50;
export function userDisplayName(user,fallback='مستخدم'){
 const name=String(user?.display_name||user?.username||fallback).trim(),title=normalizeHonorific(user?.honorific);
 return title&&name&&name!==title&&!name.startsWith(title+' ')?title+' '+name:name;
}
