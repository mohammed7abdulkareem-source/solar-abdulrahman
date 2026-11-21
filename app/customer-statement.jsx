'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import AppIcon from './app-icons';
import CustomerPicker from './customer-picker';
import CustomerAccountView from './customer-account-view';
import {customerAccount} from './compact-party-utils.mjs';
import {MatchAccount} from './reconciliation-workspace';
import {canOpenPage} from './access-utils.mjs';
import {groupBalances,ownerKey} from './party-balances-utils.mjs';
export default function CustomerStatement({profile,canReconcile,onChanged,a4,initialId='',onPayment,onSale,renderSaleEditor,onDeleteInvoice}){
 const [directory,setDirectory]=useState([]),[directoryLoading,setDirectoryLoading]=useState(true),[directoryError,setDirectoryError]=useState(''),[ownerId,setOwnerId]=useState('all'),[category,setCategory]=useState('all'),[filtersOpen,setFiltersOpen]=useState(false);
 const [id,setId]=useState(String(initialId)),[ledger,setLedger]=useState(null),[error,setError]=useState(''),[loading,setLoading]=useState(false);const generation=useRef(0),directoryGeneration=useRef(0);
 const loadDirectory=useCallback(async()=>{
  const turn=++directoryGeneration.current;
  setDirectoryLoading(true);setDirectoryError('');
  try{
   const {data,error}=await supabase.rpc('solar_statement_customers');
   if(error)throw error;
   if(turn===directoryGeneration.current){
    const rows=data||[];
    setDirectory(rows);
    setOwnerId(current=>current==='all'||rows.some(c=>ownerKey(c.owner_id)===current)?current:'all');
   }
  }catch(e){if(turn===directoryGeneration.current)setDirectoryError(e.message||'تعذر تحميل العملاء.');}
  finally{if(turn===directoryGeneration.current)setDirectoryLoading(false);}
 },[]);
 useEffect(()=>{loadDirectory();return()=>{directoryGeneration.current++;};},[loadDirectory]);
 const load=useCallback(async()=>{
  const turn=++generation.current;
  if(!id){setLedger(null);setLoading(false);return;}
  setLoading(true);setError('');
  try{
   const {data,error}=await supabase.rpc('solar_customer_statement',{customer_id:Number(id)});
   if(error)throw error;
   if(turn===generation.current)setLedger(data);
  }catch(e){
   if(turn!==generation.current)return;
   if(e.code)setLedger(null);
   if(e.code==='42501'){
    setId('');setDirectory(rows=>rows.filter(row=>String(row.id)!==String(id)));
    void loadDirectory();
   }
   setError(e.message||'تعذر تحميل الكشف.');
  }finally{if(turn===generation.current)setLoading(false);}
 },[id,loadDirectory]);
 useEffect(()=>{load();return()=>{generation.current++;};},[load]);
 const candidates=directory.filter(c=>(ownerId==='all'||ownerKey(c.owner_id)===ownerId)&&(category==='all'||c.customer_type===category)),owners=groupBalances(directory.map(c=>({...c,balance:0})));
 const changed=async()=>{await Promise.all([load(),loadDirectory(),onChanged?.()]);};
 if(ledger&&String(ledger.id)===String(id)){
  const account=customerAccount(ledger),wholesale=account.customerType==='wholesale';
  return <>{error&&<p role="alert" className="miniAlert">{error} <button type="button" onClick={load}>تحديث الكشف</button></p>}<CustomerAccountView key={ledger.id} profile={profile} account={account} balanceStatus={loading?'loading':error?'error':'ready'} a4={a4}
   backLabel="رجوع إلى اختيار العميل" onBack={()=>{setId('');setLedger(null);}} onRefresh={load} onAccountChanged={changed}
   renderSaleEditor={renderSaleEditor} onDeleteInvoice={onDeleteInvoice}
   onPayment={onPayment&&canOpenPage(profile,wholesale?'customerPayment':'systemPayment')?()=>onPayment(account):undefined}
   onSale={onSale&&canOpenPage(profile,wholesale?'sale':'system')?()=>onSale(account):undefined}
   renderMatch={canReconcile?()=> <MatchAccount standalone customerId={Number(id)} ledger={ledger} onSaved={changed}/>:undefined}/></>;
 }
 return <section className="miniParty miniChoose"><header className="miniPageHead"><h1>كشف حساب عميل</h1><button type="button" className="miniIcon" aria-label="تصفية عملاء الكشف" aria-expanded={filtersOpen} onClick={()=>setFiltersOpen(v=>!v)}><AppIcon name="filter" size={18}/></button><button type="button" className="miniIcon" aria-label="تحديث العملاء" disabled={directoryLoading||loading} onClick={()=>{loadDirectory();load();}}><AppIcon name="refresh" size={18}/></button></header>
 {filtersOpen&&<div className="miniDirectoryFilters">{profile.is_admin&&<label>المستخدم<select aria-label="مستخدم دليل الكشف" value={ownerId} onChange={e=>{setOwnerId(e.target.value);setId('');}}><option value="all">جميع المستخدمين</option>{owners.map(o=><option key={o.id} value={o.id}>{o.name}</option>)}</select></label>}<label>نوع العميل<select aria-label="نوع عميل الكشف" value={category} onChange={e=>{setCategory(e.target.value);setId('');}}><option value="all">الكل</option><option value="wholesale">جملة</option><option value="system">مفرد</option></select></label></div>}
 <CustomerPicker rows={candidates} value={id} onChange={value=>{setId(value);setLedger(null);}} loading={directoryLoading}/>
 {directoryError&&<p className="miniAlert" role="alert">{directoryError}<button type="button" onClick={loadDirectory}>إعادة المحاولة</button></p>}{error&&<p className="miniAlert" role="alert">{error}<button type="button" onClick={id?load:()=>{setError('');loadDirectory();}}>إعادة المحاولة</button></p>}
 <p className="miniEmpty" role="status">{loading?'جاري تحميل الحساب…':'ابحث بالاسم أو الهاتف، ثم اختر العميل.'}</p>
 </section>;
}
