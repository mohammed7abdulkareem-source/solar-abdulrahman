'use client';
import {useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import {filteredStock,quantity,warehouseDate} from './warehouse-utils.mjs';
import {money} from './reconciliation-utils.mjs';
import MoneyInput from './money-input';

// Retain the request key for an exact retry after a lost network response.
export function useReconciliation(){
 const attempt=useRef(null);
 return async(action,payload)=>{const fingerprint=JSON.stringify({action,payload});if(attempt.current?.fingerprint!==fingerprint)attempt.current={fingerprint,id:crypto.randomUUID()};
  const {data,error}=await supabase.rpc('solar_reconcile',{action,payload,request_id:attempt.current.id});if(error)throw error;return data;
 };
}
export function OpeningBalanceFields(){
 const [enabled,setEnabled]=useState(false);
 const [amount,setAmount]=useState('');
 return <div className="openingFields"><label className="reconcileCheck"><input type="checkbox" name="hasOpening" checked={enabled} onChange={e=>setEnabled(e.target.checked)}/>رصيد افتتاحي إن وجد</label>{enabled&&<div className="reconcilePair"><label>مبلغ الرصيد الافتتاحي · د.ع<MoneyInput aria-label="مبلغ الرصيد الافتتاحي" name="openingAmount" value={amount} onChange={setAmount} required placeholder="مثال: 2,000,000"/></label><label>اتجاه الرصيد<select name="openingDirection"><option value="1">لنا على العميل</option><option value="-1">للعميل عندنا</option></select></label></div>}</div>;
}
export function StockReconciliation({products,onChanged,warehouseId}){
 const [query,setQuery]=useState(''),[selected,setSelected]=useState(null),[actual,setActual]=useState(''),[note,setNote]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[message,setMessage]=useState('');const reconcile=useReconciliation();
 const choose=id=>{setSelected(products.find(p=>String(p.id)===id)||null);setActual('');setError('');setMessage('')};
 async function submit(e){e.preventDefault();if(busy||!selected)return;setBusy(true);setError('');setMessage('');try{
  await reconcile('stock_balance',{warehouseId:Number(warehouseId),productId:selected.id,expected:Number(selected.qty),actual:Number(actual),note});
  setSelected(null);setActual('');setNote('');setMessage('تم حفظ تسوية الرصيد وإضافتها إلى حركة المواد.');
  try{await onChanged()}catch{setError('تم الحفظ؛ تعذر تحديث الشاشة. حدّث البيانات قبل أي تسوية جديدة.')}
 }catch(e){setError(e.message||'تعذر حفظ التسوية')}finally{setBusy(false)}}
 return <details className="reconcilePanel"><summary>تسوية رصيد المخزون <small>مطابقة الجرد الفعلي</small></summary><form onSubmit={submit} className="reconcileForm"><label>بحث المادة<input aria-label="بحث مادة التسوية" value={query} onChange={e=>setQuery(e.target.value)} placeholder="اسم، كود، براند أو صنف"/></label><label>المادة<select aria-label="مادة التسوية" value={selected?.id||''} onChange={e=>choose(e.target.value)} required disabled={busy}><option value="">اختر المادة</option>{products.filter(p=>p.id===selected?.id||filteredStock([p],query).length).map(p=><option key={p.id} value={p.id}>{p.code} • {p.name} • {p.brand}</option>)}</select></label>{selected&&<><div className="reconcilePair"><div className="reconcileNumber"><small>رصيد البرنامج عند الاختيار</small><b>{quantity(selected.qty)}</b></div><label>الكمية الفعلية بعد الجرد<input aria-label="الكمية الفعلية" type="number" inputMode="decimal" min="0" max="1000000000" step="0.001" value={actual} onChange={e=>setActual(e.target.value)} required disabled={busy}/></label></div>{actual!==''&&<p className="reconcileDifference">فرق التسوية: <b>{quantity(Number(actual)-Number(selected.qty))}</b> {Number(actual)>Number(selected.qty)?'زيادة':Number(actual)<Number(selected.qty)?'نقص':'الرصيد مطابق'}</p>}<label>سبب التسوية<textarea aria-label="سبب التسوية" value={note} onChange={e=>setNote(e.target.value)} required maxLength={2000} disabled={busy}/></label><button disabled={busy}>{busy?'جاري الحفظ…':'حفظ تسوية الرصيد'}</button><button type="button" disabled={busy} onClick={async()=>{try{await onChanged();setSelected(null);setActual('');setError('')}catch{setError('تعذر تحديث الرصيد')}}}>تحديث الأرصدة وإعادة الاختيار</button></>}{error&&<p role="alert" className="workflowError">{error}</p>}{message&&<p role="status" className="workflowSuccess">{message}</p>}</form></details>;
}
export function MatchAccount({customerId,ledger,onSaved,standalone=false}){
 const [amount,setAmount]=useState(''),[direction,setDirection]=useState('1'),[note,setNote]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');const reconcile=useReconciliation();
 async function submit(e){e.preventDefault();if(busy)return;setBusy(true);setError('');try{await reconcile('customer_balance',{customerId,token:ledger.token,actual:Number(amount)*Number(direction),note});setAmount('');setNote('');await onSaved()}catch(e){setError(e.message||'تعذر حفظ المطابقة')}finally{setBusy(false)}}
 const Container=standalone?'section':'details';
 return <Container className="reconcilePanel">{!standalone&&<summary>مطابقة حساب العميل <small>إن وجدت</small></summary>}<form className="reconcileForm" onSubmit={submit}><p>أدخل الرصيد المتفق عليه. يُسجّل الفرق كحركة «مطابقة حساب».</p><div className="reconcileNumber"><small>الرصيد الحالي الكامل</small><b>{money(ledger.balance)} د.ع</b></div><div className="reconcilePair"><label>الرصيد المتفق عليه · د.ع<MoneyInput aria-label="الرصيد المتفق عليه" required value={amount} onChange={setAmount} disabled={busy}/></label><label>اتجاه الرصيد<select aria-label="اتجاه رصيد المطابقة" value={direction} onChange={e=>setDirection(e.target.value)} disabled={busy}><option value="1">لنا على العميل</option><option value="-1">للعميل عندنا</option></select></label></div>{amount!==''&&<p>فرق المطابقة: <b>{money(Number(amount)*Number(direction)-Number(ledger.balance))} د.ع</b></p>}<label>ملاحظة المطابقة<textarea aria-label="ملاحظة المطابقة" required maxLength={2000} value={note} onChange={e=>setNote(e.target.value)} disabled={busy}/></label><button disabled={busy}>{busy?'جاري الحفظ…':'حفظ مطابقة الحساب'}</button>{error&&<p role="alert" className="workflowError">{error}</p>}</form></Container>;
}

export function CustomerAccountMatch({customerId,onSaved}){
 const [ledger,setLedger]=useState(null),[error,setError]=useState('');
 useEffect(()=>{let live=true;supabase.rpc('solar_customer_statement',{customer_id:Number(customerId)}).then(({data,error})=>{if(error)throw error;if(live)setLedger(data);}).catch(e=>live&&setError(e.message));return()=>{live=false;};},[customerId]);
 if(error)return <p role="alert" className="miniAlert">{error}</p>;
 if(!ledger)return <p role="status" className="miniEmpty">جاري تحميل رصيد المطابقة…</p>;
 return <MatchAccount standalone customerId={customerId} ledger={ledger} onSaved={onSaved}/>;
}
