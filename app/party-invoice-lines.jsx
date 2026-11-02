'use client';
import {useEffect,useState} from 'react';
import {supabase} from './supabase';
import {invoiceLines} from './party-invoice-reports.mjs';
import {formatMoney as money,currencyUnit as unit} from './money-format.mjs';

export function useCustomerInvoiceLines(account,rows,active){
 const ids=JSON.stringify(rows.filter(row=>row.category==='invoices').map(row=>row.id));
 const key=JSON.stringify([account.id,account.token,account.name,ids]);
 const [state,setState]=useState({key:'',documents:{},loading:false,error:''}),[retry,setRetry]=useState(0);
 useEffect(()=>{
  if(!active)return;
  let live=true;const controller=new AbortController(),invoiceIds=JSON.parse(ids);
  setState({key,documents:{},loading:invoiceIds.length>0,error:''});
  if(!invoiceIds.length)return()=>{live=false;controller.abort()};
  async function load(){
   const documents={};
   try{
    if(!account.token)throw new Error('حدّث الحساب قبل عرض تفاصيل الفواتير.');
    for(let offset=0;offset<invoiceIds.length;offset+=100){
     const timer=setTimeout(()=>controller.abort(),20000);
     let response;try{response=await supabase.rpc('solar_customer_invoice_report_batch',{customer_id:Number(account.id),invoice_ids:invoiceIds.slice(offset,offset+100),expected_token:account.token}).abortSignal(controller.signal);}finally{clearTimeout(timer)}
     if(response.error)throw response.error;
     if(response.data?.customerName!==account.name||!Array.isArray(response.data?.rows))throw new Error('تغيّر الحساب؛ اضغط تحديث قبل عرض الفواتير.');
     for(const doc of response.data.rows)documents[String(doc.id)]=doc;
    }
    if(live)setState({key,documents,loading:false,error:''});
   }catch(error){if(live)setState({key,documents:{},loading:false,error:/[\u0600-\u06ff]/.test(error.message||'')?error.message:'تعذر تحميل تفاصيل الفواتير. تحقق من الاتصال وأعد المحاولة.'});}
  }
  void load();return()=>{live=false;controller.abort()};
 },[active,key,ids,account.id,account.name,account.token,retry]);
 if(!active)return {ready:true,documents:{},loading:false,error:'',retry:()=>setRetry(x=>x+1)};
 return {ready:state.key===key&&!state.loading&&!state.error,documents:state.key===key?state.documents:{},loading:state.key!==key||state.loading,error:state.key===key?state.error:'',retry:()=>setRetry(x=>x+1)};
}

export default function PartyInvoiceLines({account,row,documents,loading}){
 const lines=invoiceLines(account,row,documents);
 if(loading)return <p className="partyInvoiceHint">جاري تحميل المواد…</p>;
 if(!lines.available)return <p className="partyInvoiceHint">تفاصيل المواد غير متاحة ضمن صلاحيات الحساب.</p>;
 if(!lines.items.length)return <p className="partyInvoiceHint">لا توجد مواد محفوظة لهذه الفاتورة.</p>;
 return <div className="partyInvoiceItems"><div className="partyInvoiceItemsHead"><span>المادة</span><span>العدد</span><span>السعر</span><span>المجموع</span></div>{lines.items.map((item,index)=><div className="partyInvoiceItem" key={index}><span><b dir="auto">{item.name}</b>{(item.brand||item.category)&&<small>{[item.brand,item.category].filter(Boolean).join(' · ')}</small>}</span><span><small>العدد</small><bdi>{item.qty===null?'—':money(item.qty)}</bdi></span><span><small>السعر</small><bdi>{item.price===null?'—':money(item.price,lines.currency)+' '+unit(lines.currency)}</bdi></span><span><small>المجموع</small><bdi>{item.total===null?'—':money(item.total,lines.currency)+' '+unit(lines.currency)}</bdi></span></div>)}<p>أسعار المواد بعملة الفاتورة ({lines.currency}) · الرصيد بعملة الحساب ({account.currency})</p></div>;
}
