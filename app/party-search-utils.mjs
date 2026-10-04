export const normalizeSearch=value=>String(value??'').normalize('NFKC').replace(/[\u064B-\u065F\u0670\u0640]/g,'').replace(/[أإآٱ]/g,'ا').replace(/ى/g,'ي').replace(/[٠-٩]/g,d=>String(d.charCodeAt(0)-1632)).replace(/[۰-۹]/g,d=>String(d.charCodeAt(0)-1776)).toLowerCase().trim();
export function filterParties(rows,query){
 const words=normalizeSearch(query).split(/\s+/).filter(Boolean);
 return rows.filter(r=>{const text=normalizeSearch([r.name,r.phone,r.customerType].join(' '));return words.every(w=>text.includes(w)||normalizeSearch(r.phone).replace(/[^0-9+]/g,'').includes(w.replace(/[\s()-]/g,'')))});
}
