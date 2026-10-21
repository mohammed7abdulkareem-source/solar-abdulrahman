'use client';
import {useEffect,useRef,useState} from 'react';
import AppIcon from './app-icons';
import {formatMoney as money} from './money-format.mjs';

export default function ProfitRejection({request,initialNote='',busy,uncertain,error,onReject,onClose}){
 const dialog=useRef(null),reason=useRef(null),[note,setNote]=useState(initialNote),[validation,setValidation]=useState('');
 useEffect(()=>{const before=document.activeElement;dialog.current?.showModal();reason.current?.focus();const overflow=document.body.style.overflow;document.body.style.overflow='hidden';return()=>{document.body.style.overflow=overflow;if(before?.isConnected)before.focus();};},[]);
 function submit(e){e.preventDefault();if(!note.trim()){setValidation('اكتب سبب الرفض حتى يظهر للمستخدم.');reason.current?.focus();return;}onReject(note.trim());}
 return <dialog ref={dialog} className="profitRejectDialog" aria-labelledby="profit-reject-title" onCancel={e=>{e.preventDefault();if(!busy&&!uncertain)onClose();}}>
  <form onSubmit={submit} noValidate><header><div><h2 id="profit-reject-title">رفض طلب تسوية الأرباح</h2><p>{request.ownerName} · <bdi>{money(request.profit)} د.ع</bdi></p></div><button type="button" className="profitRejectClose" aria-label="إغلاق رفض التسوية" disabled={busy||uncertain} onClick={onClose}><AppIcon name="close" size={18}/></button></header>
  <p className="profitRejectHint">يبقى ربح المستخدم بدون تسوية، ويصله إشعار بسبب الرفض.</p>
  <label>سبب الرفض<textarea ref={reason} aria-label="سبب رفض طلب التسوية" value={note} maxLength={1500} disabled={busy||uncertain} onChange={e=>{setNote(e.target.value);setValidation('');}} placeholder="اكتب السبب للمستخدم…" required/></label>
  {(validation||error)&&<p className="accountAlert error" role="alert">{validation||error}</p>}
  <div className="profitRejectActions"><button type="button" className="uiButton secondary" disabled={busy||uncertain} onClick={onClose}>رجوع</button><button type="submit" className="uiButton danger" disabled={busy}>{busy?'جاري حفظ الرفض…':uncertain?'إعادة تأكيد الرفض':'تأكيد رفض الطلب'}</button></div>
  </form>
 </dialog>;
}
