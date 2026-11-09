'use client';
import {useEffect,useId,useRef,useState} from 'react';
import AppIcon from './app-icons';
import WorkspaceDialog from './workspace-dialog';
import {changeOwnPassword} from './password-change.mjs';
import {unlockNotificationSound,playNotificationSound} from './notification-sound.mjs';
import './password-change.css';

export default function PasswordChange({userId,onClose,onBusyChange}){
 const [oldPassword,setOldPassword]=useState(''),[newPassword,setNewPassword]=useState(''),[confirmPassword,setConfirmPassword]=useState(''),[visible,setVisible]=useState({}),[busy,setBusy]=useState(false),[error,setError]=useState(''),[success,setSuccess]=useState(null);
 const lock=useRef(false),mounted=useRef(true),oldInput=useRef(null),prefix=useId();
 useEffect(()=>{mounted.current=true;return()=>{mounted.current=false;onBusyChange?.(false);};},[onBusyChange]);
 const clear=()=>{setOldPassword('');setNewPassword('');setConfirmPassword('');setVisible({});};
 function close(){if(lock.current)return;clear();onClose();}
 async function submit(event){
  event.preventDefault();if(lock.current||success)return;
  let validation='';
  if(!oldPassword||!newPassword||!confirmPassword)validation='أكمل الرقم السري القديم والجديد وتأكيده.';
  else if(newPassword.length<6)validation='الرقم السري الجديد يجب أن يتكون من 6 أحرف أو أرقام على الأقل.';
  else if(new TextEncoder().encode(newPassword).length>72)validation='الرقم السري الجديد طويل جداً. استخدم رقماً أقصر.';
  else if(newPassword!==confirmPassword)validation='الرقم السري الجديد وتأكيده غير متطابقين.';
  else if(newPassword===oldPassword)validation='اختر رقمًا سريًا جديدًا يختلف عن القديم.';
  if(validation){setError(validation);return;}
  lock.current=true;setBusy(true);onBusyChange?.(true);setError('');void unlockNotificationSound();
  try{
   const result=await changeOwnPassword({oldPassword,newPassword,confirmPassword,userId});
   if(!result?.ok)throw new Error('لم يتأكد حفظ الرقم السري. تحقق من الاتصال وحاول مجددًا.');
   if(mounted.current){setSuccess(result);void playNotificationSound();}
  }catch(failure){if(mounted.current)setError(failure?.message||'تعذر تأكيد تغيير الرقم السري. تحقق من الاتصال ثم حاول تسجيل الدخول بالرقم الجديد.');}
  finally{lock.current=false;onBusyChange?.(false);if(mounted.current){clear();setBusy(false);oldInput.current?.focus();}}
 }
 const fields=[
  {key:'old',label:'الرقم السري القديم',value:oldPassword,set:setOldPassword,autoComplete:'current-password',ref:oldInput},
  {key:'new',label:'الرقم السري الجديد',value:newPassword,set:setNewPassword,autoComplete:'new-password'},
  {key:'confirm',label:'تأكيد الرقم السري الجديد',value:confirmPassword,set:setConfirmPassword,autoComplete:'new-password'}
 ];
 return <WorkspaceDialog open onClose={close} title="تغيير الرقم السري" className={'passwordChangeDialog'+(busy?' passwordChangePending':'')}>
  {success?<div className="passwordChangeSuccess" role="status"><span className="passwordChangeSuccessIcon"><AppIcon name="check" size={26}/></span><h3>تم تغيير الرقم السري بنجاح.</h3><p>{success.sessionRestored===false?'تم حفظ الرقم الجديد. أعد تسجيل الدخول باستخدامه لاستكمال العمل.':'استخدم الرقم السري الجديد في تسجيل الدخول القادم.'}</p><button type="button" onClick={close}>رجوع إلى حسابي</button></div>:<form className="passwordChangeForm" onSubmit={submit} noValidate aria-busy={busy}>
   <p className="passwordChangeIntro"><AppIcon name="shield" size={21}/><span>أدخل رقمك السري القديم، ثم اختر الرقم الجديد وأكده.</span></p>
   <fieldset disabled={busy}>
    {fields.map(field=><div className="passwordChangeField" key={field.key}><label htmlFor={prefix+'-'+field.key}>{field.label}</label><div className="passwordChangeInput"><input id={prefix+'-'+field.key} ref={field.ref} name={field.key==='old'?'current-password':field.key==='new'?'new-password':'confirm-password'} type={visible[field.key]?'text':'password'} dir="ltr" value={field.value} onChange={event=>{field.set(event.target.value);setError('');}} autoComplete={field.autoComplete} aria-label={field.label} aria-describedby={field.key==='new'?prefix+'-hint':undefined} maxLength={1024} required spellCheck={false} autoCapitalize="none"/><button type="button" aria-label={(visible[field.key]?'إخفاء ':'إظهار ')+field.label} aria-pressed={!!visible[field.key]} onClick={()=>setVisible(previous=>({...previous,[field.key]:!previous[field.key]}))}>{visible[field.key]?'إخفاء':'إظهار'}</button></div></div>)}
   </fieldset>
   <p className="passwordChangeHint" id={prefix+'-hint'}>6 أحرف أو أرقام على الأقل، ويختلف عن الرقم القديم.</p>
   {error&&<p className="passwordChangeError" role="alert">{error}</p>}
   <button className="passwordChangeSave" type="submit" disabled={busy||!oldPassword||!newPassword||!confirmPassword}><AppIcon name={busy?'refresh':'check'} size={19}/>{busy?'جاري الحفظ…':'حفظ الرقم السري'}</button>
   {busy&&<p className="passwordChangeProgress" role="status">جاري التحقق من الرقم القديم وحفظ الرقم الجديد…</p>}
  </form>}
 </WorkspaceDialog>;
}
