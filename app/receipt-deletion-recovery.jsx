'use client';
import {useEffect,useRef,useState} from 'react';
import {DELETION_ATTEMPT_EVENT,readDeletionAttempt,deletionAttemptBusy} from './receipt-deletion-attempt.mjs';
import {requestReceiptDeletion,deletionKind,deletionResultMessage} from './receipt-deletion.mjs';
export default function ReceiptDeletionRecovery({userId,onChanged}){
 const [pending,setPending]=useState(null),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[error,setError]=useState(''),live=useRef(true);
 useEffect(()=>{live.current=true;const update=()=>{setPending(readDeletionAttempt(userId));setBusy(deletionAttemptBusy(userId));};update();window.addEventListener(DELETION_ATTEMPT_EVENT,update);window.addEventListener('storage',update);return()=>{live.current=false;window.removeEventListener(DELETION_ATTEMPT_EVENT,update);window.removeEventListener('storage',update);};},[userId]);
 async function recover(){if(busy||!pending)return;setError('');setMessage('');try{const result=await requestReceiptDeletion(pending.invoiceId,pending.id);if(!live.current)return;setMessage(deletionResultMessage(result));void Promise.resolve().then(onChanged).catch(()=>{});}catch(e){if(live.current)setError(e.message||'تعذر تأكيد الحذف؛ تحقق من الاتصال ثم أعد المحاولة.');}}
 if(!pending&&!message&&!error)return null;
 return <section className="workspaceSyncError" aria-label="تأكيد الحذف السابق"><div>{pending&&<p>تأكيد {pending.action==='delete_direct'?'حذف':'طلب حذف'} {deletionKind(pending.kind)} #{pending.receiptNo} لم يصل بعد.</p>}{error&&<p role="alert">{error}</p>}{message&&<p role="status">{message}</p>}</div>{pending?<button type="button" disabled={busy} onClick={recover}>{busy?'جاري تأكيد الحذف…':'تأكيد الحذف السابق'}</button>:<button type="button" onClick={()=>{setMessage('');setError('');}}>إغلاق</button>}</section>;
}
