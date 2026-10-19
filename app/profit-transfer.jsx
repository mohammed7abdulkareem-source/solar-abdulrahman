'use client';
import {useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import {saveRequest} from './save-request.mjs';
import {money} from './supplier-utils.mjs';
export default function ProfitTransfer({rows,staff,onClose,onSaved,onLocked}){
 const [owner,setOwner]=useState(''),[note,setNote]=useState(''),[preview,setPreview]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[uncertain,setUncertain]=useState(false),attempt=useRef(null),sequence=useRef(0);
 const signature=JSON.stringify(rows.map(r=>[r.id,r.earned]));
 useEffect(()=>{setPreview(null);sequence.current++;},[signature,owner,note]);
 useEffect(()=>()=>{sequence.current++;},[]);
 async function review(){if(busy||attempt.current||!owner||!rows.length)return;const seq=++sequence.current;setBusy(true);onLocked(true);setError('');try{const {data,error}=await supabase.rpc('solar_profit_transfer',{action:'preview',payload:{invoiceIds:rows.map(r=>r.id),ownerId:owner,note}});if(seq!==sequence.current)return;if(error)throw error;setPreview(data);}catch(e){if(seq===sequence.current)setError(e.message||'تعذر عرض المعاينة.');}finally{setBusy(false);onLocked(false);}}
 async function save(){if(busy||!preview)return;setBusy(true);onLocked(true);setError('');try{
  if(!attempt.current)attempt.current={id:crypto.randomUUID(),payload:{invoiceIds:preview.rows.map(r=>r.invoiceId),ownerId:preview.ownerId,note,expectedToken:preview.token}};
  const {data,error}=await saveRequest(signal=>supabase.rpc('solar_profit_transfer',{action:'apply',request_id:attempt.current.id,payload:attempt.current.payload}).abortSignal(signal));if(error)throw error;
  attempt.current=null;setUncertain(false);onLocked(false);onSaved(data);
 }catch(e){if(e.code){attempt.current=null;setUncertain(false);setPreview(null);onLocked(false);}else setUncertain(true);setError(e.code?e.message:'لم يتأكد الرد؛ أعد تأكيد الحفظ بنفس البيانات ولن يتكرر التحويل.');}finally{setBusy(false);}}
 return <section className="profitTransferPanel" aria-label="تحويل أرباح الفواتير"><header><h3>تحويل ربح الفواتير</h3><button type="button" className="uiButton" disabled={busy||uncertain} onClick={onClose}>إلغاء</button></header><p>علّم الفواتير المطلوبة من القائمة أدناه، ثم اختر المستخدم المستفيد. ينتقل الربح فقط، وتبقى ملكية الوصل والقاصة وحساب الزبون كما هي.</p><fieldset disabled={busy||uncertain}><label>المستخدم المستفيد<select aria-label="المستخدم المستفيد من الربح" value={owner} onChange={ev=>setOwner(ev.target.value)}><option value="">اختر المستخدم</option>{staff.filter(u=>u.active!==false&&!['warehouse','installer'].includes(u.user_type)).map(u=><option key={u.id} value={u.id}>{u.display_name||u.username}</option>)}</select></label><label>ملاحظة اختيارية<input aria-label="ملاحظة تحويل الأرباح" value={note} maxLength={1000} onChange={ev=>setNote(ev.target.value)}/></label></fieldset><div className="profitTransferSelection"><span>{rows.length} فاتورة محددة</span><b>{money(rows.reduce((sum,r)=>sum+r.earned,0))} د.ع</b></div>
  {!preview&&<button type="button" className="uiButton primary" disabled={busy||!owner||!rows.length} onClick={review}>{busy?'جاري المراجعة…':'معاينة التغيير'}</button>}
  {preview&&<div className="profitTransferPreview"><b>سيُضاف إلى أرباح {preview.ownerName}: {money(preview.total)} د.ع</b>{preview.rows.map(r=><div key={r.invoiceId}><span>#{r.receiptNo} · من {r.ownerName}</span><strong>{money(r.profit)} د.ع</strong></div>)}<button type="button" className="uiButton primary" disabled={busy} onClick={save}>{busy?'جاري حفظ التغيير…':uncertain?'إعادة تأكيد الحفظ':'تأكيد حفظ التغيير'}</button></div>}{error&&<p role="alert" className="accountAlert error">{error}</p>}
 </section>;
}
