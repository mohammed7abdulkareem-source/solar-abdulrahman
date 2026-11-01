'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import AppIcon from './app-icons';
import {saveRequest} from './save-request.mjs';
import {quoteDefaultValues,quoteDefaultsError,quoteDefaultsAttempt} from './quote-defaults-utils.mjs';

export function useQuoteDefaults(userId){
 const [data,setData]=useState(null),[loadError,setLoadError]=useState(''),[saveError,setSaveError]=useState(''),[message,setMessage]=useState(''),[saving,setSaving]=useState(false),[pending,setPending]=useState(null);
 const sequence=useRef(0),lock=useRef(false),attempt=useRef(null);
 const reload=useCallback(async()=>{const seq=++sequence.current;try{const r=await supabase.rpc('solar_quote_defaults',{action:'get'});if(r.error)throw r.error;if(!r.data||!Number.isSafeInteger(r.data.revision))throw Error('تعذر تأكيد مصاريف التحصيل.');if(seq===sequence.current){setData(r.data);setLoadError('');}return r.data;}catch(e){if(seq===sequence.current)setLoadError(e.message||'تعذر تحميل مصاريف التحصيل.');return null;}},[]);
 useEffect(()=>{try{const old=quoteDefaultsAttempt(localStorage,userId).read();attempt.current=old;setPending(old);}catch{}reload();const refresh=()=>{if(document.visibilityState==='visible')void reload();};const timer=setInterval(refresh,15000);window.addEventListener('focus',refresh);window.addEventListener('solar-quote-defaults',refresh);return()=>{sequence.current++;clearInterval(timer);window.removeEventListener('focus',refresh);window.removeEventListener('solar-quote-defaults',refresh);};},[userId,reload]);
 async function save(form){
  if(lock.current)return false;setSaveError('');setMessage('');
  if(!attempt.current){const values=quoteDefaultValues(form),invalid=quoteDefaultsError(values);if(invalid){setSaveError(invalid);return false;}if(!data?.canManage||loadError){setSaveError('حدّث المصاريف وتأكد من صلاحية الحفظ للجميع.');return false;}attempt.current={id:crypto.randomUUID(),payload:{...values,expectedRevision:data.revision}};setPending(attempt.current);try{quoteDefaultsAttempt(localStorage,userId).write(attempt.current);}catch{}}
  lock.current=true;setSaving(true);
  try{const request=attempt.current;const r=await saveRequest(signal=>supabase.rpc('solar_quote_defaults',{action:'save',request_id:request.id,payload:request.payload}).abortSignal(signal));if(r.error)throw r.error;attempt.current=null;setPending(null);try{quoteDefaultsAttempt(localStorage,userId).clear()}catch{}setMessage('تم حفظ مصاريف التحصيل للجميع. الحسابات الجديدة تعتمدها تلقائيًا.');window.dispatchEvent(new Event('solar-quote-defaults'));await reload();return true;}
  catch(e){if(/^[0-9A-Z]{5}$/.test(e.code||'')){attempt.current=null;setPending(null);try{quoteDefaultsAttempt(localStorage,userId).clear()}catch{}setSaveError(e.message||'تعذر حفظ المصاريف.');if(e.code==='PT409'||e.code==='42501')await reload();}else setSaveError('لم يتأكد رد الحفظ. أعد تأكيد الحفظ السابق؛ لن تتكرر العملية.');return false;}
  finally{lock.current=false;setSaving(false);}
 }
 return {data,loadError,saveError,message,saving,pending,reload,save,ready:!!data&&!loadError,clearFeedback:()=>{setMessage('');setSaveError('');}};
}
export default function QuoteDefaultsControls({state,form,onApply,busy=false}){
 return <section className="quoteSharedDefaults" aria-label="مصاريف التحصيل العامة"><header><span><AppIcon name="settings" size={19}/><b>مصاريف التحصيل العامة</b></span><small>{state.data?'الإصدار '+state.data.revision:'جاري التحميل…'}</small></header><p>احفظ القيم لتُعتمد بالحسابات الجديدة للمستخدمين. المسودات المحفوظة تحتفظ بقيمها؛ استخدم المصاريف العامة لتطبيقها على هذا العرض.</p><div className="quoteDefaultsActions"><button type="button" disabled={busy||state.saving||!!state.pending||!state.ready} onClick={onApply}>استخدام المصاريف العامة</button>{state.data?.canManage&&<button type="button" className="quoteDefaultsSave" disabled={busy||state.saving||!state.ready} onClick={()=>state.save(form)}><AppIcon name="check" size={17}/>{state.saving?'جاري حفظ المصاريف…':state.pending?'تأكيد حفظ المصاريف السابق':'حفظ المصاريف للجميع'}</button>}</div>{state.pending&&<p className="quoteDefaultsPending">يوجد حفظ سابق بانتظار التأكيد. زر التأكيد يتحقق من نفس الطلب المحفوظ قبل إرسال أي تغيير جديد.</p>}{state.saveError&&<p role="alert" className="workflowError">{state.saveError}</p>}{state.message&&<p role="status" className="workflowSuccess">{state.message}</p>}{!state.data?.canManage&&state.ready&&<small>الحفظ للجميع متاح للإدارة أو لمن مُنحت له الصلاحية المخصصة.</small>}</section>;
}
