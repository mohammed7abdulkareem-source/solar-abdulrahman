'use client';
import {useRef,useState} from 'react';
import {supabase} from './supabase';
import {saveRequest} from './save-request.mjs';
import {unlockNotificationSound,playNotificationSound} from './notification-sound.mjs';
import AppIcon from './app-icons';

export default function SalePreparation({invoice,profile,onPrepared}){
 const lock=useRef(false),pending=useRef(null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
 if(invoice.kind!=='sale'||!profile?.active||['installer','warehouse'].includes(profile.user_type)||!(profile.is_admin||((invoice.createdBy||invoice.created_by)===profile.id&&(profile.permissions?.sale||profile.permissions?.warehouse))))return null;
 if((invoice.warehouseStatus||invoice.warehouse_status)==='ready'&&!pending.current)return null;
 async function prepare(){
  if(lock.current)return;lock.current=true;setBusy(true);setError('');setMessage('');void unlockNotificationSound();
  try{
   if(!pending.current){
    const {data,error}=await supabase.rpc('solar_sale_preparation',{action:'get',invoice_id:invoice.id});if(error)throw error;
    if(data.warehouseStatus==='ready'){onPrepared?.(data);return;}
    if(data.pricingPending)throw new Error('المواد الجديدة بانتظار تسعير الإدارة قبل إكمال التجهيز.');
    if(!confirm('تأكيد تجهيز جميع مواد وصل الجملة #'+data.receiptNo+' من '+data.warehouseName+'؟'))return;
    pending.current={action:'ready',invoice_id:invoice.id,expected_token:data.token,request_id:crypto.randomUUID()};
   }
   const {data,error}=await saveRequest(signal=>supabase.rpc('solar_sale_preparation',pending.current).abortSignal(signal));if(error)throw error;
   pending.current=null;setMessage(data.warehouseStatus==='ready'?'تم تجهيز الوصل مباشرة.':'تغيّرت مواد الوصل بعد التجهيز السابق؛ راجعها وأكّد تجهيزها من جديد.');
   void playNotificationSound();onPrepared?.(data);window.dispatchEvent(new Event('solar-warehouse-changed'));
  }catch(e){if(e.code&&/^[0-9A-Z]{5}$/.test(e.code))pending.current=null;setError(e.message||'تعذر تأكيد التجهيز. أعد تأكيد نفس الطلب.');}
  finally{lock.current=false;setBusy(false);}
 }
 return <div className="saleDirectPreparation"><button type="button" className="saleDirectPrepareButton" disabled={busy} onClick={prepare}><AppIcon name="check" size={18}/>{busy?'جاري تأكيد التجهيز…':pending.current?'إعادة تأكيد التجهيز':'تجهيز مباشر'}</button><small>تأكيد تجهيز كل مواد الوصل من مخزنه المحدّد.</small>{error&&<p role="alert" className="workflowError">{error}</p>}{message&&<p role="status" className="workflowSuccess">{message}</p>}</div>;
}
