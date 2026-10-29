'use client';
import {useEffect,useState} from 'react';
import {supabase} from './supabase';
import {canOpenPage} from './access-utils.mjs';
import CompactPartyAccount from './compact-party-account';
import {customerAccount} from './compact-party-utils.mjs';
import {CustomerAccountMatch} from './reconciliation-workspace';

export default function DebtorAccount({id,profile,a4,onBack,onPayment,onSale,onChanged}){
 const [record,setRecord]=useState(null),[error,setError]=useState(''),[refresh,setRefresh]=useState(0),[loading,setLoading]=useState(true);
 const directoryAccess=canOpenPage(profile,'customers')||canOpenPage(profile,'customerCreate');
 useEffect(()=>{let live=true;setLoading(true);setError('');setRecord(null);
  supabase.rpc(directoryAccess?'solar_customer_get':'solar_customer_statement',{customer_id:Number(id)}).then(({data,error})=>{if(!live)return;if(error)throw error;setRecord(data);}).catch(err=>{if(live)setError(err.code==='42501'?'لا تملك صلاحية كشف حساب هذا الزبون.':err.message||'تعذر تحميل الحساب. أعد المحاولة.');}).finally(()=>{if(live)setLoading(false);});
  return()=>{live=false;};
 },[id,directoryAccess,refresh]);
 if(loading||error||!record)return <section className="miniParty"><button type="button" className="uiButton" onClick={onBack}>رجوع إلى مدينون العملاء</button>{error?<div role="alert" className="accountAlert error">{error}<button type="button" className="uiButton" onClick={()=>setRefresh(n=>n+1)}>إعادة المحاولة</button></div>:<p role="status">جاري تحميل كشف حساب العميل…</p>}</section>;
 const account=customerAccount(record),wholesale=account.customerType==='wholesale';
 return <CompactPartyAccount account={account} a4={a4} onBack={onBack} backLabel="رجوع إلى مدينون العملاء" onRefresh={()=>setRefresh(n=>n+1)} onPayment={onPayment&&canOpenPage(profile,wholesale?'customerPayment':'systemPayment')?()=>onPayment(record):undefined} onSale={onSale&&canOpenPage(profile,wholesale?'sale':'system')?()=>onSale(record):undefined} renderMatch={canOpenPage(profile,'customerReconcile')?()=> <CustomerAccountMatch customerId={id} onSaved={()=>{setRefresh(n=>n+1);onChanged?.();}}/>:undefined}/>;
}
