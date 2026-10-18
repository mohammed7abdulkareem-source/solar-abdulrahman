'use client';
import {useEffect,useState} from 'react';
import {canEditExchangeRate,exchangeRateError} from './currency-utils.mjs';
import {loadExchangeRate,saveExchangeRate} from './currency-store.mjs';
import {moneyInput,money} from './supplier-utils.mjs';

export default function ExchangeRate({profile}){
  const [current,setCurrent]=useState(null),[rate,setRate]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState('');
  const permitted=canEditExchangeRate(profile);
  useEffect(()=>{let live=true;loadExchangeRate().then(data=>{if(live){setCurrent(data);setRate(data.rate==null?'':String(data.rate));}}).catch(()=>{if(live)setError('تعذر تحميل سعر الصرف. حدّث الصفحة أو راجع تحديث قاعدة البيانات.');});return()=>{live=false;};},[]);
  async function save(event){
    event.preventDefault();if(busy||!permitted||!current)return;
    const validation=exchangeRateError('USD',rate);if(validation){setError(validation);return;}
    setBusy(true);setError('');setNotice('');
    try{const data=await saveExchangeRate(rate,current.revision);setCurrent(data);setRate(String(data.rate));setNotice('تم حفظ سعر الصرف للمشتريات الجديدة. كلف المخزون والمبيعات السابقة تبقى محفوظة.');}
    catch(e){setError(['40001','PT409'].includes(e.code)?'تغيّر السعر بواسطة مستخدم آخر. حدّث الصفحة قبل الحفظ.':e.message||'تعذر حفظ سعر الصرف.');}
    finally{setBusy(false);}
  }
  return <section className="card form exchangeRatePage"><h3>سعر صرف الدولار</h3><p>عدد الدنانير العراقية مقابل دولار واحد. يُنسخ إلى فاتورة الشراء ويُحفظ معها.</p>{current&&<div className="financeTiles"><div className="financeBlue"><small>دولار واحد</small><b>{current.rate==null?'غير محدد':money(current.rate)+' د.ع'}</b></div><div className="financeGreen"><small>100 دولار</small><b>{current.rate==null?'غير محدد':money(current.rate*100)+' د.ع'}</b></div></div>}{current?.updatedAt&&<small>آخر تغيير: {new Date(current.updatedAt).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'})}</small>}{permitted?<form onSubmit={save}><label>سعر الصرف · د.ع لكل دولار<input aria-label="سعر الصرف" inputMode="decimal" value={rate} onChange={e=>setRate(moneyInput(e.target.value))} disabled={busy||!current} placeholder="مثال: 1500" required/></label><small>{Number(rate)>0?'100 دولار = '+money(Number(rate)*100)+' د.ع':'أدخل السعر الفعلي؛ لا يوجد سعر افتراضي مفترض.'}</small><button disabled={busy||!current}>{busy?'جاري الحفظ…':'حفظ سعر الصرف'}</button></form>:<p>يمكنك استخدام السعر المعتمد. تغييره يتطلب صلاحية «تعديل سعر الصرف» من الإدارة.</p>}<p className="mutedNote">البيع بالدينار، وكشف المورد بعملة الاتفاق معه. كل شراء وتسديد يحتفظ بعملته وسعر صرفه وقت الحفظ. المخزون يُقيّم بمتوسط الكلفة، وأرباح المبيعات السابقة لا تتغير بتغيير صرف اليوم.</p>{error&&<p className="workflowError" role="alert">{error}</p>}{notice&&<p className="workflowSuccess" role="status">{notice}</p>}</section>;
}
