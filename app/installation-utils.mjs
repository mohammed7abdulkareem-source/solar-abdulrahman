export const installationStages=[['pending','بانتظار البدء'],['in_progress','جاري التنصيب'],['completed','مراجعة التقرير'],['closed','ملف مغلق']];
export const installationIndex=status=>Math.max(0,installationStages.findIndex(([s])=>s===status));
export function addInstallationDays(day,count){const d=new Date(day+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+count);return d.toISOString().slice(0,10);}
export function installationWeek(day){const d=new Date(day+'T12:00:00Z');return Array.from({length:7},(_,i)=>addInstallationDays(day,i-(d.getUTCDay()+1)%7));}
export function installationLocalDay(value){const parts=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(value)).map(p=>[p.type,p.value]));return parts.year+'-'+parts.month+'-'+parts.day;}
export const installationTime=value=>new Intl.DateTimeFormat('en-GB',{timeZone:'Asia/Baghdad',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(new Date(value));
export function installationStart(day,time){if(!/^\d{4}-\d{2}-\d{2}$/.test(day||'')||!/^([01]\d|2[0-3]):[0-5]\d$/.test(time||''))return NaN;return Date.parse(day+'T'+time+':00+03:00');}
export const bookingSelectionKey=(day,id,time,exclude='')=>JSON.stringify([day||'',id||'',time||'',exclude||'']);
export function installationConflict(slots,day,time){const start=installationStart(day,time),end=start+6*3600000;return Number.isFinite(start)?slots.find(s=>Date.parse(s.start)<end&&Date.parse(s.end)>start):null;}
export function installationSlotsForDay(slots,day){const start=installationStart(day,'00:00'),end=start+24*3600000;return slots.filter(s=>Date.parse(s.start)<end&&Date.parse(s.end)>start);}

export function installationMatchesStatus(job,status,today){
 if(status==='all')return true;
 if(status==='today')return job.installDate===today&&job.installationStatus!=='closed';
 if(status==='open')return job.installationStatus!=='closed';
 return job.installationStatus===status;
}
