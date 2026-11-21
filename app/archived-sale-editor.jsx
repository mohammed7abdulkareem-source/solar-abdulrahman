'use client';
import {useEffect,useState} from 'react';
import CurrencyInvoice from './currency-invoice';
import SystemInvoiceEditor from './system-invoice-editor';
import {archiveInvoiceDraft,canEditArchivedInvoice,canEditInstallationExpenses} from './invoice-edit-utils.mjs';
import {salesAuthorizationKey} from './sales-read-scope.mjs';
import {supabase} from './supabase';

export function ArchivedSaleEditor({original,profile,customers,staff,products,onUpdateInvoice,onSaved,onCancel,a4,openA4,saveA4,shareA4}){
 const [items,setItems]=useState([]),[search,setSearch]=useState('');
 if(original.kind==='system')return <SystemInvoiceEditor profile={profile} original={original} canEditExpenses={canEditInstallationExpenses(profile,original)} customers={customers} staff={staff} products={products} onUpdate={onUpdateInvoice} onSaved={onSaved} onCancel={onCancel} a4={a4}/>;
 return <CurrencyInvoice kind="sale" contact={{...profile,display_name:original.creatorName,phone:original.creatorPhone}} products={products} parties={customers} initialInvoice={original} items={items} setItems={setItems} search={search} setSearch={setSearch} onUpdateInvoice={onUpdateInvoice} onEditSaved={onSaved} onCancel={onCancel} a4={a4} openA4={openA4} saveA4={saveA4} shareA4={shareA4}/>;
}

export function StatementSaleEditor({movementId,customerId,profile,onCancel,...editorProps}){
 const [request,setRequest]=useState(0),[result,setResult]=useState(null);
 const scope=JSON.stringify([salesAuthorizationKey(profile),customerId,movementId,request]);
 useEffect(()=>{
  let current=true;
  async function load(){
   try{
    const {data,error}=await supabase.rpc('solar_statement_sale_for_edit',{customer_id:customerId,movement_id:movementId});
    if(error)throw error;
    if(!data||String(data.id)!==String(movementId)||String(data.party_id)!==String(customerId)||!canEditArchivedInvoice(profile,data))throw new Error('هذا الوصل غير متاح للتعديل ضمن صلاحياتك.');
    if(current)setResult({scope,original:{...archiveInvoiceDraft(data),currentCustomerName:data.party_name}});
   }catch(error){if(current)setResult({scope,error:error.code==='42501'?'هذا الوصل غير متاح للتعديل ضمن صلاحياتك.':error.message||'تعذّر تحميل الوصل.'});}
  }
  void load();return()=>{current=false;};
 },[scope]);
 if(result?.scope===scope&&result.original)return <ArchivedSaleEditor key={scope} original={result.original} profile={profile} onCancel={onCancel} {...editorProps}/>;
 const error=result?.scope===scope&&result.error;
 return <section className="panel"><h2>تعديل فاتورة البيع</h2>{error?<><p role="alert">{error}</p><button type="button" onClick={()=>setRequest(n=>n+1)}>إعادة المحاولة</button></>:<p role="status">جارٍ تحميل الفاتورة…</p>} <button type="button" onClick={onCancel}>رجوع إلى كشف الحساب</button></section>;
}
