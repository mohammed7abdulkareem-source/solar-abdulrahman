'use client';
import {useState} from 'react';
import {money,dateKey} from './supplier-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {userDisplayName} from './user-name-utils.mjs';
import './profit-target-form.css';

function targetValue(raw) {
 const text=normalizeSearch(raw).replace(/−/g,'-').replace(/٫/g,'.').replace(/٬/g,',');
 if (!/^[+-]?(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$/.test(text)) return null;
 const value=Number(text.replaceAll(',',''));
 return Number.isSafeInteger(Math.round(value*100)) ? value : null;
}
const signed=value=>(value>0?'+':'')+money(value);
const amountRow=(label,value)=> <div key={label}><dt>{label}</dt><dd><bdi>{money(value)}</bdi> د.ع</dd></div>;

export default function ProfitTargetForm({owner,staff,onOwner,data,loading,busy,blocked,pending,error,onSave,onRetry}) {
 const [raw,setRaw]=useState(''),[note,setNote]=useState(''),[review,setReview]=useState(null);
 const scoped=data?.ownerId===owner ? data : null;
 const ownerRecord=staff.find(user=>user.id===owner);
 const name=scoped?.ownerName || (ownerRecord&&userDisplayName(ownerRecord)) || 'المستخدم';
 const before=scoped?.retainedProfit;
 const hasBalance=before!=null&&before!==''&&Number.isFinite(Number(before));
 const target=targetValue(raw);
 const token=scoped?.externalAdjustmentToken;
 const valid=hasBalance&&!!token&&target!==null&&Number(before)!==target&&ownerRecord?.active!==false;
 const payload={ownerId:owner,targetBalance:target,expectedToken:token,note:note.trim()};
 const signature=JSON.stringify(payload);
 const ready=valid&&!loading&&!!review&&review===signature;
 const locked=busy||blocked||!!pending;
 const history=(scoped?.externalAdjustments||[]).filter(row=>row.ownerId===owner);
 function change(value){setRaw(value);setReview(null);}
 function changeSign(){const text=normalizeSearch(raw).replace(/−/g,'-');change(text.startsWith('-')?text.slice(1):'-'+text.replace(/^\+/,''));}
 async function submit(event){
  event.preventDefault();
  if(locked||loading||!valid)return;
  if(!ready){setReview(signature);return;}
  if(await onSave(payload)){
   setRaw(current=>current===raw?'':current);
   setNote(current=>current===note?'':current);
  }
  setReview(null);
 }
 return <section className="uiPanel externalProfit" aria-label="تعديل رصيد الأرباح خارج البرنامج">
  <div className="panelTitle"><div><h2>تعديل رصيد الأرباح خارج البرنامج</h2><p>لتسوية تمت خارج البرنامج. يُسجَّل الفرق على أرباح المستخدم فقط، بشكل مستقل عن القاصة وحسابات الموردين وطلبات توزيع الأرباح.</p></div></div>
  <label className="externalProfitOwner">المستخدم
   <select aria-label="مستخدم كشف التسوية" value={owner} disabled={locked} onChange={event=>onOwner(event.target.value)}>
    {staff.filter(user=>!['warehouse','installer'].includes(user.user_type)).map(user=><option key={user.id} value={user.id}>{userDisplayName(user)}</option>)}
   </select>
  </label>
  <div className="externalProfitBalance"><span>رصيد الأرباح الحالي · كل الفترات</span>
   {loading?<span role="status">جاري تحميل الرصيد…</span>:hasBalance?<strong><bdi data-testid="external-profit-balance">{money(before)}</bdi> <small>د.ع</small></strong>:<span role="status">الرصيد غير متاح</span>}
  </div>
  {error&&<p role="alert" className="accountAlert error">{error}</p>}
  {ownerRecord?.active===false&&<small>حساب المستخدم غير نشط. يمكنك مراجعة كشفه وسجل تعديلاته.</small>}
  {pending?<div className="externalProfitPending"><p role="status">بانتظار تأكيد تعديل رصيد {name} إلى <bdi>{money(pending.payload.targetBalance)}</bdi> د.ع.</p><button type="button" className="uiButton primary" disabled={busy} onClick={onRetry}>إعادة تأكيد العملية</button></div>:
  <form onSubmit={submit}>
   <fieldset disabled={locked||!hasBalance||!token||ownerRecord?.active===false}>
    <label htmlFor="external-profit-target">رصيد الأرباح الجديد · د.ع</label>
    <div className="externalProfitInputs">
     <input id="external-profit-target" aria-label="رصيد الأرباح الجديد" type="text" inputMode="decimal" dir="ltr" autoComplete="off" value={raw}
      aria-invalid={raw!==''&&target===null} onChange={event=>change(event.target.value)} placeholder="0.00"/>
     <button type="button" className="uiButton" aria-label="تبديل إشارة الرصيد" onClick={changeSign}>±</button>
     <button type="button" className="uiButton" onClick={()=>change('0')}>تصفير الرصيد</button>
    </div>
    {raw!==''&&target===null&&<small>أدخل مبلغاً موجباً أو سالباً بمنزلتين عشريتين كحد أقصى.</small>}
    {target!==null&&Number(before)===target&&<small>الرصيد المدخل يساوي الرصيد الحالي.</small>}
    <label>ملاحظة · اختياري<input aria-label="ملاحظة تعديل الرصيد" value={note} maxLength={2000} onChange={event=>{setNote(event.target.value);setReview(null);}}/></label>
   </fieldset>
   {ready&&<div className="externalProfitPreview" role="region" aria-label="معاينة تعديل رصيد الأرباح">
    <h3>تعديل رصيد {name}</h3><dl>
     {amountRow('الرصيد الحالي',before)}{amountRow('الرصيد الجديد',target)}
     <div><dt>فرق التعديل</dt><dd><bdi>{signed(Math.round((target-Number(before))*100)/100)}</bdi> د.ع</dd></div>
    </dl>{note.trim()&&<p>{note.trim()}</p>}
   </div>}
   <button type="submit" className="uiButton primary" disabled={locked||loading||!valid}>{ready?'تأكيد تعديل الرصيد':'معاينة تعديل الرصيد'}</button>
  </form>}
  {history.length>0&&<details className="externalProfitHistory"><summary>سجل تعديلات الرصيد الخارجية</summary>
   {history.map(row=><article key={row.id}><div><strong dir="ltr">{signed(Number(row.delta))} د.ع</strong><small>{dateKey(row.createdAt)} · {row.actorName}</small></div><dl>{amountRow('قبل',row.before)}{amountRow('بعد',row.after)}</dl>{row.note&&<p>{row.note}</p>}</article>)}
  </details>}
 </section>;
}
