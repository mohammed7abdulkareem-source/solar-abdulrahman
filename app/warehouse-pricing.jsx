'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import {saveRequest} from './save-request.mjs';
import {formatMoney as money} from './money-format.mjs';
import MoneyInput from './money-input';
import AppIcon from './app-icons';

const allowed=p=>p?.active&&!['warehouse','installer'].includes(p.user_type)&&(p.is_admin||p.permissions?.sale===true);
async function pricing(action,args={}){const {data,error}=await supabase.rpc('solar_warehouse_pricing',{action,...args});if(error)throw error;return data;}
export default function WarehousePricing({profile,onChanged}){
 const [rows,setRows]=useState([]),[detail,setDetail]=useState(null),[prices,setPrices]=useState({}),[busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');
 const attempt=useRef(null),lock=useRef(false),live=useRef(true),canPrice=allowed(profile);
 const load=useCallback(async()=>{if(!canPrice)return;try{const r=await pricing('list');if(live.current)setRows(r.rows);}catch(e){if(live.current)setError(e.message||'تعذر تحميل طلبات تسعير المواد');}},[canPrice,profile?.id]);
 useEffect(()=>{live.current=true;load();window.addEventListener('solar-notification',load);window.addEventListener('focus',load);return()=>{live.current=false;window.removeEventListener('solar-notification',load);window.removeEventListener('focus',load);};},[load]);
 async function open(id){if(lock.current)return;setError('');setMessage('');setBusy(true);try{const data=await pricing('get',{invoice_id:id});setDetail(data);setPrices({});attempt.current=null;}catch(e){setError(e.message||'تعذر فتح الفقرات');}finally{setBusy(false);}}
 async function submit(action){if(lock.current||!detail)return;if(action==='approve'&&detail.items.some(i=>i.lineId==null&&(!Number.isFinite(Number(prices[i.productId]))||Number(prices[i.productId])<=0))){setError('أدخل سعر البيع لكل مادة جديدة');return;}
  if(action==='cancel'&&!confirm('إلغاء تعديل المخزن والرجوع إلى مواد الفاتورة المسجّلة؟'))return;
  lock.current=true;setBusy(true);setError('');const payload={action,invoice_id:detail.id,expected_token:detail.token,prices:action==='approve'?detail.items.filter(i=>i.lineId==null).map(i=>({productId:i.productId,price:Number(prices[i.productId])})):null},signature=JSON.stringify(payload);
  try{if(attempt.current&&attempt.current.signature!==signature)throw new Error('أعد تأكيد محاولة التسعير السابقة بنفس البيانات أولاً.');if(!attempt.current)attempt.current={signature,id:crypto.randomUUID()};
   const {error}=await saveRequest(signal=>supabase.rpc('solar_warehouse_pricing',{...payload,request_id:attempt.current.id}).abortSignal(signal));if(error){if(error.code)attempt.current=null;throw error;}
   attempt.current=null;setDetail(null);setMessage(action==='approve'?'تم اعتماد الأسعار وتحديث جميع فقرات الوصل والمخزون وإشعار مسؤول التجهيز.':'تم إلغاء تعديل المواد وإعادة الوصل المسجّل للتجهيز.');await load();await onChanged?.();
  }catch(e){setError(e.message||'تعذر تأكيد العملية؛ أعد المحاولة بنفس البيانات.');}finally{lock.current=false;setBusy(false);}
 }
 if(!canPrice)return null;
 if(!rows.length&&!detail&&!error&&!message)return null;
 const total=detail?Number(detail.expenses||0)+detail.items.reduce((n,i)=>n+Number(i.qty)*Number(i.lineId==null?prices[i.productId]||0:i.price),0):0;
 return <section className="warehousePricing" aria-label="تسعير إضافات المخزن"><header><h3><AppIcon name="receipt" size={18}/>مواد بانتظار تسعير الإدارة <small>{rows.length}</small></h3><button type="button" disabled={busy} onClick={load}>تحديث</button></header>
  {message&&<p className="workflowSuccess" role="status">{message}</p>}{error&&<p className="workflowError" role="alert">{error}</p>}
  {!detail?<div className="warehousePricingList">{rows.map(r=><button type="button" key={r.id} disabled={busy} onClick={()=>open(r.id)}><span><b>{r.party||'زبون نقدي'} · #{r.receiptNo}</b><small>{r.warehouseName} · {r.count} فقرة بعد التعديل</small></span><AppIcon name="chevron" size={15}/></button>)}</div>:<div className="warehousePricingForm"><h4>تسعير وصل #{detail.receiptNo} · {detail.party}</h4>{detail.stale&&<p className="workflowError">تغيّرت الفاتورة بعد طلب المواد. ألغِ الطلب ليُنشئ المخزن تعديلًا مطابقًا لآخر نسخة.</p>}<fieldset disabled={busy||detail.stale}>{detail.items.map((i,n)=><article key={i.lineId??'new-'+i.productId}><div><small>{n+1} · {i.lineId==null?'مادة جديدة':'فقرة مسجّلة'}</small><b dir="auto">{i.name}</b><span>العدد: {money(i.qty)}</span></div><label>سعر بيع الوحدة د.ع{i.lineId==null?<MoneyInput aria-label={'سعر المادة الجديدة '+i.name} value={prices[i.productId]??''} onChange={v=>setPrices(p=>({...p,[i.productId]:v}))}/>:<bdi>{money(i.price)} د.ع</bdi>}</label></article>)}</fieldset><div className="warehousePricingTotal"><span>مبلغ الفاتورة بعد اعتماد الأسعار</span><bdi>{money(total)} د.ع</bdi></div><div className="warehouseActions"><button type="button" disabled={busy||detail.stale} onClick={()=>submit('approve')}>{busy?'جاري التأكيد…':'اعتماد الأسعار وتحديث الوصل'}</button><button type="button" disabled={busy} onClick={()=>submit('cancel')}>إلغاء تعديل المواد</button><button type="button" disabled={busy} onClick={()=>{setDetail(null);setError('');}}>رجوع</button></div></div>}
 </section>;
}
