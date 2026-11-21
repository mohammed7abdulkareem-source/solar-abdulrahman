'use client';
import {useEffect,useRef,useState} from 'react';
import AppIcon from './app-icons';
import {customerRecord,saveCustomer} from './customer-store.mjs';
import {canRenameCustomer,customerNameKey} from './customer-utils.mjs';
import './customer-name-editor.css';

export default function CustomerNameEditor({profile,account,onSaved}){
 const [open,setOpen]=useState(false),[record,setRecord]=useState(null),[name,setName]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState('');
 const attempt=useRef(null),generation=useRef(0),saving=useRef(false),input=useRef(null),trigger=useRef(null);
 useEffect(()=>()=>{generation.current++;},[]);
 useEffect(()=>{if(open&&record)input.current?.focus();},[open,record]);
 if(!canRenameCustomer(profile,account))return null;

 async function start(){
  const request=++generation.current;
  setOpen(true);setBusy(true);setRecord(null);setName('');setError('');setNotice('');
  try{
   const fresh=await customerRecord(account.id);
   if(request!==generation.current)return;
   if(!fresh?.token||String(fresh.id)!==String(account.id))throw new Error('تعذر تحميل بيانات العميل.');
   setRecord(fresh);setName(fresh.name);
  }catch(e){if(request===generation.current)setError(e.message||'تعذر تحميل اسم العميل.');}
  finally{if(request===generation.current)setBusy(false);}
 }
 function close(){
  generation.current++;setOpen(false);setRecord(null);setError('');setBusy(false);
  requestAnimationFrame(()=>trigger.current?.focus());
 }
 async function submit(event){
  event.preventDefault();
  if(saving.current||!record)return;
  const clean=name.trim().replace(/\s+/g,' ');
  if(customerNameKey(clean).length<2||clean.length>150){setError('اكتب اسم العميل كاملاً بحد أقصى 150 حرفاً.');return;}
  const request=generation.current;
  saving.current=true;setBusy(true);setError('');
  try{
   const saved=await saveCustomer(attempt,'rename',{id:record.id,name:clean,token:record.token});
   if(request!==generation.current)return;
   close();setNotice('تم تعديل اسم العميل.');
   try{await onSaved?.(saved);}catch{setNotice('تم حفظ الاسم. حدّث الكشف لعرضه.');}
  }catch(e){
   if(request!==generation.current)return;
   if(e.code==='PT409'||e.code==='40001')setRecord(null);
   setError(attempt.current?'تعذر تأكيد الحفظ. أعد المحاولة بنفس الاسم.':(e.message||'تعذر حفظ اسم العميل.'));
  }finally{saving.current=false;if(request===generation.current)setBusy(false);}
 }
 if(!open)return <div className="statementNameControl"><button type="button" ref={trigger} className="statementNameTrigger" onClick={start}><AppIcon name="edit" size={16}/>تعديل اسم العميل</button>{notice&&<small role="status">{notice}</small>}</div>;
 return <form className="statementNameForm" aria-label="تعديل اسم العميل" onSubmit={submit}>
  <label>اسم العميل الجديد<input ref={input} value={name} maxLength={150} autoComplete="off" disabled={busy||!record||!!attempt.current} onChange={event=>{setName(event.target.value);setError('');}}/></label>
  {busy&&!record&&<small role="status">جاري تحميل الاسم…</small>}{error&&<small role="alert">{error}</small>}
  <div>{record?<button type="submit" disabled={busy||!name.trim()||name.trim()===record.name}>{busy?'جاري الحفظ…':'حفظ الاسم'}</button>:!busy&&<button type="button" onClick={start}>تحديث بيانات العميل</button>}
   <button type="button" disabled={saving.current||!!attempt.current} onClick={close}>إلغاء</button></div>
 </form>;
}
