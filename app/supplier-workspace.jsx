'use client';
import {useRef,useState} from 'react';
import {supabase} from './supabase';
import PartySearch from './party-search';
import {receiptNumber,money,moneyInput,supplierLedger,supplierLabel,supplierDocument,escapeHtml,matchesReceipt} from './supplier-utils.mjs';

function ReceiptActions({row,a4,openA4,saveA4,shareA4}){
 const doc=()=>{const d=supplierDocument(row);return a4(d.title,d.body,d.total,d.subtitle)};
 return <div className="compactActions"><button type="button" onClick={()=>openA4(doc())}>معاينة الوصل</button><button type="button" onClick={()=>saveA4(doc(),'وصل-مورد-'+receiptNumber(row))}>حفظ PDF</button><button type="button" onClick={()=>shareA4('وصل-مورد-'+receiptNumber(row),'المورد: '+row.party+'\nرقم الوصل: '+receiptNumber(row)+'\nالمبلغ: '+money(row.total)+' د.ع',doc())}>مشاركة</button></div>;
}

export function SupplierPayment({suppliers,tx,balance,onChanged,initial=null,initialParty='',onCancel,...documents}){
 const [party,setParty]=useState(initial?.party||initialParty),[amount,setAmount]=useState(initial?String(initial.total):''),[note,setNote]=useState(initial?.notes||'');
 const [saving,setSaving]=useState(false),[error,setError]=useState(''),[last,setLast]=useState(null);
 const pending=useRef(null);
 const supplier=suppliers.find(s=>s.name===party),ledger=supplierLedger(tx,supplier);
 const valid=!!supplier&&Number.isFinite(Number(amount))&&Number(amount)>0;
 const draft={draft:true,id:initial?.id,receiptNo:initial?.receiptNo,kind:'supplier_payment',party,total:Number(amount),notes:note,date:initial?.date||new Date().toISOString()};
 async function save(e){
  e.preventDefault();if(saving||pending.current?.busy)return;
  if(!valid){setError('اختر المورد وأدخل مبلغاً صحيحاً أكبر من صفر.');return;}
  const args={payment_id:initial?.id||pending.current?.id||Date.now(),supplier_id:supplier.id,amount:Number(amount),note,expected_token:initial?.token||null};
  const signature=JSON.stringify(args);
  if(pending.current&&pending.current.signature!==signature){setError('هناك محاولة حفظ لم يتأكد ردّها. أعد المحاولة بنفس البيانات أولاً.');return;}
  if(!pending.current)pending.current={id:args.payment_id,requestId:crypto.randomUUID(),signature};
  pending.current.busy=true;setSaving(true);setError('');
  let saved=false;
  try{
   const {data,error}=await supabase.rpc('solar_supplier_payment_save',{...args,request_id:pending.current.requestId});
   if(error)throw error;
   setLast({...data,kind:'supplier_payment'});saved=true;pending.current=null;
   try{await onChanged?.()}catch{setError('تم حفظ التسديد. تعذر تحديث الأرصدة، حدّث الصفحة لعرضها.');}
  }catch(e){
   if(e.code){pending.current=null;setError(e.code==='P0002'?'رصيد قاصة صاحب التسديد غير كافٍ.':e.code==='42501'?'ليس لديك صلاحية تسديد المورد أو تعديل هذا الوصل.':e.code==='40001'?'تغيّر الوصل. أغلق التعديل وافتحه مجدداً.':'تعذر حفظ التسديد. '+(e.message||''));}
   else setError('تعذر تأكيد الحفظ. أعد المحاولة بنفس البيانات؛ لن يتكرر التسديد.');
  }finally{if(pending.current)pending.current.busy=false;setSaving(false);if(saved){setAmount('');setNote('');}}
 }
 if(last)return <section className="card supplierSaved"><div className="workflowSuccess" role="status">تم {initial?'تعديل':'حفظ'} التسديد #{receiptNumber(last)}</div><h3>{last.party}</h3><strong className="receiptAmount">{money(last.total)} د.ع</strong><ReceiptActions row={last} {...documents}/><button onClick={()=>{if(initial)onCancel?.();else{setLast(null);setError('')}}}>{initial?'رجوع للكشف':'تسديد جديد'}</button>{error&&<p role="alert">{error}</p>}</section>;
 return <form className="card form supplierPaymentForm" onSubmit={save}>
  <h3>{initial?'تعديل وصل #'+receiptNumber(initial):'تسديد مورد'}</h3>
  <fieldset disabled={saving||!!pending.current}>
   <label>المورد<PartySearch rows={suppliers} value={party} onChange={setParty} placeholder="ابحث عن المورد بالاسم أو الهاتف…"/></label>
   {!initial&&supplier&&<div className="financeTiles"><div className="financeBlue"><small>حساب المورد ضمن صلاحياتك</small><b>{money(ledger.balance)} د.ع</b></div><div className="financeGreen"><small>المتوفر في قاصتي</small><b>{money(balance)} د.ع</b></div></div>}
   <label>مبلغ التسديد<input inputMode="decimal" value={amount===''?'':Number.isFinite(Number(amount))?money(amount):amount} onChange={e=>setAmount(moneyInput(e.target.value))} placeholder="1,000"/></label>
   <label>الملاحظات <small>اختياري</small><textarea value={note} maxLength={2000} onChange={e=>setNote(e.target.value)} placeholder="ملاحظات التسديد"/></label>
  </fieldset>
  {error&&<div className="workflowError" role="alert">{error}</div>}
  {valid&&!pending.current&&<ReceiptActions row={draft} {...documents}/>}
  <button disabled={saving}>{saving?'جاري الحفظ…':pending.current?'إعادة تأكيد الحفظ':initial?'حفظ التعديل':'حفظ التسديد وخصمه من قاصتي'}</button>
  {onCancel&&<button type="button" className="secondary" disabled={saving} onClick={onCancel}>رجوع للكشف</button>}
 </form>;
}

export function SupplierStatement({suppliers,tx,canPay,canEditPurchase,onChanged,renderPurchaseEditor,...documents}){
 const [party,setParty]=useState(''),[from,setFrom]=useState(''),[to,setTo]=useState(''),[view,setView]=useState('all'),[query,setQuery]=useState('');
 const [editing,setEditing]=useState(null),[error,setError]=useState(''),[loading,setLoading]=useState(null);
 const supplier=suppliers.find(s=>s.name===party),ledger=supplierLedger(tx,supplier,from,to);
 const rows=ledger.rows.filter(t=>(view==='all'||(view==='payments'?t.kind==='supplier_payment':t.kind==='purchase'))&&matchesReceipt(t,query));
 const purchases=ledger.rows.filter(t=>t.kind==='purchase').reduce((s,t)=>s+Number(t.total),0),payments=ledger.rows.reduce((s,t)=>s+(t.kind==='supplier_payment'||t.cash?Number(t.total):0),0);
 async function edit(t){setError('');if(t.kind==='purchase'){setEditing(t);return;}setLoading(t.id);try{const {data,error}=await supabase.rpc('solar_supplier_payment_get',{payment_id:t.id});if(error)throw error;setEditing({...data,kind:'supplier_payment'});}catch{setError('تعذر فتح التسديد. حدّث البيانات وحاول مجدداً.');}finally{setLoading(null);}}
 function statementHtml(){const e=escapeHtml;return documents.a4('كشف حساب مورد','<div class="meta"><div>المورد: '+e(party)+'</div><div>الفترة: '+e(from||'البداية')+' — '+e(to||'اليوم')+'</div><div>الرصيد الافتتاحي: '+money(ledger.opening)+' د.ع</div><div>الرصيد بنهاية الفترة: '+money(ledger.balance)+' د.ع</div></div><table><thead><tr><th>التاريخ / الوصل</th><th>البيان</th><th>المبلغ د.ع</th><th>الرصيد د.ع</th></tr></thead><tbody>'+rows.map(t=>'<tr><td>'+e(new Date(t.date).toLocaleDateString('ar-IQ',{timeZone:'Asia/Baghdad'}))+'<br>#'+e(receiptNumber(t))+'</td><td>'+supplierLabel(t)+(t.notes?'<br>'+e(t.notes):'')+'</td><td>'+money(t.total)+'</td><td>'+money(t.balance)+'</td></tr>').join('')+'</tbody></table>',money(ledger.balance)+' د.ع','الحركات ضمن صلاحياتك • الرصيد يشمل جميع حركات الفترة');}
 if(editing)return <div className="supplierEdit"><button onClick={()=>setEditing(null)}>← رجوع لكشف المورد</button>{editing.kind==='supplier_payment'?<SupplierPayment key={editing.id} suppliers={suppliers} tx={tx} initial={editing} onChanged={onChanged} onCancel={()=>setEditing(null)} {...documents}/>:renderPurchaseEditor(editing,()=>setEditing(null))}</div>;
 return <section className="supplierStatement">{supplier&&<div className="compactActions"><button onClick={()=>documents.openA4(statementHtml())}>معاينة الكشف</button><button onClick={()=>documents.saveA4(statementHtml(),'كشف-مورد-'+party)}>حفظ PDF</button><button onClick={()=>documents.shareA4('كشف-مورد-'+party,'كشف حساب '+party+'\nالرصيد: '+money(ledger.balance)+' د.ع',statementHtml())}>مشاركة الكشف</button></div>}
  <div className="card form"><PartySearch rows={suppliers} value={party} onChange={setParty} placeholder="ابحث عن المورد بالاسم أو الهاتف…"/>
   <div className="dateRange"><label>من<input type="date" value={from} max={to||undefined} onChange={e=>setFrom(e.target.value)}/></label><label>إلى<input type="date" value={to} min={from||undefined} onChange={e=>setTo(e.target.value)}/></label></div>
   <input value={query} onChange={e=>setQuery(e.target.value)} placeholder="ابحث برقم الوصل…" aria-label="بحث برقم الوصل"/>
   <div className="statementTabs">{[['all','الكشف الرئيسي'],['invoices','المشتريات'],['payments','التسديدات']].map(([v,label])=><button key={v} type="button" className={view===v?'active':''} onClick={()=>setView(v)}>{label}</button>)}</div>
  </div>
  {error&&<div className="workflowError" role="alert">{error}</div>}
  {supplier&&<><div className="financeTiles"><div className="financeBlue"><small>مشتريات الفترة</small><b>{money(purchases)} د.ع</b></div><div className="financeRed"><small>المدفوع للمورد بالفترة</small><b>{money(payments)} د.ع</b></div><div className="financeTeal"><small>الرصيد الافتتاحي</small><b>{money(ledger.opening)} د.ع</b></div><div className="financeGreen"><small>الرصيد بنهاية الفترة</small><b>{money(ledger.balance)} د.ع</b></div></div>

   <p className="mutedNote">الحركات ضمن صلاحياتك. الرصيد يشمل جميع حركات الفترة حتى عند تصفية النتائج.</p>
   {!rows.length?<div className="empty">لا توجد حركات مطابقة</div>:rows.map(t=><article className="card supplierMovement" key={t.id}><header><b>{supplierLabel(t)}</b><small>{new Date(t.date).toLocaleDateString('ar-IQ',{timeZone:'Asia/Baghdad'})}</small></header><span className="receiptNumber">رقم الوصل: <bdi>#{receiptNumber(t)}</bdi></span><div className="movementAmounts"><div><small>المبلغ</small><b className={t.kind==='supplier_payment'?'amountRed':'amountBlue'}>{money(t.total)} د.ع</b></div><div><small>الرصيد بعد الحركة</small><b>{money(t.balance)} د.ع</b></div></div>{t.notes&&<p>{t.notes}</p>}<ReceiptActions row={t} {...documents}/>{(t.kind==='supplier_payment'?canPay:canEditPurchase)&&<button className="editMovement" disabled={loading!==null} onClick={()=>edit(t)}>{loading===t.id?'جاري الفتح…':'تعديل الحركة'}</button>}</article>)}
  </>}
 </section>;
}
