export const escapeHtml=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function invoiceDate(value){
 if(!value)return '—';
 const date=new Date(value);if(!Number.isFinite(date.getTime()))return '—';
 return new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Baghdad',day:'2-digit',month:'2-digit',year:'numeric'}).format(date);
}
export function warrantyLastDay(value,term){
 const amount=Number(term?.duration);if(!Number.isInteger(amount)||amount<=0||!['days','months','years'].includes(term?.unit))return null;
 const parsed=new Date(value);if(!Number.isFinite(parsed.getTime()))return null;
 const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(parsed);
 const get=key=>Number(parts.find(x=>x.type===key).value),year=get('year'),month=get('month')-1,day=get('day');
 let end;
 if(term.unit==='days')end=new Date(Date.UTC(year,month,day+amount));
 else {
  const target=new Date(Date.UTC(year+(term.unit==='years'?amount:0),month+(term.unit==='months'?amount:0),1));
  const last=new Date(Date.UTC(target.getUTCFullYear(),target.getUTCMonth()+1,0)).getUTCDate();
  end=new Date(Date.UTC(target.getUTCFullYear(),target.getUTCMonth(),Math.min(day,last)));
 }
 end.setUTCDate(end.getUTCDate()-1);
 return invoiceDate(end);
}
