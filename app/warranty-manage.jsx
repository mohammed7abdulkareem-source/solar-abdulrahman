'use client';
import {useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import WarrantyEditor from './warranty-editor';
import {warrantyPolicy,warrantyError,warrantyUrl} from './warranty-utils.mjs';
export default function WarrantyManage({invoiceId,onChanged}){
 const [open,setOpen]=useState(false),[data,setData]=useState(null),[policy,setPolicy]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');const pending=useRef(null),lock=useRef(false);
 useEffect(()=>{let live=true;if(!open)return;setBusy(true);setError('');supabase.rpc('solar_warranty_manage',{action:'get',payload:{id:invoiceId}}).then(({data,error})=>{if(!live)return;if(error){setError(error.message);setData(null);}else{setData(data);setPolicy(data.warranty);}setBusy(false);}).catch(()=>{if(live){setError('تعذر تحميل الضمان.');setBusy(false);}});return()=>{live=false;};},[open,invoiceId]);
 async function save(){if(lock.current||!data)return;const invalid=warrantyError(policy,data.items);if(invalid){setError(invalid);return;}lock.current=true;setBusy(true);setError('');
  const payload={id:invoiceId,expectedToken:data.expectedToken,warranty:warrantyPolicy(policy,data.items)};
  try{if(!pending.current)pending.current={id:crypto.randomUUID(),payload};const {data:result,error}=await supabase.rpc('solar_warranty_manage',{action:'save',request_id:pending.current.id,payload:pending.current.payload});if(error)throw error;pending.current=null;setData(v=>({...v,warrantyToken:result.warrantyToken,warranty:result.warranty}));setMessage('تم حفظ الضمان. رمز الوصل نفسه يعرض آخر تحديث.');setOpen(false);await onChanged?.();}
  catch(err){if(err.code)pending.current=null;setError(err.code?err.message:'لم يتأكد الحفظ؛ أعد تأكيد العملية بنفس البيانات.');}finally{lock.current=false;setBusy(false);}
 }
 return <div className="warrantyManage"><button type="button" disabled={busy||!!pending.current} onClick={()=>{setOpen(v=>!v);setMessage('');}}>{open?'إغلاق الضمان':'ضمان الفاتورة'}</button>{message&&<p role="status">{message}</p>}{open&&<section className="warrantySaved" aria-label="تعديل ضمان الفاتورة">{error&&<p role="alert" className="accountAlert error">{error}</p>}{!data?busy?<p>جاري التحميل…</p>:null:<><fieldset disabled={busy||!!pending.current} style={{border:0,padding:0}}><WarrantyEditor value={policy} items={data.items} onChange={setPolicy}/></fieldset>{data.warranty?.enabled&&policy?.enabled&&data.warrantyToken&&<p><a href={warrantyUrl(data.warrantyToken)} target="_blank" rel="noopener noreferrer">فتح شهادة الضمان</a></p>}<button type="button" disabled={busy} onClick={save}>{busy?'جاري الحفظ…':pending.current?'إعادة تأكيد حفظ الضمان':'حفظ ضمان الفاتورة'}</button></>}</section>}</div>;
}
