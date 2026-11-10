'use client';
import {useCallback,useEffect,useMemo,useRef,useState} from 'react';
import {supabase} from './supabase';
import {canManageWholesalePricing} from './access-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {formatMoney as money} from './money-format.mjs';
import {saveRequest} from './save-request.mjs';
import {unlockNotificationSound,playNotificationSound} from './notification-sound.mjs';
import {WHOLESALE_PRICE_BATCH_LIMIT,wholesalePriceDraft,wholesalePriceChanged,wholesalePriceValidation,wholesalePriceItems,readWholesalePriceAttempt,rememberWholesalePriceAttempt,clearWholesalePriceAttempt} from './wholesale-pricing-utils.mjs';
import AppIcon from './app-icons';
import MoneyInput from './money-input';
import './wholesale-pricing.css';

const dateLabel=value=>{const date=value?new Date(value):null;return date&&!Number.isNaN(date.getTime())?date.toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'}):'لم يُسجل تغيير بعد';};
const PAGE_SIZE=40;
export default function WholesalePricing({profile}){
 const allowed=canManageWholesalePricing(profile),userId=profile?.id;
 const [data,setData]=useState(null),[drafts,setDrafts]=useState({}),[query,setQuery]=useState(''),[filter,setFilter]=useState('all'),[limit,setLimit]=useState(PAGE_SIZE),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[pending,setPending]=useState(null),[conflict,setConflict]=useState(false),[reloadWarning,setReloadWarning]=useState(false);
 const sequence=useRef(0),controller=useRef(null),lock=useRef(false),mounted=useRef(true),liveUser=useRef(userId);liveUser.current=userId;
 const products=Array.isArray(data?.products)?data.products:[],dirtyRows=products.filter(row=>wholesalePriceChanged(row,drafts[row.id])),dirtyCount=dirtyRows.length;
 const rowErrors=Object.fromEntries(dirtyRows.map(row=>[row.id,wholesalePriceValidation(drafts[row.id])]).filter(([,message])=>message));
 const frozen=loading||busy||!!pending||conflict||!data;
 const load=useCallback(async()=>{
  if(!allowed||lock.current)return;
  const request=++sequence.current;controller.current?.abort();const nextController=new AbortController();controller.current=nextController;
  setLoading(true);setError('');const timer=setTimeout(()=>nextController.abort(),15000);
  try{
   const result=await supabase.rpc('solar_wholesale_pricing',{action:'state'}).abortSignal(nextController.signal);
   if(request!==sequence.current||liveUser.current!==userId)return;
   if(result.error)throw result.error;
   if(!result.data?.canManage||result.data.currency!=='IQD'||!Array.isArray(result.data.products))throw new Error('تعذر تحميل أسعار الجملة ضمن صلاحيات حسابك.');
   setData(result.data);setDrafts({});setConflict(false);setReloadWarning(false);setLimit(PAGE_SIZE);
  }catch(failure){if(request===sequence.current&&liveUser.current===userId){setData(null);setError(nextController.signal.aborted?'تأخر تحميل أسعار الجملة. تحقق من الاتصال وحاول مجدداً.':failure.message||'تعذر تحميل أسعار بيع الجملة.');}}
  finally{clearTimeout(timer);if(request===sequence.current&&liveUser.current===userId)setLoading(false);}
 },[allowed,userId]);
 useEffect(()=>{mounted.current=true;setData(null);setDrafts({});setNotice('');setPending(readWholesalePriceAttempt(userId));setConflict(false);setReloadWarning(false);void load();return()=>{mounted.current=false;++sequence.current;controller.current?.abort();};},[load,userId]);
 useEffect(()=>{setLimit(PAGE_SIZE);},[query,filter]);
 const matches=useMemo(()=>{
  const needle=normalizeSearch(query);
  return products.filter(row=>(!needle||normalizeSearch([row.name,row.code,row.brand,row.category].join(' ')).includes(needle))&&(filter==='available'?Number(row.qty)>0:filter==='active'?(drafts[row.id]?.enabled??row.enabled):filter==='changed'?wholesalePriceChanged(row,drafts[row.id]):true));
 },[products,query,filter,drafts]);
 function changeRow(row,patch){
  if(frozen)return;
  setDrafts(previous=>{const next={...(previous[row.id]||wholesalePriceDraft(row)),...patch};if(!wholesalePriceChanged(row,next)){const copy={...previous};delete copy[row.id];return copy;}return {...previous,[row.id]:next};});
  setError('');setNotice('');
 }
 function reload(){if(busy||pending)return;if(dirtyCount){setReloadWarning(true);return;}void load();}
 async function write(action,payload){
  if(lock.current||!allowed||(!pending&&(!data||loading||conflict)))return;
  const attempt=pending||{id:crypto.randomUUID(),action,payload};
  if(!rememberWholesalePriceAttempt(userId,attempt)){setError('تعذر تجهيز الحفظ على هذا الجهاز. تحقق من مساحة الجهاز وإعدادات المتصفح ثم حاول مجدداً.');return;}
  lock.current=true;setBusy(true);setError('');setNotice('');setPending(attempt);void unlockNotificationSound();
  ++sequence.current;controller.current?.abort();
  try{
   const result=await saveRequest(signal=>supabase.rpc('solar_wholesale_pricing',{action:attempt.action,request_id:attempt.id,payload:attempt.payload}).abortSignal(signal));
   if(result.error)throw result.error;
   if(!result.data?.canManage||result.data.currency!=='IQD'||!Array.isArray(result.data.products))throw new Error('لم يصل تأكيد كامل لحفظ أسعار الجملة.');
   clearWholesalePriceAttempt(userId,attempt.id);
   if(!mounted.current||liveUser.current!==userId)return;
   setPending(null);setData(result.data);setConflict(false);setReloadWarning(false);
   if(attempt.action==='save')setDrafts({});
   setNotice(attempt.action==='save'?'تم حفظ أسعار بيع الجملة.':attempt.payload.enabled?'تم تشغيل الأسعار الإلزامية وإرسال الإشعار للمستخدمين.':'تم إيقاف الأسعار الإلزامية مع الاحتفاظ بالأسعار المحفوظة وإرسال الإشعار للمستخدمين.');
   window.dispatchEvent(new CustomEvent('solar-wholesale-pricing'));void playNotificationSound();
  }catch(failure){
   if(!mounted.current||liveUser.current!==userId)return;
   const definitive=/^[0-9A-Z]{5}$/.test(failure.code||'');
   if(definitive){clearWholesalePriceAttempt(userId,attempt.id);setPending(null);if(['PT409','40001'].includes(failure.code))setConflict(true);}
   setError(definitive?(['PT409','40001'].includes(failure.code)?'تغيّرت الأسعار بواسطة مستخدم آخر. تعديلاتك محفوظة أمامك؛ حدّث القائمة وراجع الأسعار قبل الحفظ.':failure.message||'تعذر حفظ أسعار الجملة.'):'لم يتأكد الحفظ بسبب الاتصال. أعد تأكيد الطلب نفسه أدناه لتجنب تكرار التغيير أو الإشعار.');
  }finally{lock.current=false;if(mounted.current&&liveUser.current===userId)setBusy(false);}
 }
 function save(event){
  event.preventDefault();if(frozen||!dirtyCount)return;
  if(Object.keys(rowErrors).length){setError('راجع أسعار المواد المشار إليها قبل الحفظ.');return;}
  void write('save',{items:wholesalePriceItems(products,drafts)});
 }
 if(!allowed)return <p className="wpAlert" role="alert">إدارة أسعار بيع الجملة غير متاحة ضمن صلاحيات حسابك.</p>;
 return <section className="wholesalePricing" aria-label="إدارة أسعار بيع الجملة">
  <header className="wpHero"><div className="wpHeroHeading"><span className="wpHeroIcon"><AppIcon name="tag" size={25}/></span><div><h2>أسعار بيع الجملة</h2><p>حدد الحد الأدنى لكل مادة، وتحكّم بتطبيقه على البيع.</p></div></div><span className="wpCurrency">دينار عراقي · IQD</span></header>
  {error&&<p className="wpAlert" role="alert">{error}</p>}{notice&&<p className="wpSuccess" role="status">{notice}</p>}
  {pending&&<div className="wpPending" role="status"><span>يوجد طلب حفظ لم يتأكد بعد. تبقى بيانات الطلب ثابتة حتى تأكيد النتيجة.</span><button type="button" disabled={busy||loading} onClick={()=>write(pending.action,pending.payload)}>{busy?'جاري التأكيد…':'تأكيد حفظ أسعار الجملة السابق'}</button></div>}
  {loading?<div className="wpLoading" role="status"><AppIcon name="refresh" size={19}/>جاري تحميل المواد والأسعار…</div>:!data?<div className="wpEmpty"><p>لم تُحمّل قائمة الأسعار.</p><button type="button" onClick={()=>void load()}><AppIcon name="refresh" size={17}/>إعادة التحميل</button></div>:<>
   <section className={'wpPolicy'+(data.enabled?' on':'')} aria-label="حالة التسعير الإلزامي للجملة"><div className="wpPolicyHead"><span className="wpPolicyTitle"><i className="wpPolicyDot"/>{data.enabled?'الأسعار الإلزامية مفعّلة':'الأسعار الإلزامية متوقفة'}</span><button type="button" className="wpPolicyButton" disabled={frozen} onClick={()=>write('toggle',{enabled:!data.enabled,expectedRevision:data.revision})}><AppIcon name="power" size={17}/>{data.enabled?'إيقاف الأسعار الإلزامية':'تشغيل الأسعار الإلزامية'}</button></div><p>عند التشغيل، يُطبّق الحد الأدنى على المواد المحددة أدناه، ويمكن لمن لديه صلاحية البيع الحر تجاوزه. الإيقاف يحتفظ بالأسعار والاختيارات.</p><div className="wpPolicyMeta"><span>آخر تعديل: <b>{dateLabel(data.updatedAt)}</b></span>{data.updatedByName&&<span>بواسطة: <b>{data.updatedByName}</b></span>}</div></section>
   <div className="wpSummary"><div><span>المواد المسجلة</span><strong>{money(products.length)}</strong></div><div><span>مواد بسعر محفوظ</span><strong>{money(products.filter(row=>row.minPrice!=null).length)}</strong></div><div><span>تعديلات غير محفوظة</span><strong>{money(dirtyCount)}</strong></div></div>
   <form onSubmit={save}>
    <section className="wpCatalog"><header className="wpCatalogHead"><h3>قائمة المواد والأسعار</h3><button type="button" disabled={busy||!!pending} onClick={reload}><AppIcon name="refresh" size={16}/>تحديث</button></header>
     {reloadWarning&&<div className="wpReloadWarning"><span>تحديث القائمة يلغي تعديلاتك غير المحفوظة ويجلب آخر الأسعار المعتمدة.</span><div><button type="button" onClick={()=>void load()}>تحديث وإلغاء تعديلاتي</button><button type="button" onClick={()=>setReloadWarning(false)}>الاحتفاظ بتعديلاتي</button></div></div>}
     <div className="wpFilters"><label className="wpSearch"><AppIcon name="search" size={18}/><input aria-label="البحث في أسعار بيع الجملة" value={query} onChange={event=>setQuery(event.target.value)} placeholder="ابحث باسم المادة أو الكود أو البراند…"/></label><label className="wpFilterSelect">عرض<select aria-label="تصفية مواد أسعار الجملة" value={filter} onChange={event=>setFilter(event.target.value)}><option value="all">كل المواد</option><option value="available">المتوفر بالمخزن</option><option value="active">المحدد للتطبيق</option><option value="changed">التعديلات الحالية</option></select></label><span className="wpFilterCount">{money(matches.length)} مادة</span></div>
     {!matches.length?<div className="wpEmpty"><AppIcon name="package" size={25}/><p>{query||filter!=='all'?'لا توجد مواد مطابقة للبحث والتصفية.':'لا توجد مواد متاحة ضمن مخازنك المسموحة.'}</p></div>:<div className="wpTableWrap"><table className="wpTable"><thead><tr><th scope="col">المادة</th><th scope="col">المتوفر</th><th scope="col">الكلفة · د.ع</th><th scope="col">سعر البيع الأدنى</th><th scope="col">التطبيق</th></tr></thead><tbody>{matches.slice(0,limit).map(row=>{
      const draft=drafts[row.id]||wholesalePriceDraft(row),changed=wholesalePriceChanged(row,draft),disabled=frozen||(!changed&&dirtyCount>=WHOLESALE_PRICE_BATCH_LIMIT),inputId='wholesale-minimum-'+row.id;
      return <tr key={row.id} className={changed?'isDirty':''}><td><span className="wpProductName">{row.name}</span><span className="wpProductMeta">{[row.code&&'كود: '+row.code,row.brand,row.category].filter(Boolean).join(' · ')}</span>{row.updatedAt&&<small className="wpProductMeta">{dateLabel(row.updatedAt)}{row.updatedByName?' · '+row.updatedByName:''}</small>}{changed&&<span className="wpRowChanged">غير محفوظ</span>}</td><td data-label="المتوفر"><span className="wpQty" dir="ltr">{money(row.qty)}</span></td><td data-label="الكلفة"><span className="wpCost" dir="ltr">{money(row.cost)}<small>د.ع</small></span></td><td className="wpPriceCell"><label htmlFor={inputId} className="wpPriceLabel">سعر البيع الأدنى · د.ع</label><div className="wpPriceInput"><MoneyInput id={inputId} aria-label={'سعر البيع الأدنى — '+row.name} value={draft.minPrice} onChange={minPrice=>changeRow(row,{minPrice})} disabled={disabled} placeholder="غير محدد" aria-invalid={!!rowErrors[row.id]} aria-describedby={rowErrors[row.id]?'wholesale-error-'+row.id:undefined}/><span>د.ع</span></div>{rowErrors[row.id]&&<p className="wpRowError" id={'wholesale-error-'+row.id}>{rowErrors[row.id]}</p>}</td><td><label className="wpApply"><input type="checkbox" aria-label={'تطبيق الحد الأدنى — '+row.name} checked={draft.enabled} onChange={event=>changeRow(row,{enabled:event.target.checked})} disabled={disabled}/><span>تطبيق الحد الأدنى</span></label></td></tr>;
     })}</tbody></table></div>}
     {matches.length>limit&&<button type="button" className="wpLoadMore" onClick={()=>setLimit(value=>value+PAGE_SIZE)}>عرض {Math.min(PAGE_SIZE,matches.length-limit)} مادة أخرى</button>}
    </section>
    <div className="wpSaveBar"><div><b>{dirtyCount?dirtyCount+' مادة بانتظار الحفظ':'الأسعار المحفوظة جاهزة'}</b><small>{dirtyCount>=WHOLESALE_PRICE_BATCH_LIMIT?'احفظ هذه التعديلات قبل تعديل مواد أخرى.':'السعر الفارغ يبقى غير محدد حتى تختاره وتحفظه.'}</small></div><button type="submit" disabled={frozen||!dirtyCount||Object.keys(rowErrors).length>0}><AppIcon name={busy?'refresh':'check'} size={18}/>{busy?'جاري الحفظ…':'حفظ الأسعار'}</button></div>
   </form>
   <p className="wpPrivateNote">الكلفة المعروضة للمراجعة الداخلية. تغيير هذه الإعدادات لا يغيّر الفواتير السابقة.</p>
  </>}
 </section>;
}
