'use client';
import {useEffect,useState} from 'react';
import {supabase} from './supabase';
import {movementHtml} from './customer-account-documents.mjs';
import {formatMoney as money} from './money-format.mjs';
import {invoiceDate} from './document-format.mjs';
import ReportActions from './report-actions';

export default function CustomerMovementDocument({account,movementId,a4}){
 const [data,setData]=useState(null),[error,setError]=useState(''),[retry,setRetry]=useState(0);
 useEffect(()=>{let live=true;const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),12000);setData(null);setError('');
  supabase.rpc('solar_customer_movement',{customer_id:Number(account.id),movement_id:Number(movementId)}).abortSignal(controller.signal).then(({data,error})=>{if(error)throw error;if(!data)throw new Error('الوصل غير متاح');if(live)setData(data);}).catch(e=>{if(live)setError(e.code?e.message:'تعذر تحميل الوصل الكامل. أعد المحاولة.');}).finally(()=>clearTimeout(timer));
  return()=>{live=false;clearTimeout(timer);controller.abort();};
 },[account.id,movementId,retry]);
 if(error)return <div className="miniAlert" role="alert">{error}<button type="button" onClick={()=>setRetry(n=>n+1)}>إعادة تحميل الوصل</button></div>;
 if(!data)return <p className="miniEmpty" role="status">جاري تحميل الوصل الكامل…</p>;
 const invoice=data.invoice,receipt=data.receipt,m=data.movement,items=invoice?.items||receipt?.invoice?.items||[],system=invoice?.kind==='system'||!!receipt?.invoice;
 const snapshot=invoice?.invoice_account;
 return <section className="customerOriginalMovement" aria-label="الوصل الكامل">
  <div className="customerReceiptContacts"><div><small>مسؤول الوصل</small><b>{m.creatorName||'—'}</b>{m.creatorPhone&&<bdi dir="ltr">{m.creatorPhone}</bdi>}</div><div><small>العميل</small><b>{account.name}</b>{(invoice?.customer_phone||account.phone)&&<bdi dir="ltr">{invoice?.customer_phone||account.phone}</bdi>}</div></div>
  {invoice?.warehouse_name&&<p className="customerReceiptWarehouse">المخزن: <b>{invoice.warehouse_name}</b> · {invoice.warehouse_status==='ready'?'✓ تم التجهيز':'بانتظار التجهيز'}</p>}
  {items.length>0&&<div className="customerReceiptItems"><h3>{invoice?'مواد الفاتورة':'مواد المنظومة المرتبطة'} <small>{items.length} فقرة</small></h3>{items.map((i,n)=><article key={n}><header><span>{n+1}</span><div><b dir="auto">{i.product_name||i.name}</b><small>{[i.brand_name||i.brand,i.category].filter(Boolean).join(' · ')}</small></div></header><div className="customerReceiptItemNumbers"><span>الكمية <b>{money(i.qty)}</b></span>{!system&&<><span>سعر الوحدة <b><bdi>{money(i.price)} د.ع</bdi></b></span><span>المجموع <b><bdi>{money(Number(i.qty)*Number(i.price))} د.ع</bdi></b></span></>}</div></article>)}</div>}
  {invoice&&<div className="customerReceiptTotal"><span>مبلغ الفاتورة</span><b><bdi>{money(invoice.total)} د.ع</bdi></b></div>}
  {snapshot&&<div className="customerReceiptSnapshot"><h3>ملخص الحساب عند إصدار الفاتورة</h3><dl>{[['الحساب السابق',snapshot.available?snapshot.previousBalance:null],['مبلغ الفاتورة',snapshot.invoiceTotal],['المدفوع عنها',snapshot.paidNow],['الحساب النهائي',snapshot.available?snapshot.balanceAfter:null]].map(([label,value])=><div key={label}><dt>{label}</dt><dd>{value==null?'—':<bdi>{money(value)} د.ع</bdi>}</dd></div>)}</dl><p><b>آخر تسديد سابق: </b>{snapshot.lastPayment?<><bdi>{money(snapshot.lastPayment.amount)} د.ع</bdi> · {invoiceDate(snapshot.lastPayment.date)} · وصل #{snapshot.lastPayment.receiptNo||'—'}</>:snapshot.available?'لا يوجد تسديد سابق مسجّل.':'آخر تسديد سابق غير متاح.'}</p></div>}
  {receipt&&<div className="customerReceiptSnapshot"><h3>{receipt.total<0?'وصل إضافة على الحساب':'وصل التسديد'}</h3><dl><div><dt>الحساب السابق</dt><dd><bdi>{money(receipt.oldBalance)} د.ع</bdi></dd></div><div><dt>{receipt.total<0?'الإضافة':'التسديد'}</dt><dd><bdi>{money(Math.abs(receipt.total))} د.ع</bdi></dd></div><div><dt>الحساب بعد الوصل</dt><dd><bdi>{money(receipt.remaining)} د.ع</bdi></dd></div><div><dt>المستلم</dt><dd>{receipt.cashOwnerName}</dd></div>{receipt.invoice&&<div><dt>المنظومة المرتبطة</dt><dd>#{receipt.invoice.receiptNo}</dd></div>}</dl></div>}
  {invoice&&<p className="customerReceiptWarranty">{invoice.warranty?.enabled?'تفاصيل ضمان المواد والصيانة والباركود موجودة بالوصل الأصلي.':'الفاتورة بدون ضمان محدد.'}</p>}
  <ReportActions enabled html={movementHtml(data,account,a4)} filename={'وصل-'+account.name+'-'+(m.receiptNo||m.id)}/>
 </section>;
}
