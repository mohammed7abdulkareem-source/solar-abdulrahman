'use client';
import {useEffect,useRef,useState} from 'react';
import {createPortal} from 'react-dom';
import AppIcon from './app-icons';
import {reloadVerifiedApp,watchAppVersion} from './app-update-client.mjs';
import './app-update.css';

export const APP_VERSION='4.1.24';
export default function AppUpdate(){
 const [busy,setBusy]=useState(false),[available,setAvailable]=useState(''),[error,setError]=useState(''),[statusArea,setStatusArea]=useState(null);
 const refresh=useRef(null);
 useEffect(()=>{
  setStatusArea(document.getElementById('workspace-update-notice'));
  const stop=watchAppVersion(version=>setAvailable(version===APP_VERSION?'':version));
  return ()=>{stop();refresh.current?.abort();refresh.current=null;};
 },[]);
 async function update(){
  if(refresh.current||!window.confirm('تحديث البرنامج الآن؟ احفظ أي بيانات غير محفوظة قبل المتابعة.'))return;
  const request=new AbortController();
  refresh.current=request;setBusy(true);setError('');
  try{await reloadVerifiedApp(request);}
  catch{if(refresh.current===request)setError('تعذر التحديث. تأكد من الإنترنت وحاول مجدداً.');}
  finally{if(refresh.current===request){refresh.current=null;setBusy(false);}}
 }
 const label=busy?'جاري التحديث…':available?'تحديث جديد متوفر':'تحديث البرنامج';
 return <>
  <div className="appUpdate"><button type="button" className={available?'available':''} disabled={busy} onClick={update} aria-label={label} title={'الإصدار الحالي '+APP_VERSION}><AppIcon name="refresh" size={18}/><span className="updateLabel">{label}</span></button>{error&&<small role="alert">{error}</small>}</div>
  {statusArea&&available&&createPortal(<aside className="workspaceUpdateBanner" aria-label="تحديث البرنامج">
   <span role="status">إصدار جديد متاح <bdi>{available}</bdi></span>
   <button type="button" onClick={update} disabled={busy}><AppIcon name="refresh" size={16}/>{busy?'جاري التحديث…':'تحديث الآن'}</button>
   {error&&<small role="alert">{error}</small>}
  </aside>,statusArea)}
 </>;
}
