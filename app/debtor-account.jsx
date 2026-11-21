'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import {canOpenPage} from './access-utils.mjs';
import CustomerAccountView from './customer-account-view';
import {customerAccount} from './compact-party-utils.mjs';
import {CustomerAccountMatch} from './reconciliation-workspace';

export default function DebtorAccount({id,profile,a4,onBack,onPayment,onSale,onChanged,renderSaleEditor,onDeleteInvoice}){
 const [record,setRecord]=useState(null),[error,setError]=useState(''),[loading,setLoading]=useState(true);
 const generation=useRef(0);
 const directoryAccess=canOpenPage(profile,'customers')||canOpenPage(profile,'customerCreate');
 const load=useCallback(async()=>{
  const turn=++generation.current;
  setLoading(true);setError('');
  try{
   const {data,error}=await supabase.rpc(directoryAccess?'solar_customer_get':'solar_customer_statement',{customer_id:Number(id)});
   if(error)throw error;
   if(String(data?.id)!==String(id))throw new Error('تعذر تحميل حساب العميل المحدد.');
   if(turn===generation.current)setRecord(data);
  }catch(err){
   if(turn===generation.current){if(err.code)setRecord(null);setError(err.code==='42501'?'لا تملك صلاحية كشف حساب هذا الزبون.':err.message||'تعذر تحميل الحساب. أعد المحاولة.');}
  }finally{if(turn===generation.current)setLoading(false);}
 },[directoryAccess,id]);
 useEffect(()=>{load();return()=>{generation.current++;};},[load]);
 async function changed(){await Promise.all([load(),onChanged?.()]);}
 if(!record||String(record.id)!==String(id))return <section className="miniParty"><button type="button" className="uiButton" onClick={onBack}>رجوع إلى مدينون العملاء</button>{error?<div role="alert" className="accountAlert error">{error}<button type="button" className="uiButton" onClick={load}>إعادة المحاولة</button></div>:<p role="status">جاري تحميل كشف حساب العميل…</p>}</section>;
 const account=customerAccount(record),wholesale=account.customerType==='wholesale';
 return <>{error&&<p role="alert" className="miniAlert">{error} <button type="button" onClick={load}>تحديث الكشف</button></p>}<CustomerAccountView profile={profile} account={account} a4={a4} balanceStatus={loading?'loading':error?'error':'ready'}
  onBack={onBack} backLabel="رجوع إلى مدينون العملاء" onRefresh={load} onAccountChanged={changed}
  renderSaleEditor={renderSaleEditor} onDeleteInvoice={onDeleteInvoice}
  onPayment={onPayment&&canOpenPage(profile,wholesale?'customerPayment':'systemPayment')?()=>onPayment(record):undefined}
  onSale={onSale&&canOpenPage(profile,wholesale?'sale':'system')?()=>onSale(record):undefined}
  renderMatch={canOpenPage(profile,'customerReconcile')?()=> <CustomerAccountMatch customerId={id} onSaved={changed}/>:undefined}/></>;
}
