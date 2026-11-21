'use client';

import {useCallback,useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import {saveRequest} from './save-request.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import AppIcon from './app-icons';

const validState=value=>typeof value?.token==='string'&&!!value.token&&Array.isArray(value.users)
 &&value.users.every(user=>typeof user.id==='string'&&typeof user.name==='string'&&typeof user.enabled==='boolean');
const pendingKey=actorId=>'solar-profit-basis-users:'+actorId;
function pendingSave(actorId){
 try{
  const value=JSON.parse(sessionStorage.getItem(pendingKey(actorId))||'null');
  return value?.id&&value?.payload?.token&&Array.isArray(value.payload.changes)?value:null;
 }catch{return null;}
}

export default function ProfitBasisUsers({actorId}){
 const [state,setState]=useState(null),[changes,setChanges]=useState({}),[query,setQuery]=useState('');
 const [loading,setLoading]=useState(true),[saving,setSaving]=useState(false),[pending,setPending]=useState(null);
 const [error,setError]=useState(''),[message,setMessage]=useState(''),[conflict,setConflict]=useState(false);
 const current=useRef(true),writing=useRef(false),readController=useRef(null);
 const read=useCallback(async()=>{
  if(writing.current)return;
  readController.current?.abort();
  const controller=new AbortController();readController.current=controller;
  const timer=setTimeout(()=>controller.abort(),15000);
  setLoading(true);setError('');setMessage('');
  try{
   const {data,error}=await supabase.rpc('solar_profit_basis_users',{action:'state'}).abortSignal(controller.signal);
   if(readController.current!==controller||!current.current)return;
   if(error)throw error;
   if(!validState(data))throw new Error('تعذر التحقق من إعدادات أساس الربح.');
   setState(data);setChanges({});setConflict(false);
  }catch(err){if(readController.current===controller&&current.current)setError(controller.signal.aborted?'تأخر تحميل المستخدمين. أعد المحاولة.':err.message||'تعذر تحميل أساس الربح للمستخدمين.');}
  finally{clearTimeout(timer);if(readController.current===controller&&current.current)setLoading(false);}
 },[]);
 useEffect(()=>{
  current.current=true;setPending(pendingSave(actorId));void read();
  return ()=>{current.current=false;readController.current?.abort();};
 },[actorId,read]);
 function toggle(user,enabled){
  setChanges(previous=>{
   const next={...previous};
   if(enabled===user.enabled)delete next[user.id];else next[user.id]=enabled;
   return next;
  });
  setMessage('');setError('');
 }
 async function save(){
  if(writing.current||(!pending&&(!state||!Object.keys(changes).length)))return;
  const attempt=pending||{id:crypto.randomUUID(),payload:{token:state.token,changes:Object.entries(changes).map(([id,enabled])=>({id,enabled}))}};
  // Keep a submitted intent across a tab refresh when the response is interrupted.
  try{sessionStorage.setItem(pendingKey(actorId),JSON.stringify(attempt));}catch{/* The mounted form retains the same request for retry. */}
  writing.current=true;setSaving(true);setPending(attempt);setError('');setMessage('');
  try{
   const {data,error}=await saveRequest(signal=>supabase.rpc('solar_profit_basis_users',{action:'save',request_id:attempt.id,payload:attempt.payload}).abortSignal(signal));
   if(error)throw error;
   if(!validState(data))throw new Error('لم يصل تأكيد إعدادات الربح. أعد تأكيد الحفظ.');
   try{sessionStorage.removeItem(pendingKey(actorId));}catch{}
   if(!current.current)return;
   setState(data);setChanges({});setPending(null);setMessage('تم حفظ أساس الربح للمستخدمين.');
   window.dispatchEvent(new Event('solar-wholesale-pricing'));
  }catch(err){
   if(!current.current)return;
   if(/^[0-9A-Z]{5}$/.test(err.code||'')){
    try{sessionStorage.removeItem(pendingKey(actorId));}catch{}
    setPending(null);
    if(['40001','PT409'].includes(err.code)){setConflict(true);setError('تغيّرت الإعدادات. حمّل الاختيارات الحالية ثم راجع التعديل.');}
    else setError(err.message||'تعذر حفظ إعدادات الربح.');
   }else setError('لم يتأكد الحفظ. أعد إرسال نفس الطلب لتأكيد النتيجة.');
  }finally{writing.current=false;if(current.current)setSaving(false);}
 }
 const users=state?.users||[],filtered=users.filter(user=>normalizeSearch(user.name).includes(normalizeSearch(query)));
 const changedCount=Object.keys(changes).length,selected=users.filter(user=>user.enabled).length;
 const frozen=loading||saving||!!pending||conflict;
 return <details className="wpBasisPanel" aria-label="أساس ربح المستخدمين">
  <summary><AppIcon name="users" size={19}/><span>أساس ربح المستخدمين</span>{state&&<small>{selected} بسعر الجملة</small>}<AppIcon name="chevron" size={16}/></summary>
  <div className="wpBasisBody">
   <p>حدّد المستخدمين الذين تُحسب أرباحهم على سعر الجملة المحدد للمواد المفعّلة، في وصولات الجملة والمنظومات الجديدة. يُحسب ربح بقية المستخدمين على الكلفة الفعلية.</p>
   {loading&&<p role="status">جاري تحميل المستخدمين…</p>}
   {error&&<p role="alert" className="wpAlert">{error}</p>}
   {message&&<p role="status" className="wpSuccess">{message}</p>}
   {state&&<>
    {users.length>6&&<label className="wpSearch wpBasisSearch"><AppIcon name="search" size={16}/><input aria-label="بحث في مستخدمي أساس الربح" value={query} onChange={e=>setQuery(e.target.value)} placeholder="ابحث باسم المستخدم…"/></label>}
    <fieldset disabled={frozen} className="wpConfiguration"><legend className="wpVisuallyHidden">احتساب ربح المستخدم على سعر الجملة</legend><div className="wpUnifiedChecklist"><div className="wpScopeUsers">
     {filtered.map(user=>{
      const checked=changes[user.id]??user.enabled;
      return <label key={user.id} className={'wpScopeUser'+(checked?' checked':'')}><input type="checkbox" checked={checked} aria-label={'أساس الربح بسعر الجملة — '+user.name} onChange={e=>toggle(user,e.target.checked)}/><span className="wpScopeUserName">{user.name}{user.active===false&&<small>الحساب موقوف</small>}</span><span className={'wpScopeStatus '+(checked?'required':'free')}>{checked?'سعر الجملة':'الكلفة الفعلية'}</span></label>;
     })}
     {!filtered.length&&<p className="wpScopeEmpty">{query?'لا يوجد مستخدم مطابق للبحث.':'لا توجد حسابات إدارية بصلاحيات محددة.'}</p>}
    </div></div></fieldset>
    <p>المادة غير المفعّلة أو بلا سعر محدد تُحسب بكلفتها الفعلية داخلياً. تبقى كلفة الشركة مخفية عن المستخدم المحدد.</p>
   </>}
   <div className="wpConfigurationSave"><span>{changedCount>0?changedCount+' تعديلات غير محفوظة':''}</span><div>
    {(!state||conflict)&&!loading&&!pending&&<button type="button" onClick={read}>تحميل الإعدادات الحالية</button>}
    {changedCount>0&&!frozen&&<button type="button" onClick={()=>setChanges({})}>إلغاء التعديل</button>}
    {(state||pending)&&<button type="button" className="primary" disabled={saving||loading||conflict||(!pending&&!changedCount)} onClick={save}>{saving?'جاري الحفظ…':pending?'تأكيد الحفظ السابق':'حفظ أساس الربح'}</button>}
   </div></div>
  </div>
 </details>;
}
