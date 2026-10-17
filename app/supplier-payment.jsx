'use client';
import {useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import PartySearch from './party-search';
import MoneyInput from './money-input';
import ReportActions,{ReportIcon} from './report-actions';
import {receiptNumber,money,supplierDocument,supplierIsCharge} from './supplier-utils.mjs';
const reasons=[['charge_extra_expense','مصروف إضافي'],['charge_old_balance','حساب قديم'],['charge_other','إضافة أخرى']];
export default function SupplierPayment({suppliers,onChanged,initial=null,initialParty='',onCancel,a4}){
 const initialCharge=initial&&supplierIsCharge(initial);
 const [party,setParty]=useState(initial?.party||initialParty),[amount,setAmount]=useState(initial?String(Math.abs(initial.total)):''),[note,setNote]=useState(initial?.notes||''),[direction,setDirection]=useState(initialCharge?'charge':'cash'),[reason,setReason]=useState(initialCharge?initial.mode||'charge_other':'charge_extra_expense');
 const [saving,setSaving]=useState(false),[error,setError]=useState(''),[last,setLast]=useState(null),[account,setAccount]=useState(null),[loading,setLoading]=useState(false),[accountError,setAccountError]=useState(''),[refresh,setRefresh]=useState(0),[draftDate,setDraftDate]=useState(()=>initial?.date||new Date().toISOString());
 const pending=useRef(null),supplier=suppliers.find(s=>s.name===party),charge=direction==='charge';
 useEffect(()=>{let live=true;setAccount(null);setAccountError('');if(!supplier){setLoading(false);return()=>{live=false;};}setLoading(true);
  supabase.rpc('solar_supplier_account',{supplier_id:supplier.id,payment_id:initial?.id||null}).then(({data,error})=>{if(!live)return;if(error)throw error;setAccount(data);}).catch(e=>{if(live)setAccountError(e.message||'تعذر تحميل حساب المورد.');}).finally(()=>{if(live)setLoading(false);});
  return()=>{live=false;};
 },[supplier?.id,initial?.id,refresh]);
 const value=Number(amount),valid=!!supplier&&amount!==''&&Number.isFinite(value)&&value>0&&value<=1e12&&Math.abs(value*100-Math.round(value*100))<.0001&&(!charge||note.trim().length>0);
 const signed=charge?-value:value,oldAmount=initial&&String(initial.supplierId)===String(supplier?.id)?Number(initial.total):0;
 const projected=Number(account?.balance||0)+oldAmount-(Number.isFinite(signed)?signed:0),cashAfter=Number(account?.cashBalance||0)-(charge?0:(Number.isFinite(value)?value:0)-(initial?.cash!==false?Number(initial?.total||0):0));
 const draft={draft:true,id:initial?.id,receiptNo:initial?.receiptNo,kind:'supplier_payment',party,total:signed,cash:!charge,mode:charge?reason:'cash',notes:note,date:draftDate,beforeBalance:account?.balance,afterBalance:projected};
 const documentRow=last||draft,doc=supplierDocument(documentRow),html=a4(doc.title,doc.body,doc.total,doc.subtitle);
 async function save(event){
  event.preventDefault();if(saving||pending.current?.busy)return;if(!valid){setError(charge?'اختر المورد وأدخل مبلغًا صحيحًا وسبب الإضافة.':'اختر المورد وأدخل مبلغًا صحيحًا أكبر من صفر.');return;}
  const args={payment_id:initial?.id||pending.current?.id||Date.now(),supplier_id:supplier.id,amount:value,movement_mode:charge?reason:'cash',note,expected_token:initial?.token||null},signature=JSON.stringify(args);
  if(pending.current&&pending.current.signature!==signature){setError('أعد تأكيد محاولة الحفظ السابقة بنفس البيانات أولًا.');return;}
  if(!pending.current)pending.current={id:args.payment_id,requestId:crypto.randomUUID(),signature};pending.current.busy=true;setSaving(true);setError('');
  try{const {data,error}=await supabase.rpc('solar_supplier_movement_save',{...args,request_id:pending.current.requestId});if(error)throw error;pending.current=null;setLast({...data,kind:'supplier_payment'});setRefresh(n=>n+1);try{await onChanged?.();}catch{setError('تم حفظ الحركة. حدّث البيانات لإظهارها في بقية الأقسام.');}}
  catch(e){if(e.code){pending.current=null;setError(e.code==='P0002'?'المتوفر في قاصة صاحب الوصل لا يكفي للتسديد.':e.code==='40001'?'تغير الوصل؛ افتح التعديل مجددًا.':e.message||'تعذر حفظ الحركة.');}else setError('لم يتأكد رد الحفظ. أعد المحاولة بنفس البيانات؛ لن تتكرر الحركة.');}
  finally{if(pending.current)pending.current.busy=false;setSaving(false);}
 }
 function newMovement(){if(initial){onCancel?.();return;}setLast(null);setAmount('');setNote('');setError('');setDraftDate(new Date().toISOString());}
 return <section className="accountWorkspace supplierMovementWorkspace"><header className="accountHero"><span className="accountHeroIcon"><ReportIcon name="wallet"/></span><div><span className="accountEyebrow">حسابات الموردين</span><h1>{initial?'تعديل حركة المورد':'تسديد وإضافات المورد'}</h1><p>تسديد نقدي ينقص المستحق، أو إضافة غير نقدية تزيد حساب المورد.</p></div>{onCancel&&<button className="reportRefresh" onClick={onCancel}>رجوع للكشف</button>}</header>
  {last?<section className="supplierMovementSaved"><span className="supplierSavedCheck">✓</span><div role="status">تم {initial?'تعديل':'حفظ'} {supplierIsCharge(last)?'الإضافة على حساب المورد':'التسديد'} بنجاح</div><h2>{last.party}</h2><span>وصل #{receiptNumber(last)}</span><b>{money(Math.abs(last.total))} <small>د.ع</small></b><p>{supplierIsCharge(last)?'المبلغ أُضيف إلى حساب المورد دون خصم نقدي.':'المبلغ خُصم من القاصة وسجّل كتسديد للمورد.'}</p>{last.afterBalance!=null&&<div className="supplierSavedBalance">رصيد حساب المورد بعد الحفظ <strong>{money(last.afterBalance)} د.ع</strong></div>}<ReportActions enabled html={html} filename={doc.title+'-'+receiptNumber(last)}/><button className="reportButton download" onClick={newMovement}>{initial?'رجوع للكشف':'حركة جديدة'}</button></section>:
  <form className="supplierMovementForm" onSubmit={save}><div className="accountFilterPanel"><div className="accountFilterTitle"><div><h2>{initial?'تعديل الوصل #'+receiptNumber(initial):'سجّل حركة على حساب المورد'}</h2><p>اختر نوع الحركة قبل إدخال المبلغ.</p></div></div><fieldset disabled={saving||!!pending.current}>
   <div className="supplierDirection" role="group" aria-label="اتجاه حركة المورد"><button type="button" disabled={!!initial} className={!charge?'active cash':''} aria-pressed={!charge} onClick={()=>{setDirection('cash');setError('');}}><ReportIcon name="download"/><span><b>تسديد للمورد</b><small>ينقص الدين ويخصم من القاصة</small></span></button><button type="button" disabled={!!initial} className={charge?'active charge':''} aria-pressed={charge} onClick={()=>{setDirection('charge');setError('');}}><ReportIcon name="document"/><span><b>إضافة على حساب المورد</b><small>تزيد المستحق له بدون خصم نقدي</small></span></button></div>
   <label>المورد<PartySearch rows={suppliers} value={party} onChange={v=>{setParty(v);setError('');}} placeholder="ابحث عن المورد بالاسم أو الهاتف…"/></label>
   {account&&<div className="supplierCurrentBalances"><div><span>رصيد المورد الحالي ضمن صلاحياتك</span><b>{money(account.balance)} <small>د.ع</small></b></div><div><span>المتوفر في قاصة {account.cashOwnerName||'صاحب الوصل'}</span><b>{money(account.cashBalance)} <small>د.ع</small></b></div></div>}
   {loading&&<p role="status" className="accountFootnote">جاري تحميل الرصيد الحالي…</p>}{accountError&&<div className="accountAlert error" role="alert">{accountError}<button type="button" onClick={()=>setRefresh(n=>n+1)}>إعادة تحميل الرصيد</button></div>}
   <div className="supplierAmountFields"><label>{charge?'المبلغ المضاف على الحساب':'مبلغ التسديد'} · د.ع<MoneyInput aria-label="مبلغ حركة المورد" value={amount} onChange={setAmount} placeholder="مثال: 1,000,000" required/></label>{charge&&<label>سبب الإضافة<select aria-label="سبب إضافة حساب المورد" value={reason} onChange={e=>setReason(e.target.value)}>{reasons.map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></label>}</div>
   <label>{charge?'تفاصيل الإضافة · مطلوبة':'ملاحظات التسديد · اختيارية'}<textarea aria-label="ملاحظات حركة المورد" required={charge} value={note} onChange={e=>setNote(e.target.value)} maxLength={2000} placeholder={charge?'اكتب تفاصيل المصروف أو الحساب القديم…':'اكتب ملاحظة إن وجدت…'}/></label>
   {account&&amount!==''&&<div className={'supplierProjection '+(charge?'charge':'cash')}><div><span>أثر الحركة على حساب المورد</span><b>{charge?'+':'−'} {money(value)} د.ع</b></div><div><span>رصيد المورد المتوقع بعد الحفظ</span><b data-testid="supplier-projected">{money(projected)} د.ع</b></div><div><span>{charge?'القاصة بعد الإضافة · دون خصم':'القاصة المتوقعة بعد التسديد'}</span><b>{money(cashAfter)} د.ع</b></div></div>}
  </fieldset>{error&&<div className="accountAlert error" role="alert">{error}</div>}<button className={'supplierMovementSave '+(charge?'charge':'')} type="submit" disabled={saving||(!pending.current&&(!valid||!account||loading))}>{saving?'جاري الحفظ…':pending.current?'إعادة تأكيد الحفظ':initial?'حفظ تعديل الوصل':charge?'إضافة المبلغ إلى حساب المورد':'حفظ التسديد وخصمه من القاصة'}</button></div>
  <div className="supplierDraftExport"><div><span className="accountEyebrow">راجع قبل الحفظ</span><h2>معاينة وصل الحركة <small>مسودة</small></h2></div><ReportActions enabled={valid&&!!account&&!loading&&!pending.current} html={html} filename={doc.title+'-'+party+'-مسودة'}/></div></form>}
  {last&&error&&<div className="accountAlert error" role="alert">{error}</div>}
 </section>;
}
