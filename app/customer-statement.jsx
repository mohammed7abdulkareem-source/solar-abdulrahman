'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import AppIcon from './app-icons';
import CustomerPicker from './customer-picker';
import CompactPartyAccount from './compact-party-account';
import CustomerPaymentHistory from './customer-payment-history';
import {customerAccount} from './compact-party-utils.mjs';
import {MatchAccount} from './reconciliation-workspace';
import {canOpenPage,cashOwner} from './access-utils.mjs';
import {groupBalances,ownerKey} from './party-balances-utils.mjs';
export default function CustomerStatement({profile,canReconcile,onChanged,a4,initialId='',onPayment,onSale,transactions=[]}){
 const [directory,setDirectory]=useState([]),[directoryLoading,setDirectoryLoading]=useState(true),[directoryError,setDirectoryError]=useState(''),[ownerId,setOwnerId]=useState('all'),[category,setCategory]=useState('all'),[filtersOpen,setFiltersOpen]=useState(false);
 const [id,setId]=useState(String(initialId)),[ledger,setLedger]=useState(null),[error,setError]=useState(''),[loading,setLoading]=useState(false),[paymentEdit,setPaymentEdit]=useState(null);const generation=useRef(0);
 const loadDirectory=useCallback(async()=>{setDirectoryLoading(true);setDirectoryError('');try{const {data,error}=await supabase.rpc('solar_statement_customers');if(error)throw error;setDirectory(data||[]);}catch(e){setDirectoryError(e.message||'تعذر تحميل العملاء.');}finally{setDirectoryLoading(false);}},[]);
 useEffect(()=>{loadDirectory();},[loadDirectory]);
 const load=useCallback(async()=>{const n=++generation.current;setLedger(null);setError('');if(!id){setLoading(false);return;}setLoading(true);try{const {data,error}=await supabase.rpc('solar_customer_statement',{customer_id:Number(id)});if(n!==generation.current)return;if(error)throw error;setLedger(data);}catch(e){if(n===generation.current)setError(e.message||'تعذر تحميل الكشف.');}finally{if(n===generation.current)setLoading(false);}},[id]);
 useEffect(()=>{load();return()=>{generation.current++;};},[load]);
 const candidates=directory.filter(c=>(ownerId==='all'||ownerKey(c.owner_id)===ownerId)&&(category==='all'||c.customer_type===category)),owners=groupBalances(directory.map(c=>({...c,balance:0})));
 const changed=async()=>{await load();await onChanged?.();};
 if(paymentEdit)return <div className="miniParty miniEmbedded"><CustomerPaymentHistory initialId={paymentEdit.id} initialAction={paymentEdit.action} backLabel="رجوع لحساب العميل" onBack={()=>{setPaymentEdit(null);load();}} onChanged={changed}/></div>;
 if(ledger&&!loading){const account=customerAccount(ledger);return <CompactPartyAccount key={ledger.id+ledger.token} account={account} a4={a4} onBack={()=>{setId('');setLedger(null);}} onRefresh={load} onPayment={onPayment&&canOpenPage(profile,account.customerType==='wholesale'?'customerPayment':'systemPayment')?()=>onPayment(account):undefined} onSale={onSale&&canOpenPage(profile,account.customerType==='wholesale'?'sale':'system')?()=>onSale(account):undefined} onMovementEdit={(r,action)=>setPaymentEdit({id:r.id,action})} canEditMovement={r=>r.kind==='customer_payment'&&!['opening_balance','account_reconciliation'].includes(r.mode)&&canOpenPage(profile,'customerPayment')&&(profile.is_admin||transactions.some(t=>String(t.id)===String(r.id)&&cashOwner(t)===profile.id))} renderMatch={canReconcile?()=> <MatchAccount standalone customerId={Number(id)} ledger={ledger} onSaved={changed}/>:undefined}/>;}
 return <section className="miniParty miniChoose"><header className="miniPageHead"><h1>كشف حساب عميل</h1><button type="button" className="miniIcon" aria-label="تصفية عملاء الكشف" aria-expanded={filtersOpen} onClick={()=>setFiltersOpen(v=>!v)}><AppIcon name="filter" size={18}/></button><button type="button" className="miniIcon" aria-label="تحديث العملاء" disabled={directoryLoading||loading} onClick={()=>{loadDirectory();load();}}><AppIcon name="refresh" size={18}/></button></header>
 {filtersOpen&&<div className="miniDirectoryFilters">{profile.is_admin&&<label>المستخدم<select aria-label="مستخدم دليل الكشف" value={ownerId} onChange={e=>{setOwnerId(e.target.value);setId('');}}><option value="all">جميع المستخدمين</option>{owners.map(o=><option key={o.id} value={o.id}>{o.name}</option>)}</select></label>}<label>نوع العميل<select aria-label="نوع عميل الكشف" value={category} onChange={e=>{setCategory(e.target.value);setId('');}}><option value="all">الكل</option><option value="wholesale">جملة</option><option value="system">مفرد</option></select></label></div>}
 <CustomerPicker rows={candidates} value={id} onChange={value=>{setId(value);setLedger(null);}} loading={directoryLoading}/>
 {directoryError&&<p className="miniAlert" role="alert">{directoryError}<button type="button" onClick={loadDirectory}>إعادة المحاولة</button></p>}{error&&<p className="miniAlert" role="alert">{error}</p>}
 <p className="miniEmpty" role="status">{loading?'جاري تحميل الحساب…':'ابحث بالاسم أو الهاتف، ثم اختر العميل.'}</p>
 </section>;
}
