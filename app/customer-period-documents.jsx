'use client';
import {useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import {combineCustomerDocuments,periodDocumentLabel} from './customer-account-documents.mjs';
import ReportActions from './report-actions';
import AppIcon from './app-icons';

export default function CustomerPeriodDocuments({account,from,to,category,query,invalid,a4}){
 const [result,setResult]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState('');const generation=useRef(0),request=useRef(null);
 const key=JSON.stringify([account.id,from,to,category,query]);
 useEffect(()=>{generation.current++;request.current?.abort();setResult(null);setBusy(false);setError('');return()=>{generation.current++;request.current?.abort();};},[key]);
 async function prepare(){
  if(busy||invalid)return;const seq=++generation.current,controller=new AbortController();request.current=controller;setBusy(true);setError('');setResult(null);
  const timer=setTimeout(()=>controller.abort(),15000);
  try{const {data,error}=await supabase.rpc('solar_customer_documents',{customer_id:Number(account.id),date_from:from||null,date_to:to||null,category,search_text:query.trim()}).abortSignal(controller.signal);if(error)throw error;if(seq!==generation.current)return;
   if(!data?.rows?.length)throw new Error('لا توجد وصولات ضمن الفترة والاختيارات.');
   const title=periodDocumentLabel(category)+' · '+account.name;setResult({key,html:combineCustomerDocuments(data.rows,account,a4,title),count:data.rows.length});
  }catch(e){if(seq===generation.current)setError(e.code?e.message:/[\u0600-\u06ff]/.test(e.message||'')?e.message:'تعذر تحميل الوصولات. تحقق من الاتصال وأعد المحاولة.');}finally{clearTimeout(timer);if(seq===generation.current)setBusy(false);}
 }
 const ready=result?.key===key;
 return <div className="customerPeriodExport" aria-label="تصدير وصولات الفترة"><div><span>{from||'بداية التعامل'} — {to||'اليوم'}</span><button type="button" disabled={busy||invalid} onClick={prepare}><AppIcon name="document" size={17}/>{busy?'جاري تحميل الوصولات…':'سحب '+periodDocumentLabel(category)}</button></div>{error&&<p className="miniAlert" role="alert">{error}</p>}{ready&&<><p>{result.count} وصل كامل ضمن الفترة والبحث المحددين</p><ReportActions enabled={!invalid} html={result.html} filename={periodDocumentLabel(category)+'-'+account.name}/></>}</div>;
}
