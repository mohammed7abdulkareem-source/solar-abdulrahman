'use client';
import {useEffect,useState} from 'react';
import PartySearch from './party-search';
import AppIcon from './app-icons';
import SupplierPaymentHistory from './supplier-payment-history';
import CompactPartyAccount from './compact-party-account';
import {supplierAccount} from './compact-party-utils.mjs';
import {fxRead} from './fx-store.mjs';
export {default as SupplierPayment} from './supplier-payment';
export function SupplierStatement({initialParty='',suppliers,tx=[],canPay,canEditPurchase,canEditRate,onChanged,renderPurchaseEditor,onBack,onEditSupplier,onPayment,onPurchase,onCurrency,...documents}){
 const [party,setParty]=useState(initialParty),[revision,setRevision]=useState('current'),[data,setData]=useState(null),[refresh,setRefresh]=useState(0),[editing,setEditing]=useState(null),[error,setError]=useState(''),[loading,setLoading]=useState(false);
 const supplier=suppliers.find(s=>s.name===party);
 useEffect(()=>{let live=true;setData(null);setError('');if(!supplier){setLoading(false);return()=>{live=false;};}setLoading(true);fxRead('statement',{supplierId:supplier.id}).then(d=>live&&setData(d)).catch(err=>live&&setError(err.message)).finally(()=>live&&setLoading(false));return()=>{live=false;};},[supplier?.id,refresh]);
 const changed=async()=>{setRefresh(n=>n+1);await onChanged?.();};
 if(editing)return <div className="miniParty miniEmbedded">{editing.kind!=='supplier_payment'&&<button type="button" className="miniBackLink" onClick={()=>{setEditing(null);setRefresh(n=>n+1);}}>رجوع لحساب المورد</button>}{editing.kind==='supplier_payment'?<SupplierPaymentHistory key={editing.id} initialId={editing.id} initialAction={editing.operation} initialQuery={party} canEditRate={canEditRate} onChanged={changed} onBack={()=>{setEditing(null);setRefresh(n=>n+1);}} a4={documents.a4}/>:renderPurchaseEditor?.(editing,()=>{setEditing(null);setRefresh(n=>n+1);})}</div>;
 if(!supplier)return <section className="miniParty miniChoose"><header className="miniPageHead"><h1>حساب المورد</h1></header><PartySearch rows={suppliers} value={party} onChange={v=>{setParty(v);setRevision('current');}} placeholder="ابحث عن المورد بالاسم أو الهاتف…"/><p className="miniEmpty">اختر المورد لعرض حسابه.</p></section>;
 if(!data||loading)return <section className="miniParty"><header className="miniPageHead"><button type="button" className="miniIcon" aria-label="رجوع للموردين" onClick={()=>onBack?onBack():setParty('')}><AppIcon name="arrow" size={18}/></button><h1>{supplier.name}</h1></header>{error?<p className="miniAlert" role="alert">{error}<button type="button" onClick={()=>setRefresh(n=>n+1)}>إعادة المحاولة</button></p>:<p className="miniEmpty" role="status">جاري تحميل الحساب…</p>}</section>;
 const selectedRevision=revision==='current'?data.revision:Number(revision),account={...supplierAccount(data,party,tx,selectedRevision),id:supplier.id};
 const revisions=[...new Set(data.rows.map(r=>r.revision))];
 return <CompactPartyAccount key={supplier.id+':'+selectedRevision+':'+refresh} account={account} a4={documents.a4} onBack={()=>onBack?onBack():setParty('')} onRefresh={()=>setRefresh(n=>n+1)} onEdit={onEditSupplier?()=>onEditSupplier(supplier):undefined} onPayment={canPay&&onPayment?()=>onPayment(supplier):undefined} onSale={canEditPurchase&&onPurchase?()=>onPurchase(supplier):undefined} onSettings={onCurrency?()=>onCurrency(supplier):undefined} canEditMovement={r=>!!r.original&&!r.voided&&(r.kind==='supplier_payment'?canPay:r.kind==='purchase'&&canEditPurchase)} onMovementEdit={(r,operation)=>setEditing({...r.original,operation})} extraControls={revisions.length>1?<label className="miniRevision">سجل العملة<select aria-label="سجل عملة حساب المورد" value={revision} onChange={e=>setRevision(e.target.value)}><option value="current">الحساب الحالي · {data.currency}</option>{revisions.filter(v=>v!==data.revision).map(v=><option key={v} value={v}>سجل سابق {v} · {data.rows.find(r=>r.revision===v).currency}</option>)}</select></label>:undefined}/>;
}
