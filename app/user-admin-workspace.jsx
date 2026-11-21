'use client';
import {useEffect,useRef,useState} from 'react';
import AppIcon from './app-icons';
import PhoneActions from './phone-actions';
import {supabase} from './supabase';
import {isAdministrator} from './access-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {userDisplayName} from './user-name-utils.mjs';
import {userDetailsRequest} from './user-admin-details.mjs';
import {
 accountPermissions,accountRole,changeAccountPermission,fieldRoleActions,
 permissionGroups,resetAccountPermissions,roleLabels,selectedPermissionLabels,warehouseDirections
} from './user-admin-permissions.mjs';
import './user-admin-workspace.css';

const stages=['بيانات الحساب','صلاحيات الأقسام','المخازن','مراجعة الحساب'];
const noDirections={fromPrimary:false,toPrimary:false,other:false};

async function userAction(body){
 const {data,error}=await supabase.functions.invoke('solar-admin-users',{body});
 if(error){
  let failure;
  try{failure=await error.context?.json();}catch{}
  const status=error.context?.status;
  throw Object.assign(new Error(failure?.error||'تعذر تأكيد العملية. تحقق من الاتصال وأعد المحاولة.'),{uncertain:!status||status>=500});
 }
 if(!data||typeof data.ok!=='boolean')throw Object.assign(new Error('لم يصل تأكيد العملية. أعد المحاولة.'),{uncertain:true});
 if(!data.ok)throw new Error(data.error||'تعذر تنفيذ العملية.');
 return data;
}

function safeWarehouses(user){
 const w=user?.warehouse;
 if(!w||!Array.isArray(w.ids)||typeof w.all!=='boolean')return null;
 return {all:w.all,ids:[...w.ids],transferDirections:{...noDirections,...w.transferDirections}};
}
function identity(user){
 return {username:user?.username||'',display_name:user?.display_name||'',honorific:user?.honorific||'',phone:user?.phone||'',password:''};
}
function warehouseSummary(role,access,warehouses){
 if(role==='admin')return 'جميع المخازن بحكم دور المدير';
 if(role==='installer')return 'المواد المرفقة بمهام التنصيب المسندة إليه';
 if(!access)return 'تعذر التحقق من مخازن الحساب';
 if(access.all)return 'جميع المخازن الحالية والجديدة';
 if(!access.ids.length)return 'لم يُحدّد مخزن';
 return access.ids.map(id=>warehouses.find(w=>String(w.id)===String(id))?.name||'مخزن رقم '+id).join('، ');
}

function Confirmation({title,children,actionLabel,busy,onCancel,onConfirm}){
 const ref=useRef(null);
 useEffect(()=>{
  const previous=document.activeElement,dialog=ref.current;
  dialog.showModal();dialog.querySelector('button')?.focus();
  return ()=>{dialog.close();if(previous?.isConnected)previous.focus();};
 },[]);
 return <dialog className="uaConfirm" ref={ref} aria-labelledby="ua-confirm-title" onCancel={e=>{e.preventDefault();if(!busy)onCancel();}}>
  <h2 id="ua-confirm-title">{title}</h2>{children}
  <div className="uaActions"><button type="button" disabled={busy} onClick={onCancel}>إلغاء</button><button type="button" className="uaDanger" disabled={busy} onClick={onConfirm}>{busy?'جاري التنفيذ…':actionLabel}</button></div>
 </dialog>;
}

function PermissionStep({role,value,onChange,onReset}){
 if(role!=='user')return <div className="uaRolePermissions">
  <div className="uaRoleIcon"><AppIcon name={role==='admin'?'shield':role==='warehouse'?'warehouse':'tools'}/></div>
  <h3>{roleLabels[role]}</h3><ul>{fieldRoleActions[role].map(label=><li key={label}>{label}</li>)}</ul>
  {role!=='admin'&&<label className="uaCheck"><input type="checkbox" data-permission="layoutCustomize" checked={value.layoutCustomize===true} onChange={e=>onChange({...value,layoutCustomize:e.target.checked})}/>تخصيص ترتيب وحجم أقسامه</label>}
 </div>;
 return <>
  <div className="uaPermissionBar"><span>الصلاحيات المحددة <b>{selectedPermissionLabels(role,value).length}</b></span><button type="button" className="uaQuietDanger" onClick={onReset}>تصفير الصلاحيات</button></div>
  <div className="uaPermissionGroups">{permissionGroups.map(group=>{
   const selected=group.options.filter(([key])=>value[key]===true).length;
   return <details key={group.title} className="uaPermissionGroup">
    <summary><AppIcon name={group.icon} size={19}/><b>{group.title}</b><small>{selected} من {group.options.length}</small><AppIcon name="chevron" size={15}/></summary>
    <div>{group.options.map(([key,label])=><label className="uaCheck" key={key}><input type="checkbox" data-permission={key} checked={value[key]===true} onChange={e=>onChange(changeAccountPermission(value,key,e.target.checked))}/>{label}</label>)}</div>
   </details>;
  })}</div><p className="uaHint">صلاحيات المبيعات والعملاء والتسديدات والأرباح تخص سجلات المستخدم.</p>
 </>;
}

function WarehouseStep({role,value,warehouses,onChange}){
 if(role==='admin'||role==='installer')return <p className="uaInfo"><AppIcon name="warehouse" size={20}/>{warehouseSummary(role,value,warehouses)}</p>;
 if(!value)return <p className="uaError" role="alert">تعذر تحميل صلاحيات مخازن هذا المستخدم. ارجع إلى الدليل وحدّث القائمة.</p>;
 function checked(id){return value.ids.some(v=>String(v)===String(id));}
 function changeId(id){
  const ids=checked(id)?value.ids.filter(v=>String(v)!==String(id)):[...value.ids,id];
  onChange({...value,ids});
 }
 return <div className="uaWarehouses">
  <fieldset className="uaWarehouseScope"><legend>نطاق المخازن</legend>
   <label><input type="radio" name="ua-warehouse-scope" checked={value.all} onChange={()=>onChange({...value,all:true})}/>جميع المخازن الحالية والجديدة</label>
   <label><input type="radio" name="ua-warehouse-scope" checked={!value.all} onChange={()=>onChange({...value,all:false})}/>مخازن محددة</label>
  </fieldset>
  {!value.all&&<fieldset><legend>المخازن المسموحة</legend><div className="uaWarehouseList">{warehouses.filter(w=>w.active||checked(w.id)).map(w=><label key={w.id} className="uaCheck"><input type="checkbox" checked={checked(w.id)} onChange={()=>changeId(w.id)}/>{w.name}{!w.active&&<small>موقوف</small>}</label>)}</div>{!warehouses.length&&<p className="uaHint">لا توجد مخازن معرفة.</p>}</fieldset>}
  <fieldset><legend>اتجاهات نقل المواد</legend>
   <div className="uaWarehouseList">{warehouseDirections.map(([key,label])=><label key={key} className="uaCheck"><input type="checkbox" checked={value.transferDirections[key]===true} onChange={e=>onChange({...value,transferDirections:{...value.transferDirections,[key]:e.target.checked}})}/>{label}</label>)}</div>
  </fieldset>
 </div>;
}

function Wizard({editing,warehouses,actorId,onExit,onSaved}){
 const [target,setTarget]=useState(editing),[info,setInfo]=useState(()=>identity(editing)),[role,setRole]=useState(()=>accountRole(editing));
 const [perms,setPerms]=useState(()=>accountPermissions(editing?.permissions)),[warehouse,setWarehouse]=useState(()=>safeWarehouses(editing)),[active,setActive]=useState(editing?editing.active:true);
 const [stage,setStage]=useState(0),[busy,setBusy]=useState(false),[error,setError]=useState(''),[confirm,setConfirm]=useState(''),[uncertain,setUncertain]=useState(false);
 const pending=useRef(null),lock=useRef(false),heading=useRef(null);
 const isSelf=target?.id===actorId;
 const [changePassword,setChangePassword]=useState(false);
 const initialDetails=identity(target);
 const changedDetails=changePassword||Object.keys(info).some(key=>key!=='password'&&String(initialDetails[key]||'')!==info[key]);
 const changedAccess=role!==accountRole(target)||JSON.stringify(perms)!==JSON.stringify(accountPermissions(target?.permissions))||
  JSON.stringify(warehouse)!==JSON.stringify(safeWarehouses(target))||!!target&&active!==target.active;
 const edited=target?changedDetails||changedAccess:Object.values(info).some(Boolean);
 useEffect(()=>{if(!edited)return;const guard=e=>{e.preventDefault();e.returnValue='';};window.addEventListener('beforeunload',guard);return()=>window.removeEventListener('beforeunload',guard);},[edited]);
 function move(next){if(lock.current)return;setError('');setStage(next);}
 useEffect(()=>{heading.current?.focus({preventScroll:true});heading.current?.scrollIntoView({block:'start'});},[stage]);
 function field(name,value){setInfo(old=>({...old,[name]:value}));setError('');}
 function leave(){if(lock.current)return;if(edited||uncertain)setConfirm('leave');else onExit();}
 async function mutate(body,receive){
  if(lock.current)return;
  const attempt=pending.current||{id:crypto.randomUUID(),body};
  pending.current=attempt;lock.current=true;setBusy(true);setError('');
  try{
   const reply=await userAction({...attempt.body,request_id:attempt.id});
   receive(reply);pending.current=null;setUncertain(false);
  }catch(err){
   if(!err.uncertain){pending.current=null;setUncertain(false);}else setUncertain(true);
   setError(err.message);
  }finally{lock.current=false;setBusy(false);}
 }
 function details(e){
  e.preventDefault();
  if(target&&!changedDetails&&!uncertain){move(1);return;}
  let body;
  try{body=userDetailsRequest(info,target,changePassword);}catch(err){setError(err.message);return;}
  void mutate(body,({user})=>{
   if(!user?.id||!user.token)throw Object.assign(new Error('لم يصل تأكيد حفظ الحساب. أعد المحاولة.'),{uncertain:true});
   setTarget(user);setInfo(identity(user));setChangePassword(false);if(!target)setWarehouse(safeWarehouses(user));setStage(1);
  });
 }
 const currentLabels=selectedPermissionLabels(role,perms);
 function finalize(){
  if(!target?.id||!target.token||(!warehouse&&!['admin','installer'].includes(role))){setError('تعذر تأكيد إعدادات المستخدم. حدّث دليل المستخدمين.');return;}
  const warehouseChanged=JSON.stringify(warehouse)!==JSON.stringify(safeWarehouses(target));
  const body={action:'finalize',user_id:target.id,token:target.token,role,permissions:perms,active,warehouse:warehouseChanged&&!['admin','installer'].includes(role)?warehouse:null};
  void mutate(body,({user})=>{
   if(user?.id!==target.id)throw Object.assign(new Error('لم يصل تأكيد حفظ الإعدادات. أعد المحاولة.'),{uncertain:true});
   onSaved('تم حفظ إعدادات '+userDisplayName(user)+' وحسابه '+(user.active?'فعّال.':'موقوف.'));
  });
 }
 return <section className="userAdminWizard" data-step={stage+1}>
  <header className="uaTitle"><div><span>{editing?'تعديل مستخدم':'إضافة مستخدم'}</span><h1>{target?userDisplayName(target):'حساب مستخدم جديد'}</h1></div><button type="button" disabled={busy} onClick={leave}>رجوع إلى الدليل</button></header>
  <ol className="uaSteps" aria-label="خطوات إعداد المستخدم">{stages.map((label,i)=><li key={label} aria-current={stage===i?'step':undefined} data-done={i<stage}><span>{i<stage?<AppIcon name="check" size={15}/>:i+1}</span>{label}</li>)}</ol>
  <section className="uaPanel"><h2 ref={heading} tabIndex={-1}>{stages[stage]}</h2>
   {stage===0&&<form onSubmit={details}><fieldset className="uaDetailsGrid" disabled={busy||uncertain}>
    <label>الاسم الظاهر<input aria-label="الاسم الظاهر" value={info.display_name} maxLength={100} autoComplete="off" onChange={e=>field('display_name',e.target.value)} required/></label>
    <label>اسم المستخدم<input aria-label="اسم المستخدم" value={info.username} dir="ltr" autoCapitalize="none" maxLength={30} autoComplete="off" onChange={e=>field('username',e.target.value)} required/></label>
    <label>رقم هاتف المستخدم<input aria-label="رقم هاتف المستخدم" value={info.phone} dir="ltr" type="tel" maxLength={30} onChange={e=>field('phone',e.target.value)} required={!target||!!target.phone}/></label>
    <label>الكنية أو الصفة <small>اختياري</small><input aria-label="كنية المستخدم" value={info.honorific} list="ua-honorifics" maxLength={50} onChange={e=>field('honorific',e.target.value)}/><datalist id="ua-honorifics"><option value="المهندس"/><option value="الإداري"/><option value="الحاج"/><option value="السيد"/></datalist>{info.honorific&&<small>{userDisplayName(info)}</small>}</label>
    {target&&<label className="uaCheck"><input type="checkbox" checked={changePassword} onChange={e=>{setChangePassword(e.target.checked);field('password','');}}/>تغيير كلمة المرور</label>}
    {(!target||changePassword)&&<label>{target?'كلمة المرور الجديدة':'كلمة المرور'}<input aria-label={target?'كلمة المرور الجديدة':'كلمة المرور'} type="password" dir="ltr" autoComplete="new-password" value={info.password} minLength={6} onChange={e=>field('password',e.target.value)} required/></label>}
   </fieldset>{!target&&<p className="uaHint">يُحفظ الحساب موقوفاً إلى أن تراجع الصلاحيات والمخازن وتختار تفعيله.</p>}
   {error&&<p role="alert" className="uaError">{error}</p>}<div className="uaActions"><button type="submit" disabled={busy} className="uaPrimary">{busy?'جاري الحفظ…':'حفظ البيانات والمتابعة'}</button></div></form>}
   {stage===1&&<><div className="uaRoleSelect"><label>نوع المستخدم<select aria-label="نوع المستخدم" value={role} disabled={isSelf} onChange={e=>setRole(e.target.value)}>{Object.entries(roleLabels).map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></label></div><PermissionStep role={role} value={perms} onChange={setPerms} onReset={()=>setConfirm('reset')}/></>}
   {stage===2&&<WarehouseStep role={role} value={warehouse} warehouses={warehouses} onChange={setWarehouse}/>}
   {stage===3&&<><dl className="uaReview"><div><dt>اسم الدخول</dt><dd dir="auto">{target.username}</dd></div><div><dt>نوع المستخدم</dt><dd>{roleLabels[role]}</dd></div><div><dt>المخازن</dt><dd>{warehouseSummary(role,warehouse,warehouses)}</dd></div>
    {warehouse&&!['admin','installer'].includes(role)&&<div><dt>اتجاهات النقل</dt><dd>{warehouseDirections.filter(([key])=>warehouse.transferDirections[key]).map(([,label])=>label).join('، ')||'لا يوجد نقل مسموح'}</dd></div>}
    </dl><details className="uaReviewPermissions"><summary>الصلاحيات المحددة ({currentLabels.length})</summary>{currentLabels.length?<ul>{currentLabels.map(label=><li key={label}>{label}</li>)}</ul>:<p>لم تُحدّد صلاحيات للأقسام.</p>}</details>
    <fieldset className="uaAccountStatus" disabled={isSelf||busy||uncertain}><legend>حالة الحساب بعد الحفظ</legend><label><input type="radio" name="ua-active" checked={active} onChange={()=>setActive(true)}/>فعّال</label><label><input type="radio" name="ua-active" checked={!active} onChange={()=>setActive(false)}/>موقوف</label></fieldset>
   </>}
   {stage>0&&<>{error&&<p className="uaError" role="alert">{error}</p>}<div className="uaActions"><button type="button" disabled={busy||uncertain} onClick={()=>move(stage-1)}>السابق</button><button type="button" className="uaPrimary" disabled={busy||(stage===2&&!warehouse&&!['admin','installer'].includes(role))} onClick={()=>stage===3?finalize():move(stage+1)}>{busy?'جاري الحفظ…':stage===1?'مراجعة المخازن':stage===2?'مراجعة الحساب':'حفظ إعدادات المستخدم'}</button></div></>}
  </section>
  {confirm==='reset'&&<Confirmation title="تصفير صلاحيات الأقسام؟" actionLabel="تأكيد التصفير" onCancel={()=>setConfirm('')} onConfirm={()=>{setPerms(resetAccountPermissions(perms));setConfirm('');}}><p>تُزال صلاحيات الأقسام المحددة لهذا المستخدم عند حفظ المراجعة النهائية. تبقى بيانات حسابه ومخازنه وحالته محفوظة.</p></Confirmation>}
  {confirm==='leave'&&<Confirmation title="الرجوع إلى دليل المستخدمين؟" actionLabel="الرجوع إلى الدليل" onCancel={()=>setConfirm('')} onConfirm={onExit}><p>{target?'تبقى بيانات الحساب المحفوظة. تفقد أي تغييرات لم تحفظها في هذه الخطوات.':'تفقد البيانات التي أدخلتها ولم تحفظها.'}</p></Confirmation>}
 </section>;
}

function UserDirectory({users,loading,query,onQuery,status,onStatus,onNew,onEdit,onRemove,actorId,onRefresh}){
 const q=normalizeSearch(query);
 const shown=users.filter(user=>(status==='all'||(status==='active')===user.active)&&normalizeSearch([userDisplayName(user),user.username,user.phone].filter(Boolean).join(' ')).includes(q));
 return <>
  <header className="uaTitle"><div><h1>المستخدمون والصلاحيات</h1><p>إدارة حسابات الفريق ومخازن العمل.</p></div><button type="button" className="uaPrimary" onClick={onNew} disabled={loading}><AppIcon name="add" size={18}/>إضافة مستخدم</button></header>
  <section className="uaPanel uaDirectory" aria-label="دليل المستخدمين" aria-busy={loading}>
   <header><h2>دليل المستخدمين</h2><button type="button" disabled={loading} onClick={onRefresh} aria-label="تحديث دليل المستخدمين"><AppIcon name="refresh" size={18}/>تحديث</button></header>
   <div className="uaFilters"><label className="uaSearch"><AppIcon name="search" size={18}/><input aria-label="بحث المستخدمين" type="search" value={query} onChange={e=>onQuery(e.target.value)} placeholder="الاسم أو الهاتف أو اسم الدخول"/></label><label className="uaFilter"><span>حالة الحساب</span><select aria-label="حالة الحساب" value={status} onChange={e=>onStatus(e.target.value)}><option value="all">جميع الحالات</option><option value="active">فعّال</option><option value="inactive">موقوف</option></select></label></div>
   {loading?<p className="uaHint" role="status">جاري تحميل الحسابات…</p>:<><p className="uaCount" role="status">{shown.length} حساب</p><ul className="uaUserList">{shown.map(user=>{
    const role=accountRole(user),name=userDisplayName(user);
    return <li data-user-id={user.id} key={user.id}><div className="uaUserIdentity"><span className={'uaAvatar ua-'+role}><AppIcon name={role==='admin'?'shield':role==='warehouse'?'warehouse':role==='installer'?'tools':'user'} size={21}/></span><div><h3>{name}</h3><small><bdi dir="ltr">@{user.username||'—'}</bdi> · {roleLabels[role]}</small></div></div>
     <span className={'uaStatus '+(user.active?'uaActive':'uaInactive')}>{user.active?'فعّال':'موقوف'}</span>
     {user.phone&&<PhoneActions phone={user.phone} label={name}/>}
     <div className="uaRowActions"><button type="button" onClick={()=>onEdit(user)}><AppIcon name="edit" size={15}/>تعديل</button>
     {user.id!==actorId&&<button type="button" className="uaQuietDanger" onClick={()=>onRemove(user)}>حذف</button>}</div>
    </li>;
   })}</ul>{!shown.length&&<p className="uaEmpty">{users.length?'ماكو حساب يطابق البحث.':'لا توجد حسابات في الدليل.'}</p>}</>}
  </section>
 </>;
}

function UserAdminDirectory({profile}){
 const [users,setUsers]=useState([]),[warehouses,setWarehouses]=useState([]),[loading,setLoading]=useState(true),[error,setError]=useState(''),[notice,setNotice]=useState('');
 const [query,setQuery]=useState(''),[status,setStatus]=useState('all'),[editor,setEditor]=useState(null),[removing,setRemoving]=useState(null),[removeBusy,setRemoveBusy]=useState(false);
 const sequence=useRef(0),removeAttempt=useRef(null),removeLock=useRef(false);
 async function load(){
  const id=++sequence.current;setLoading(true);setError('');
  try{
   const data=await userAction({action:'directory'});
   if(id!==sequence.current)return false;
   if(!Array.isArray(data.users)||!Array.isArray(data.warehouses))throw new Error('تعذر قراءة دليل المستخدمين والمخازن.');
   setUsers(data.users);setWarehouses(data.warehouses);return true;
  }catch(err){if(id===sequence.current){setError(err.message);setUsers([]);setWarehouses([]);}return false;}
  finally{if(id===sequence.current)setLoading(false);}
 }
 useEffect(()=>{void load();return()=>{sequence.current++;};},[profile.id]);
 async function exit(message=''){
  setEditor(null);setNotice(message);await load();window.scrollTo({top:0,behavior:'instant'});
 }
 async function remove(){
  if(!removing||removeLock.current||removing.id===profile.id)return;
  removeLock.current=true;setRemoveBusy(true);setError('');
  const request=removeAttempt.current||{action:'remove',request_id:crypto.randomUUID(),user_id:removing.id,token:removing.token};
  removeAttempt.current=request;
  try{
   const result=await userAction(request);
   if(!['archived','deleted'].includes(result.mode))throw Object.assign(new Error('لم يصل تأكيد إزالة الحساب. أعد المحاولة.'),{uncertain:true});
   setRemoving(null);removeAttempt.current=null;
   await exit(result.mode==='deleted'?'تم حذف حساب '+userDisplayName(removing)+'.':'تمت أرشفة حساب '+userDisplayName(removing)+' وإيقاف دخوله. تبقى سجلاته المالية محفوظة.');
  }catch(err){setError(err.message);if(!err.uncertain)removeAttempt.current=null;}
  finally{removeLock.current=false;setRemoveBusy(false);}
 }
 return <div className="userAdminWorkspace" dir="rtl">
  {editor?<Wizard key={editor.user?.id||'new'} editing={editor.user} warehouses={warehouses} actorId={profile.id} onExit={()=>void exit()} onSaved={message=>void exit(message)}/>:<>
   {notice&&<p className="uaNotice" role="status"><AppIcon name="check" size={18}/>{notice}</p>}
   {error&&!removing&&<p className="uaError" role="alert">{error}</p>}
   <UserDirectory users={users} loading={loading} query={query} onQuery={setQuery} status={status} onStatus={setStatus} actorId={profile.id} onRefresh={load}
    onNew={()=>{setNotice('');setError('');setEditor({user:null});}} onEdit={user=>{setNotice('');setError('');setEditor({user});}} onRemove={user=>{setError('');setRemoving(user);removeAttempt.current=null;}}/>
  </>}
  {removing&&<Confirmation title={'حذف حساب '+userDisplayName(removing)+'؟'} actionLabel="تأكيد حذف الحساب" busy={removeBusy} onCancel={()=>{setRemoving(null);removeAttempt.current=null;setError('');void load();}} onConfirm={remove}>
   <p>يُحذف الحساب غير المرتبط بسجلات. إذا كان مرتبطاً بعمليات سابقة، يُؤرشف ويُوقَف دخوله حتى تُحفظ سجلاته.</p>{error&&<p className="uaError" role="alert">{error}</p>}
  </Confirmation>}
 </div>;
}
export default function UserAdminWorkspace({profile}){
 return isAdministrator(profile)?<UserAdminDirectory key={profile.id} profile={profile}/>:<p role="alert">إدارة المستخدمين متاحة لمدير البرنامج فقط.</p>;
}
