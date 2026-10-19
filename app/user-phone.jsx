'use client';
import {useState} from 'react';
import {supabase} from './supabase';
import {normalizeUserPhone,validUserPhone} from './user-phone-utils.mjs';
export default function UserPhone({profile,onSaved,onClose,onLogout}){
 const [phone,setPhone]=useState(profile.phone||''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 async function save(ev){ev.preventDefault();if(busy)return;if(!validUserPhone(phone)){setError('أدخل رقم هاتف صحيحاً، مثل 07701234567.');return;}setBusy(true);setError('');
  try{const {data,error}=await supabase.rpc('solar_my_phone',{phone:normalizeUserPhone(phone)});if(error)throw error;onSaved(data.phone);}catch(e){setError(e.message||'تعذر حفظ الرقم. أعد المحاولة.');}finally{setBusy(false);}
 }
 return <main className="loginPage userPhonePage"><section className="loginCard"><h1>{profile.phone?'رقم هاتفي':'أكمل رقم هاتفك'}</h1><p>يظهر رقمك على فواتير البيع ووصولات التسديد الخاصة بك، حتى يگدر الزبون يتواصل وياك.</p><form onSubmit={save}><label>رقم هاتف المستخدم<input autoFocus type="tel" inputMode="tel" autoComplete="tel" dir="ltr" aria-label="رقم هاتفي للوصولات" placeholder="07701234567" maxLength={30} value={phone} onChange={e=>setPhone(e.target.value)} disabled={busy} required/></label>{error&&<p role="alert" className="loginError">{error}</p>}<button type="submit" disabled={busy}>{busy?'جاري حفظ الرقم…':'حفظ رقم الهاتف'}</button>{onClose&&<button type="button" className="secondary" disabled={busy} onClick={onClose}>رجوع</button>}{!onClose&&<button type="button" className="secondary" disabled={busy} onClick={onLogout}>تسجيل خروج</button>}</form></section></main>;
}
