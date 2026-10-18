'use client';
import {useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import MoneyInput from './money-input';
import {formatMoney as money,currencyUnit as unit} from './money-format.mjs';

export default function CashReconciliation({initialOwner,initialRate,onClose,onSaved}){
 const [owner,setOwner]=useState(initialOwner||''),[mode,setMode]=useState(initialOwner?'set':'zero'),[currency,setCurrency]=useState(initialOwner?'IQD':'both'),[amount,setAmount]=useState(''),[rate,setRate]=useState(initialRate||''),[note,setNote]=useState('مطابقة رصيد القاصة'),[data,setData]=useState(null),[directory,setDirectory]=useState([]),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(''),[confirming,setConfirming]=useState(false),[refresh,setRefresh]=useState(0);
 const attempt=useRef(null),actions=useRef(null);
 useEffect(()=>{if(confirming)actions.current?.scrollIntoView({block:'center',behavior:'smooth'});},[confirming]);
 useEffect(()=>{let live=true;setLoading(true);setData(null);setError('');supabase.rpc('solar_cash_reconcile',{action:'context',payload:{ownerId:owner||null}}).then(r=>{if(r.error)throw r.error;if(live){setData(r.data);setDirectory(r.data.owners);}}).catch(e=>live&&setError(e.message||'تعذر تحميل القاصات')).finally(()=>live&&setLoading(false));return()=>{live=false;};},[owner,refresh]);
 const target=mode==='zero'?0:Number(amount),rows=(data?.rows||[]).map(r=>({...r,afterIQD:['IQD','both'].includes(currency)?target:Number(r.IQD),afterUSD:['USD','both'].includes(currency)?target:Number(r.USD)}));
 const changed=rows.filter(r=>r.afterIQD!==Number(r.IQD)||r.afterUSD!==Number(r.USD)||(['USD','both'].includes(currency)&&r.afterUSD===0&&Number(r.usdBook)!==0));
 const needsRate=changed.some(r=>r.afterUSD>Number(r.USD));
 const validation=data?.pendingCount?'احسم عمليات تسليم القاصة المعلّقة أولاً.':mode==='set'&&(amount===''||!Number.isFinite(target)||target<0||target>1e12)?'اكتب الرصيد الصحيح المطلوب، أو اختر تصفير الرصيد.':!changed.length?'الرصيد المطلوب مطابق للرصيد الحالي؛ لا توجد مبالغ تحتاج تسوية.':note.trim().length<3?'اكتب سبب التسوية بثلاثة أحرف على الأقل.':needsRate&&!(Number(rate)>0&&Number(rate)<=1e6)?'أدخل سعر صرف صحيح للدولار المضاف.':'';
 const locked=busy||!!attempt.current;
 async function save(e){e.preventDefault();if(busy||loading||!data)return;if(validation){setError(validation);return;}setError('');if(!confirming){setConfirming(true);return;}
  const payload={ownerId:owner||null,mode,currency,target,rate:needsRate?Number(rate):null,note:note.trim(),expectedToken:data.token},signature=JSON.stringify(payload);
  if(attempt.current&&attempt.current.signature!==signature){setError('أعد تأكيد نفس العملية السابقة.');return;}
  if(!attempt.current)attempt.current={id:crypto.randomUUID(),signature};setBusy(true);setError('');
  try{const r=await supabase.rpc('solar_cash_reconcile',{action:'apply',request_id:attempt.current.id,payload});if(r.error)throw r.error;attempt.current=null;await onSaved(r.data);}
  catch(e){if(e.code){attempt.current=null;setConfirming(false);}setError(e.code?e.message:'لم يتأكد الرد؛ اضغط إعادة تأكيد التسوية بنفس البيانات ولن تتكرر.');}finally{setBusy(false);}
 }
 return <section className="cashReconciliation accountWorkspace"><header className="workspaceHead"><div><span className="sectionKicker">للأدمن فقط</span><h1>تعديل وتصفير القاصات</h1><p>طابق رصيد البرنامج مع النقد الموجود فعليًا.</p></div><button className="uiButton secondary" disabled={locked} onClick={onClose}>الرجوع للصندوق</button></header>
 <div className="reconcileInfo">التسوية تخص النقد فقط. لا تلغي تسديد مورد أو زبون، ولا تغيّر المبيعات أو الأرباح. الحركات السابقة تبقى محفوظة.</div>
 {error&&<p className="accountAlert error" role="alert">{error}</p>}
 <form className="uiPanel" onSubmit={save} noValidate><fieldset disabled={locked||confirming}>
 <div className="formGrid"><label>القاصة المطلوب تعديلها<select aria-label="قاصة التسوية" value={owner} onChange={e=>{setOwner(e.target.value);setAmount('');if(!e.target.value){setMode('zero');setCurrency('both');}}}><option value="">جميع القاصات — تصفير فقط</option>{directory.map(r=><option key={r.id} value={r.id}>{r.name}{r.active?'':' · حساب غير نشط'}</option>)}</select></label>
 <label>نوع التسوية<select aria-label="نوع تسوية القاصة" value={mode} onChange={e=>{setMode(e.target.value);if(e.target.value==='set'&&currency==='both')setCurrency('IQD');}}><option value="set" disabled={!owner}>تحديد الرصيد الصحيح</option><option value="zero">تصفير الرصيد</option></select></label>
 <label>العملة<select aria-label="عملة تسوية القاصة" value={currency} disabled={!owner} onChange={e=>setCurrency(e.target.value)}><option value="IQD">الدينار العراقي · IQD</option><option value="USD">الدولار الأمريكي · USD</option>{mode==='zero'&&<option value="both">الدينار والدولار معًا</option>}</select></label>
 {mode==='set'&&<label>الرصيد الصحيح بعد التعديل · {unit(currency)}<MoneyInput aria-label="الرصيد الصحيح للقاصة" value={amount} onChange={setAmount} currency={currency} required/></label>}
 {needsRate&&<label>صرف الدولار المضاف · د.ع لكل دولار<MoneyInput aria-label="صرف تسوية الدولار" value={rate} onChange={setRate} required/><small>يثبّت قيمة الدولار المضاف فقط، ولا يحوّل رصيد الدينار.</small></label>}</div>
 <label>سبب التعديل أو التصفير · قابل للتغيير<textarea aria-label="سبب تسوية القاصة" value={note} onChange={e=>setNote(e.target.value)} maxLength={2000} placeholder="مثال: مطابقة النقد الفعلي بعد مراجعة الوصولات" required/></label>
 </fieldset>
 {loading?<p role="status">جاري قراءة الأرصدة…</p>:<><div className="panelTitle"><h2>{confirming?'راجع النتيجة قبل التأكيد':'الأرصدة قبل وبعد التسوية'}</h2><button type="button" className="uiButton secondary" disabled={locked||confirming} onClick={()=>setRefresh(n=>n+1)}>تحديث الأرصدة</button></div>{data?.pendingCount>0&&<p className="accountAlert error" role="alert">توجد {data.pendingCount} عملية تسليم قاصة معلّقة. احسم الاستلام أو الإلغاء من «تسليم واستلام القاصة» قبل التسوية.</p>}
 <div className="reconcileRows">{rows.map(r=><article className="reconcileRow" key={r.id}><h3>{r.name}</h3>{['IQD','USD'].map(c=><div key={c}><span>{c==='IQD'?'الدينار':'الدولار'}</span><bdi>{money(r[c],c)} {unit(c)}</bdi><span>←</span><bdi className="reconcileAfter">{mode==='set'&&amount===''&&c===currency?'—':money(r['after'+c],c)} {unit(c)}</bdi></div>)}</article>)}</div></>}
 <p className="formHint">يُحفظ اسم الأدمن والسبب والرصيد السابق والجديد في وصل تسوية. تصفير القاصة يُبقي سجلها ولا يحذفه.</p>
 {confirming&&<p className="reconcileConfirm">{owner?'سيُعدّل رصيد القاصة المحددة فقط.':'سيُصفّر رصيد الدينار والدولار في جميع القاصات المعروضة.'} عدد القاصات التي ستتغير: {changed.length}.</p>}
 {validation&&!loading&&<p className="formHint reconcileValidation">{validation}</p>}<div className="reconcileActions" ref={actions}>{confirming&&<button type="button" className="uiButton secondary" disabled={locked} onClick={()=>setConfirming(false)}>رجوع للتعديل</button>}<button type="submit" className={'uiButton '+(mode==='zero'?'reconcileDanger':'primary')} disabled={busy||loading||!data}>{busy?'جاري حفظ التسوية…':attempt.current?'إعادة تأكيد التسوية':confirming?(mode==='zero'?'تأكيد تصفير الأرصدة':'تأكيد تعديل الرصيد'):'معاينة التسوية'}</button></div>
 </form></section>;
}
