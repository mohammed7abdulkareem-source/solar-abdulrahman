export function notificationReadBoundary(notices){
 return notices.reduce((latest,notice)=>Number.isFinite(Date.parse(notice.created_at))&&(!latest||Date.parse(notice.created_at)>Date.parse(latest))?notice.created_at:latest,null);
}

export function applyConfirmedNotificationReads(notices,confirmed){
 const dates=confirmed instanceof Map?confirmed:new Map(confirmed.map(row=>[row.id,row.read_at]));
 return notices.map(notice=>dates.has(notice.id)?{...notice,read_at:dates.get(notice.id)}:notice);
}

export function mergeNotificationRows(loaded,arrivals=[],confirmed=new Map(),limit=30){
 const rows=new Map(loaded.map(row=>[row.id,row]));
 for(const row of arrivals)rows.set(row.id,row);
 return applyConfirmedNotificationReads([...rows.values()],confirmed).sort((a,b)=>Date.parse(b.created_at)-Date.parse(a.created_at)||String(b.id).localeCompare(String(a.id))).slice(0,limit);
}

// Keep the selected ID set fixed before any writes. The cutoff comes from an
// already displayed server timestamp, not the device's potentially skewed clock.
export async function unreadNotificationIds(client,{userId,before,signal}){
 if(!userId||!before||!Number.isFinite(Date.parse(before)))throw new Error('تعذر تحديد الإشعارات الحالية. حدّث القائمة ثم حاول مجددًا.');
 const ids=new Set();let after='';
 for(;;){
  let query=client.from('solar_notifications').select('id').eq('user_id',userId).is('read_at',null).lte('created_at',before).order('id',{ascending:true}).limit(250);
  if(after)query=query.gt('id',after);
  if(signal)query=query.abortSignal(signal);
  const{data,error}=await query;if(error)throw error;
  if(!Array.isArray(data))throw new Error('تعذر التحقق من قائمة الإشعارات.');
  if(!data.length)break;
  const next=data.at(-1)?.id;
  if(typeof next!=='string'||next<=after)throw new Error('تعذر إكمال قائمة الإشعارات.');
  for(const row of data)if(typeof row.id==='string')ids.add(row.id);
  after=next;
 }
 return [...ids];
}

export async function markNotificationIdsRead(client,{userId,ids,readAt=new Date().toISOString(),signal,onConfirmed=()=>{}}){
 if(!userId)throw new Error('يجب تسجيل الدخول أولًا.');
 const unique=[...new Set(ids)];let updatedCount=0;
 try{
  for(let offset=0;offset<unique.length;offset+=100){
   const batch=unique.slice(offset,offset+100),requested=new Set(batch);
   let query=client.from('solar_notifications').update({read_at:readAt}).eq('user_id',userId).in('id',batch).is('read_at',null).select('id,read_at');
   if(signal)query=query.abortSignal(signal);
   const{data,error}=await query;if(error)throw error;
   if(!Array.isArray(data))throw new Error('لم يصل تأكيد قراءة الإشعارات.');
   const confirmed=data.filter(row=>requested.has(row.id)&&typeof row.read_at==='string'&&row.read_at);
   updatedCount+=confirmed.length;onConfirmed(confirmed);
  }
  return{updatedCount,targetCount:unique.length};
 }catch(error){const failure=new Error(error.message||'تعذر تأكيد قراءة الإشعارات.');failure.updatedCount=updatedCount;failure.targetCount=unique.length;throw failure;}
}

export async function markAllNotificationsRead(client,options){
 const ids=await unreadNotificationIds(client,options);
 return markNotificationIdsRead(client,{...options,ids});
}
