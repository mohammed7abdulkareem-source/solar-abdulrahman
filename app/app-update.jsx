'use client';
import {useEffect,useState} from 'react';
export const APP_VERSION='3.16.0';
export default function AppUpdate(){
 const [busy,setBusy]=useState(false),[available,setAvailable]=useState(false),[error,setError]=useState('');
 useEffect(()=>{let live=true;const check=()=>{if(document.visibilityState!=='visible')return;fetch('/version.json',{cache:'no-store'}).then(r=>r.ok?r.json():null).then(v=>{if(live&&v?.version)setAvailable(v.version!==APP_VERSION)}).catch(()=>{})};check();window.addEventListener('focus',check);return()=>{live=false;window.removeEventListener('focus',check)}},[]);
 async function update(){
  if(busy||!confirm('تحديث البرنامج الآن؟ احفظ أي بيانات غير محفوظة قبل المتابعة.'))return;
  setBusy(true);setError('');
  try{
   const response=await fetch('/version.json?check='+Date.now(),{cache:'no-store',signal:AbortSignal.timeout(15000)});if(!response.ok)throw new Error();await response.json();
   if('serviceWorker' in navigator){const registration=await navigator.serviceWorker.register('/sw.js',{updateViaCache:'none'});await registration.update();const worker=registration.installing||registration.waiting;if(worker&&worker.state!=='activated')await new Promise(resolve=>{const done=()=>{clearTimeout(timer);worker.removeEventListener('statechange',changed);resolve()};const changed=()=>{if(['activated','redundant'].includes(worker.state))done()};const timer=setTimeout(done,5000);worker.addEventListener('statechange',changed)})}
   const url=new URL(window.location.href);url.searchParams.set('updated',String(Date.now()));window.location.replace(url.href);
  }catch{setError('تعذر التحديث؛ تأكد من الإنترنت وحاول مجدداً.');setBusy(false)}
 }
 return <div className="appUpdate"><button type="button" className={available?'available':''} disabled={busy} onClick={update} title={'الإصدار الحالي '+APP_VERSION}>{busy?'جاري التحديث…':available?'↻ تحديث جديد متوفر':'↻ تحديث البرنامج'}</button>{error&&<small role="alert">{error}</small>}</div>;
}
