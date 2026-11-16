'use client';
import {useCallback,useEffect,useMemo,useRef,useState} from 'react';
import {supabase} from './supabase';
import {canManageWholesalePricing} from './access-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {formatMoney as money} from './money-format.mjs';
import {saveRequest} from './save-request.mjs';
import {unlockNotificationSound,playNotificationSound} from './notification-sound.mjs';
import {WHOLESALE_PRICE_BATCH_LIMIT,availableWholesalePriceProducts,wholesalePriceSaveNotice,wholesalePriceDraft,wholesalePriceChanged,wholesalePriceValidation,wholesalePriceItems,wholesaleScopeDraft,wholesaleScopeChanged,wholesaleScopeValidation,wholesaleScopePayload,readWholesalePriceAttempt,rememberWholesalePriceAttempt,clearWholesalePriceAttempt} from './wholesale-pricing-utils.mjs';
import AppIcon from './app-icons';
import MoneyInput from './money-input';
import './wholesale-pricing.css';

const dateLabel=value=>{const date=value?new Date(value):null;return date&&!Number.isNaN(date.getTime())?date.toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'}):'لم يُسجل تغيير بعد';};
const PAGE_SIZE=40;
const hasScopeState=state=>['all','selected'].includes(state?.scopeMode)&&typeof state?.scopeConfigured==='boolean'&&Array.isArray(state?.eligibleUsers)&&Array.isArray(state?.selectedUserIds);
const scopeStatus=user=>user.effectiveEnforced===true?'سعر إلزامي':user.reason==='override'?'بيع حر بصلاحية':user.reason==='outside_scope'?'بيع حر · خارج النطاق':user.reason==='disabled'?'الإلزام متوقف':'بانتظار التحديث';
export default function WholesalePricing({profile}){
 const allowed=canManageWholesalePricing(profile),userId=profile?.id;
 const [data,setData]=useState(null),[drafts,setDrafts]=useState({}),[query,setQuery]=useState(''),[filter,setFilter]=useState('available'),[limit,setLimit]=useState(PAGE_SIZE),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[pending,setPending]=useState(null),[conflict,setConflict]=useState(false),[reloadWarning,setReloadWarning]=useState(false);
 const [scopeDraft,setScopeDraft]=useState(null),[usersQuery,setUsersQuery]=useState(''),[showUsers,setShowUsers]=useState(false);
 const sequence=useRef(0),controller=useRef(null),lock=useRef(false),mounted=useRef(true),liveUser=useRef(userId);liveUser.current=userId;
 const products=useMemo(()=>availableWholesalePriceProducts(data?.products),[data?.products]),dirtyRows=products.filter(row=>wholesalePriceChanged(row,drafts[row.id])),dirtyCount=dirtyRows.length;
 const rowErrors=Object.fromEntries(dirtyRows.map(row=>[row.id,wholesalePriceValidation(drafts[row.id])]).filter(([,message])=>message));
 const frozen=loading||busy||!!pending||conflict||!data;
 const scopeReady=hasScopeState(data),scope=scopeDraft||wholesaleScopeDraft(data),scopeDirty=wholesaleScopeChanged(data,scopeDraft),scopeNeedsSave=scopeReady&&(!data.scopeConfigured||scopeDirty),scopeError=wholesaleScopeValidation(scope,data?.eligibleUsers),scopeUsers=(data?.eligibleUsers||[]).filter(user=>!usersQuery||normalizeSearch(user.name).includes(normalizeSearch(usersQuery)));
 const load=useCallback(async()=>{
  if(!allowed||lock.current)return;
  const request=++sequence.current;controller.current?.abort();const nextController=new AbortController();controller.current=nextController;
  setLoading(true);setError('');const timer=setTimeout(()=>nextController.abort(),15000);
  try{
   const result=await supabase.rpc('solar_wholesale_pricing',{action:'state'}).abortSignal(nextController.signal);
   if(request!==sequence.current||liveUser.current!==userId)return;
   if(result.error)throw result.error;
   if(!result.data?.canManage||result.data.currency!=='IQD'||!Array.isArray(result.data.products))throw new Error('تعذر تحميل أسعار الجملة ضمن صلاحيات حسابك.');
   setData(result.data);setDrafts({});setScopeDraft(null);setConflict(false);setReloadWarning(false);setLimit(PAGE_SIZE);
  }catch(failure){if(request===sequence.current&&liveUser.current===userId){setData(null);setError(nextController.signal.aborted?'تأخر تحميل أسعار الجملة. تحقق من الاتصال وحاول مجدداً.':failure.message||'تعذر تحميل أسعار بيع الجملة.');}}
  finally{clearTimeout(timer);if(request===sequence.current&&liveUser.current===userId)setLoading(false);}
 },[allowed,userId]);
 useEffect(()=>{mounted.current=true;setData(null);setDrafts({});setScopeDraft(null);setUsersQuery('');setShowUsers(false);setNotice('');setPending(readWholesalePriceAttempt(userId));setConflict(false);setReloadWarning(false);void load();return()=>{mounted.current=false;++sequence.current;controller.current?.abort();};},[load,userId]);
 useEffect(()=>{setLimit(PAGE_SIZE);},[query,filter]);
 const matches=useMemo(()=>{
  const needle=normalizeSearch(query);
  return products.filter(row=>(!needle||normalizeSearch([row.name,row.code,row.brand,row.category].join(' ')).includes(needle))&&(filter==='active'?(drafts[row.id]?.enabled??row.enabled):filter==='changed'?wholesalePriceChanged(row,drafts[row.id]):true));
 },[products,query,filter,drafts]);
 function changeRow(row,patch){
  if(frozen)return;
  setDrafts(previous=>{const next={...(previous[row.id]||wholesalePriceDraft(row)),...patch};if(!wholesalePriceChanged(row,next)){const copy={...previous};delete copy[row.id];return copy;}return {...previous,[row.id]:next};});
  setError('');setNotice('');
 }
 function changeScope(patch){if(frozen)return;setScopeDraft(previous=>({...(previous||wholesaleScopeDraft(data)),...patch}));setError('');setNotice('');}
 function changeScopeUser(id,checked){changeScope({userIds:checked?[...new Set([...scope.userIds,id])]:scope.userIds.filter(value=>value!==id)});}
 function saveScope(){if(frozen||!scopeNeedsSave)return;if(scopeError){setError(scopeError);return;}void write('scope',wholesaleScopePayload(scope,data.revision));}
 function reload(){if(busy||pending)return;if(Object.keys(drafts).length||scopeDirty){setReloadWarning(true);return;}void load();}
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
   if(attempt.action==='scope'&&!hasScopeState(result.data))throw new Error('لم يصل تأكيد كامل لحفظ المستخدمين المشمولين بالتسعير.');
   clearWholesalePriceAttempt(userId,attempt.id);
   if(!mounted.current||liveUser.current!==userId)return;
   setPending(null);setData(result.data);setConflict(false);setReloadWarning(false);
   if(attempt.action==='save')setDrafts(previous=>{const next={...previous};for(const item of attempt.payload.items)delete next[item.productId];return next;});
   if(attempt.action==='scope')setScopeDraft(null);
   setNotice(wholesalePriceSaveNotice(attempt.action,attempt.payload,result.data));
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
  <header className="wpHero"><div className="wpHeroHeading"><span className="wpHeroIcon"><AppIcon name="tag" size={25}/></span><div><h2>أسعار بيع الجملة</h2><p>أسعار المواد المتوفرة في مخازنك المسموحة.</p></div></div><span className="wpCurrency">دينار عراقي · IQD</span></header>
  {error&&<p className="wpAlert" role="alert">{error}</p>}{notice&&<p className="wpSuccess" role="status">{notice}</p>}
  {pending&&<div className="wpPending" role="status"><span>يوجد طلب حفظ لم يتأكد بعد. تبقى بيانات الطلب ثابتة حتى تأكيد النتيجة.</span><button type="button" disabled={busy||loading} onClick={()=>write(pending.action,pending.payload)}>{busy?'جاري التأكيد…':'تأكيد حفظ أسعار الجملة السابق'}</button></div>}
  {loading?<div className="wpLoading" role="status"><AppIcon name="refresh" size={19}/>جاري تحميل المواد والأسعار…</div>:!data?<div className="wpEmpty"><p>لم تُحمّل قائمة الأسعار.</p><button type="button" onClick={()=>void load()}><AppIcon name="refresh" size={17}/>إعادة التحميل</button></div>:<>
   <section className={'wpPolicy'+(data.enabled?' on':'')} aria-label="حالة التسعير الإلزامي للجملة">
    <div className="wpPolicyHead"><span className="wpPolicyTitle"><i className="wpPolicyDot"/>{data.enabled?'الأسعار الإلزامية مفعّلة':'الأسعار الإلزامية متوقفة'}</span><button type="button" className="wpPolicyButton" aria-label={data.enabled?'إيقاف الأسعار الإلزامية':'تشغيل الأسعار الإلزامية'} disabled={frozen||scopeDirty} onClick={()=>write('toggle',{enabled:!data.enabled,expectedRevision:data.revision})}><AppIcon name="power" size={17}/>{data.enabled?'إيقاف الإلزام':'تشغيل الإلزام'}</button></div>
    {scopeReady&&<fieldset className="wpScope" disabled={frozen}>
     <legend>تطبيق الأسعار على</legend>
     <div className="wpScopeModes">{[['all','جميع المستخدمين'],['selected','مستخدمون محددون']].map(([mode,label])=><label key={mode} className={scope.mode===mode?'selected':''}><input type="radio" name="wholesale-pricing-scope" value={mode} checked={scope.mode===mode} onChange={()=>changeScope({mode})}/><span>{label}</span></label>)}</div>
     <p className="wpScopeHint">عند حفظ النطاق، يلتزم المشمولون بالأسعار عند التشغيل، حتى الأدمن وأصحاب صلاحية البيع الحر. غير المشمولين يبقون على البيع الحر.</p>
     <details className="wpScopePeople" open={scope.mode==='selected'||showUsers} onToggle={event=>setShowUsers(event.currentTarget.open)}>
      <summary>المستخدمون وحالة التطبيق <span>{money(data.eligibleUsers.length)}</span></summary>
      <div className="wpScopeListHead"><small>الحالة المحفوظة حالياً</small>{data.eligibleUsers.length>6&&<input aria-label="البحث في مستخدمي تسعير الجملة" value={usersQuery} onChange={event=>setUsersQuery(event.target.value)} placeholder="ابحث باسم المستخدم…"/>}</div>
      <div className="wpScopeUsers">{scopeUsers.map(user=><label key={user.id} className={'wpScopeUser'+(scope.mode==='selected'&&scope.userIds.includes(user.id)?' checked':'')}>
       {scope.mode==='selected'&&<input type="checkbox" aria-label={'تطبيق الأسعار على — '+user.name} checked={scope.userIds.includes(user.id)} onChange={event=>changeScopeUser(user.id,event.target.checked)}/>}
       <span className="wpScopeUserName">{user.name}{user.isAdmin&&<small>إدارة البرنامج</small>}</span><span className={'wpScopeStatus '+(user.effectiveEnforced?'required':'free')}>{scopeStatus(user)}</span>
      </label>)}</div>
      {!scopeUsers.length&&<p className="wpScopeEmpty">{usersQuery?'لا يوجد مستخدم مطابق للبحث.':'لا يوجد مستخدم متاح لبيع الجملة حالياً.'}</p>}
     </details>
     {scopeError&&scope.mode==='selected'&&<p className="wpScopeError" role="status">{scopeError}</p>}
     {scopeNeedsSave&&<div className="wpScopeSave"><span>{data.scopeConfigured?'اختيارك غير محفوظ. احفظه قبل تغيير حالة الإلزام.':'لم يُعتمد النطاق بعد؛ استثناءات الأدمن والبيع الحر السابقة ما زالت سارية لحين الاعتماد.'}</span><div>{scopeDraft&&<button type="button" onClick={()=>setScopeDraft(null)}>إلغاء التعديل</button>}<button type="button" className="primary" aria-label="حفظ نطاق تطبيق أسعار الجملة" disabled={!!scopeError} onClick={saveScope}>{busy?'جاري الحفظ…':data.scopeConfigured?'حفظ نطاق التطبيق':'اعتماد نطاق التطبيق'}</button></div></div>}
    </fieldset>}
    <details className="wpPolicyDetails"><summary>كيف يُطبّق التسعير؟</summary><p>عند التشغيل، يُطبّق الحد الأدنى على المواد المحددة بحسب حالة كل مستخدم. الإيقاف ونفاد الكمية يحتفظان بالأسعار والاختيارات.</p></details><div className="wpPolicyMeta"><span>آخر تعديل: <b>{dateLabel(data.updatedAt)}</b></span>{data.updatedByName&&<span>بواسطة: <b>{data.updatedByName}</b></span>}</div>
   </section>
   <div className="wpSummary"><div><span>المواد المتوفرة</span><strong>{money(products.length)}</strong></div><div><span>مواد بسعر محفوظ</span><strong>{money(products.filter(row=>row.minPrice!=null).length)}</strong></div><div><span>تعديلات غير محفوظة</span><strong>{money(dirtyCount)}</strong></div></div>
   <form onSubmit={save}>
    <section className="wpCatalog"><header className="wpCatalogHead"><h3>المواد المتوفرة</h3><div className="wpCatalogActions"><button type="button" className="wpCatalogRefresh" aria-label="تحديث أسعار الجملة" title="تحديث" disabled={busy||!!pending} onClick={reload}><AppIcon name="refresh" size={17}/></button><button type="submit" className="wpQuickSave" aria-label="حفظ الأسعار" disabled={frozen||!dirtyCount||Object.keys(rowErrors).length>0}><AppIcon name={busy?'refresh':'check'} size={17}/>{busy?'جاري الحفظ…':'حفظ'}</button></div></header>
     {reloadWarning&&<div className="wpReloadWarning"><span>تحديث القائمة يلغي تعديلاتك غير المحفوظة ويجلب آخر الأسعار المعتمدة.</span><div><button type="button" onClick={()=>void load()}>تحديث وإلغاء تعديلاتي</button><button type="button" onClick={()=>setReloadWarning(false)}>الاحتفاظ بتعديلاتي</button></div></div>}
     <div className="wpFilters"><label className="wpSearch"><AppIcon name="search" size={18}/><input aria-label="البحث في أسعار بيع الجملة" value={query} onChange={event=>setQuery(event.target.value)} placeholder="ابحث باسم المادة أو الكود أو البراند…"/></label><label className="wpFilterSelect">عرض<select aria-label="تصفية مواد أسعار الجملة" value={filter} onChange={event=>setFilter(event.target.value)}><option value="available">المتوفر بالمخزن</option><option value="active">المحدد للتطبيق</option><option value="changed">التعديلات الحالية</option></select></label><span className="wpFilterCount">{money(matches.length)} مادة</span></div>
     {!matches.length?<div className="wpEmpty"><AppIcon name="package" size={25}/><p>{query||filter!=='available'?'لا توجد مواد متوفرة مطابقة للبحث والتصفية.':'لا توجد مواد بكميات متوفرة ضمن مخازنك المسموحة.'}</p></div>:<div className="wpTableWrap"><table className="wpTable"><thead><tr><th scope="col">المادة</th><th scope="col">المتوفر</th><th scope="col">الكلفة · د.ع</th><th scope="col">سعر البيع الأدنى</th><th scope="col">التطبيق</th></tr></thead><tbody>{matches.slice(0,limit).map(row=>{
      const draft=drafts[row.id]||wholesalePriceDraft(row),changed=wholesalePriceChanged(row,draft),disabled=frozen||(!changed&&dirtyCount>=WHOLESALE_PRICE_BATCH_LIMIT),inputId='wholesale-minimum-'+row.id;
      return <tr key={row.id} className={changed?'isDirty':''}><td><span className="wpProductName">{row.name}</span><span className="wpProductMeta">{[row.code&&'كود: '+row.code,row.brand,row.category].filter(Boolean).join(' · ')}</span>{row.updatedAt&&<small className="wpProductMeta">{dateLabel(row.updatedAt)}{row.updatedByName?' · '+row.updatedByName:''}</small>}{changed&&<span className="wpRowChanged">غير محفوظ</span>}</td><td data-label="المتوفر"><span className="wpQty" dir="ltr">{money(row.qty)}</span></td><td data-label="الكلفة"><span className="wpCost" dir="ltr">{money(row.cost)}<small>د.ع</small></span></td><td className="wpPriceCell"><label htmlFor={inputId} className="wpPriceLabel">سعر البيع الأدنى · د.ع</label><div className="wpPriceInput"><MoneyInput id={inputId} aria-label={'سعر البيع الأدنى — '+row.name} value={draft.minPrice} onChange={minPrice=>changeRow(row,{minPrice})} disabled={disabled} placeholder="غير محدد" aria-invalid={!!rowErrors[row.id]} aria-describedby={rowErrors[row.id]?'wholesale-error-'+row.id:undefined}/><span>د.ع</span></div>{rowErrors[row.id]&&<p className="wpRowError" id={'wholesale-error-'+row.id}>{rowErrors[row.id]}</p>}</td><td><label className="wpApply"><input type="checkbox" aria-label={'تطبيق الحد الأدنى — '+row.name} checked={draft.enabled} onChange={event=>changeRow(row,{enabled:event.target.checked})} disabled={disabled}/><span>تطبيق الحد الأدنى</span></label></td></tr>;
     })}</tbody></table></div>}
     {matches.length>limit&&<button type="button" className="wpLoadMore" onClick={()=>setLimit(value=>value+PAGE_SIZE)}>عرض {Math.min(PAGE_SIZE,matches.length-limit)} مادة أخرى</button>}
    </section>
    <div className="wpSaveBar"><div><b>{dirtyCount?dirtyCount+' مادة بانتظار الحفظ':'الأسعار المحفوظة جاهزة'}</b><small>{dirtyCount>=WHOLESALE_PRICE_BATCH_LIMIT?'احفظ هذه التعديلات قبل تعديل مواد أخرى.':'السعر الفارغ يبقى غير محدد حتى تختاره وتحفظه.'}</small></div><button type="submit" aria-label="حفظ الأسعار من أسفل القائمة" disabled={frozen||!dirtyCount||Object.keys(rowErrors).length>0}><AppIcon name={busy?'refresh':'check'} size={18}/>{busy?'جاري الحفظ…':'حفظ التعديلات'}</button></div>
   </form>
   <p className="wpPrivateNote">الكلفة المعروضة للمراجعة الداخلية. تغيير هذه الإعدادات لا يغيّر الفواتير السابقة.</p>
  </>}
 </section>;
}
