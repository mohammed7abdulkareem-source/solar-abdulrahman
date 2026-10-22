'use client';
import AppIcon from './app-icons';
import {contactPhoneLinks,splitContactPhones} from './phone-contact-utils.mjs';
export default function PhoneActions({phone,label='رقم الهاتف',className=''}){
 const phones=splitContactPhones(phone);if(!phones.length)return null;
 return <span className={'phoneContacts '+className}>{phones.map((value,index)=>{const links=contactPhoneLinks(value);return <span className="phoneActions" key={index}><bdi className="phoneActionNumber" dir="ltr">{value}</bdi>{links&&<><a className="phoneCall" href={links.call} aria-label={'اتصال '+label} title="اتصال" onClick={e=>e.stopPropagation()}><AppIcon name="phone" size={16}/></a><a className="phoneWhatsapp" href={links.whatsapp} target="_blank" rel="noopener noreferrer" aria-label={'واتساب '+label} title="واتساب" onClick={e=>e.stopPropagation()}><AppIcon name="whatsapp" size={17}/></a></>}</span>;})}</span>;
}
