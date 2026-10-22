import {normalizeUserPhone,validUserPhone} from './user-phone-utils.mjs';
import {escapeHtml as e} from './document-format.mjs';
import {iconSvg} from './ui-icons.mjs';
export const splitContactPhones=value=>String(value??'').split(/[,،;؛/|\n]+/).map(s=>s.trim()).filter(Boolean);
export function contactPhoneLinks(value){
 const normalized=normalizeUserPhone(value);
 if(!validUserPhone(normalized)||/^\+?0+$/.test(normalized))return null;
 let international=normalized.replace(/^\+/,'');
 if(normalized.startsWith('+'))international=international.replace(/^9640(?=7\d{9}$)/,'964');
 else if(/^0[1-9]\d{7,9}$/.test(normalized))international='964'+normalized.slice(1);
 else if(/^7\d{9}$/.test(normalized))international='964'+normalized;
 return {call:'tel:'+normalized,whatsapp:'https://wa.me/'+international};
}
export function phoneContactDocument(value){
 const phones=splitContactPhones(value);if(!phones.length)return '—';
 return phones.map(phone=>{const links=contactPhoneLinks(phone);return '<span class="documentPhoneContact" style="display:inline-flex;align-items:center;gap:5px;direction:ltr;white-space:nowrap"><bdi dir="ltr">'+e(phone)+'</bdi>'+(links?'<a aria-label="اتصال" title="اتصال" href="'+links.call+'" style="display:inline-flex;color:#1c5877">'+iconSvg('phone').replace('width="18" height="18"','width="13" height="13"')+'</a><a aria-label="واتساب" title="واتساب" href="'+links.whatsapp+'" target="_blank" rel="noopener noreferrer" style="display:inline-flex;color:#147442">'+iconSvg('whatsapp').replace('width="18" height="18"','width="13" height="13"')+'</a>':'')+'</span>';}).join(' / ');
}
