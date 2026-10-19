'use client';
import {useEffect,useRef,useState} from 'react';
import MoneyInput from './money-input';
import AppIcon from './app-icons';
import CompactPartyAccount from './compact-party-account';
import CustomerPaymentHistory from './customer-payment-history';
import {customerAccount,partyInitials} from './compact-party-utils.mjs';
import {canOpenPage,cashOwner} from './access-utils.mjs';
import {CustomerAccountMatch} from './reconciliation-workspace';
import {checkCustomer,customerDirectory,customerRecord,saveCustomer} from './customer-store.mjs';
import {customerMatches,customerNameKey,customerPhoneKey,filteredCustomers,validOpening} from './customer-utils.mjs';
import {accountLabel,accountEffect,money} from './reconciliation-utils.mjs';
import {warehouseDate} from './warehouse-utils.mjs';

const emptyForm=profile=>({name:'',phone:'',customerType:'system',ownerId:profile.id,opening:false,amount:'',direction:'1'});
const typeLabel=type=>type==='wholesale'?'بيع جملة':'منظومات';
export default function CustomerWorkspace({profile,staff=[],rows:sourceRows=[],onChanged,a4,onPayment,onSale,transactions=[],initialAccountId=null,initialCreate=false}){
 const [records,setRecords]=useState([]),[form,setForm]=useState(()=>emptyForm(profile)),[editing,setEditing]=useState(null),[detail,setDetail]=useState(null),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[editingId,setEditingId]=useState(null),[query,setQuery]=useState(''),[type,setType]=useState('all'),[balance,setBalance]=useState('all'),[page,setPage]=useState(1),[error,setError]=useState(''),[notice,setNotice]=useState(''),[checked,setChecked]=useState([]),[checking,setChecking]=useState(false),[checkError,setCheckError]=useState(false),[uncertain,setUncertain]=useState(false);
 const attempt=useRef(null),generation=useRef(0),panel=useRef(null),detailGeneration=useRef(0);
 const [editorOpen,setEditorOpen]=useState(()=>initialCreate&&canOpenPage(profile,'customerCreate')),[filtersOpen,setFiltersOpen]=useState(false),[paymentEdit,setPaymentEdit]=useState(null);
 const isAdmin=!!profile.is_admin,canManage=isAdmin||profile.permissions?.customers===true;
 async function load(){const n=++generation.current;setLoading(true);try{const data=await customerDirectory();if(n===generation.current)setRecords(data);}catch(e){if(n===generation.current)setError(e.message||'تعذر تحميل الزبائن. أعد التحديث.');}finally{if(n===generation.current)setLoading(false);}}
 useEffect(()=>{load();return()=>{generation.current++;};},[sourceRows]);
 useEffect(()=>{if(initialAccountId)showAccount(initialAccountId);},[initialAccountId]);
 const checkName=editing&&customerNameKey(form.name)===customerNameKey(editing.name)?'':form.name;
 const checkPhone=editing&&customerPhoneKey(form.phone)===customerPhoneKey(editing.phone)?'':form.phone;
 useEffect(()=>{let live=true;setChecked([]);setCheckError(false);if(!checkName.trim()&&!checkPhone.trim()){setChecking(false);return;}
  setChecking(true);const timer=setTimeout(()=>checkCustomer(checkName,checkPhone,editing?.id).then(result=>{if(live){setChecked(result);setChecking(false);}}).catch(()=>{if(live){setCheckError(true);setChecking(false);}}),250);
  return()=>{live=false;clearTimeout(timer);};
 },[checkName,checkPhone,editing?.id]);
 const exact=customerMatches(records,checkName,checkPhone,editing?.id);
 const duplicates=[...checked,...exact.filter(c=>!checked.some(x=>String(x.id)===String(c.id))).map(c=>({id:c.id,name:c.name,reason:'name'}))];
 const similar=form.name.trim().length>=2?filteredCustomers(records,form.name).filter(c=>String(c.id)!==String(editing?.id)&&!duplicates.some(x=>String(x.id)===String(c.id))).slice(0,3):[];
 const shown=filteredCustomers(records,query,type,balance),pages=Math.max(1,Math.ceil(shown.length/12)),currentPage=Math.min(page,pages),visible=shown.slice((currentPage-1)*12,currentPage*12);
 const signed=form.opening?Number(form.amount)*Number(form.direction):0;
 const proposedBalance=Number(editing?.balance||0)-Number(editing?.openingBalance||0)+signed;
 const change=(key,value)=>{setForm(f=>({...f,[key]:value}));setError('');setNotice('');};
 function cancel(){if(uncertain)return;setEditorOpen(false);detailGeneration.current++;setEditing(null);setForm(emptyForm(profile));setError('');setNotice('');attempt.current=null;}
 async function edit(id){
  if(busy||uncertain||!canManage)return;
  const n=++detailGeneration.current;setEditingId(id);setError('');setNotice('');
  try{const record=await customerRecord(id);if(n!==detailGeneration.current)return;setEditorOpen(true);setDetail(null);setEditing(record);setForm({name:record.name,phone:record.phone,customerType:record.customerType,ownerId:record.ownerId||profile.id,opening:Number(record.openingBalance)!==0,amount:record.openingBalance?String(Math.abs(record.openingBalance)):'',direction:record.openingBalance<0?'-1':'1'});attempt.current=null;panel.current?.scrollIntoView({behavior:'smooth',block:'start'});}
  catch(e){if(n===detailGeneration.current)setError(e.message||'تعذر فتح تعديل الزبون');}
  finally{if(n===detailGeneration.current)setEditingId(null);}
 }
 async function refresh(){if(uncertain)return;setError('');await load();if(editing)await edit(editing.id);}
 async function changed(){await load();try{await onChanged?.();}catch{setNotice('تم الحفظ. حدّث بيانات البرنامج لإظهار التغيير في بقية الأقسام.');}}
 async function submit(event){
  event.preventDefault();if(busy||duplicates.length)return;setError('');setNotice('');
  if(customerNameKey(form.name).length<2){setError('اكتب اسم الزبون كاملاً');return;}
  if(form.opening&&(form.amount===''||!validOpening(signed))){setError('أدخل مبلغاً افتتاحياً صحيحاً');return;}
  const payload={id:editing?.id||attempt.current?.id||Date.now(),name:form.name.trim(),phone:form.phone.trim(),customerType:form.customerType,ownerId:form.ownerId||profile.id,...(editing||form.opening?{openingBalance:signed}:{}),...(editing?{token:editing.token}:{})};
  if(attempt.current)attempt.current.id=payload.id;
  setBusy(true);setUncertain(false);
  try{await saveCustomer(attempt,editing?'update':'create',payload);setForm(emptyForm(profile));setEditing(null);setEditorOpen(false);setDetail(null);setNotice(editing?'تم حفظ بيانات الزبون وتعديل الرصيد الافتتاحي في الحساب.':isAdmin?'تم تسجيل الزبون ورصيده الافتتاحي.':'تم تسجيل الزبون ضمن زبائنك فقط.');await changed();}
  catch(e){setError(e.message||'تعذر تأكيد الحفظ. أعد المحاولة بنفس البيانات.');if(attempt.current){attempt.current.id=payload.id;setUncertain(true);}}
  finally{setBusy(false);}
 }
 async function showAccount(id){if(busy)return;setEditingId(id);setError('');try{setDetail(await customerRecord(id));}catch(e){setError(e.message||'تعذر فتح الحساب');}finally{setEditingId(null);}}
 async function remove(record){
  if(busy||uncertain||!canManage||!confirm('حذف الزبون '+record.name+'؟ لا يمكن حذف زبون لديه حركات حساب.'))return;
  setBusy(true);setError('');try{const latest=await customerRecord(record.id);await saveCustomer(attempt,'delete',{id:latest.id,token:latest.token});if(editing?.id===record.id)cancel();setDetail(null);setNotice('تم حذف الزبون الخالي من الحركات.');await changed();}catch(e){setError(e.message||'تعذر الحذف');if(attempt.current){setUncertain(true);setError('لم يتأكد رد الحذف. حدّث الصفحة وتحقق من وجود الزبون قبل أي عملية جديدة.');}}finally{setBusy(false);}
 }

 const alerts=<>{error&&<p className="miniAlert" role="alert">{error}</p>}{notice&&<p className="miniSuccess" role="status">{notice}</p>}</>;
 if(paymentEdit)return <div className="miniParty miniEmbedded"><CustomerPaymentHistory initialId={paymentEdit.id} initialAction={paymentEdit.action} backLabel="رجوع لحساب العميل" onBack={()=>{setPaymentEdit(null);if(detail)showAccount(detail.id);}} onChanged={async()=>{await changed();if(detail)setDetail(await customerRecord(detail.id));}}/></div>;
 if(detail&&!editorOpen)return <div>{alerts}<CompactPartyAccount key={detail.id+detail.token} account={customerAccount(detail)} a4={a4} onBack={()=>setDetail(null)} onRefresh={()=>showAccount(detail.id)} onEdit={canManage?()=>edit(detail.id):undefined} onPayment={canOpenPage(profile,detail.customerType==='wholesale'?'customerPayment':'systemPayment')?()=>onPayment?.(detail):undefined} onSale={canOpenPage(profile,detail.customerType==='wholesale'?'sale':'system')?()=>onSale?.(detail):undefined} canEditMovement={r=>r.kind==='customer_payment'&&!['opening_balance','account_reconciliation'].includes(r.mode)&&canOpenPage(profile,'customerPayment')&&(isAdmin||transactions.some(t=>String(t.id)===String(r.id)&&cashOwner(t)===profile.id))} onMovementEdit={(r,action)=>setPaymentEdit({id:r.id,action})} renderMatch={canOpenPage(profile,'customerReconcile')?()=> <CustomerAccountMatch customerId={detail.id} onSaved={async()=>{await changed();setDetail(await customerRecord(detail.id));}}/>:undefined}/></div>;
 if(editorOpen)return <section className="miniParty miniPartyEditor customerWorkspace"><header className="miniPageHead"><button type="button" className="miniIcon" aria-label="رجوع للعملاء" disabled={busy||uncertain} onClick={cancel}><AppIcon name="arrow" size={19}/></button><h1>{editing?'تعديل العميل':'إضافة زبون'}</h1><span/></header>{alerts}<div className="customerEditor" ref={panel}>   <form onSubmit={submit}><fieldset disabled={busy||uncertain}>
    <label>اسم الزبون <input aria-label="اسم الزبون" value={form.name} onChange={e=>change('name',e.target.value)} maxLength={150} placeholder="الاسم الكامل للزبون" autoFocus required/></label>
    <label>رقم الهاتف<input aria-label="رقم هاتف الزبون" value={form.phone} onChange={e=>change('phone',e.target.value)} maxLength={40} inputMode="tel" dir="ltr" placeholder="07xx xxx xxxx"/></label>
    {form.name.trim()||form.phone.trim()?<div className={'customerDuplicate '+(duplicates.length?'exists':'')} aria-live="polite">{checking?'جاري التحقق من التسجيل…':duplicates.length?<><strong>هذا الزبون مسجّل مسبقاً</strong><span>{duplicates.some(d=>d.reason==='phone')?'رقم الهاتف مرتبط بزبون مسجّل.':'يوجد زبون بنفس الاسم؛ استخدم الحساب المسجّل.'}</span>{canManage&&duplicates.filter(d=>d.id!=null).slice(0,2).map(d=><button type="button" key={d.id} onClick={()=>edit(d.id)}>فتح الزبون المسجّل: {d.name}</button>)}{duplicates.some(d=>d.id==null)&&<span>الحساب لدى مستخدم آخر؛ راجع الإدارة.</span>}</>:checkError?'تعذر التحقق المباشر؛ سيُفحص التكرار عند الحفظ.':form.name.trim()?'✓ لا يوجد تسجيل مطابق ضمن نتائج الفحص.':'ابحث بالاسم أو الهاتف قبل الإضافة.'}</div>:null}
    {canManage&&!duplicates.length&&similar.length>0&&<div className="customerSimilar"><b>أسماء مشابهة — تأكد قبل الإضافة</b>{similar.map(c=><button type="button" key={c.id} onClick={()=>edit(c.id)}>{c.name}<span>فتح الحساب ←</span></button>)}</div>}
    <label>نوع الزبون<select aria-label="نوع الزبون" value={form.customerType} onChange={e=>change('customerType',e.target.value)}><option value="system">مفرد · منظومات</option><option value="wholesale">جملة · بيع جملة</option></select></label>
    {!isAdmin&&<div className="customerOwnershipNote"><strong>يتبع حسابك تلقائياً</strong><span>{profile.display_name||profile.username}</span></div>}{isAdmin&&<label>المستخدم المسؤول<select aria-label="المستخدم المسؤول عن الزبون" value={form.ownerId} onChange={e=>change('ownerId',e.target.value)}>{[...new Map([{id:profile.id,display_name:profile.display_name||profile.username||'حسابي'},...staff.filter(u=>u.active!==false&&!['installer','warehouse'].includes(u.user_type))].map(u=>[u.id,u])).values()].map(u=><option key={u.id} value={u.id}>{u.display_name||u.username||'مستخدم'}</option>)}</select></label>}
    <section className={'customerOpening '+(form.opening?'enabled':'')}><label className="customerCheck"><input aria-label="رصيد افتتاحي إن وجد" type="checkbox" checked={form.opening} onChange={e=>change('opening',e.target.checked)}/><span><strong>رصيد افتتاحي</strong><small>حساب سابق على بداية التعامل</small></span></label>{form.opening&&<div className="customerOpeningFields"><label>مبلغ الرصيد الافتتاحي · د.ع<MoneyInput aria-label="مبلغ الرصيد الافتتاحي" value={form.amount} onChange={v=>change('amount',v)} placeholder="مثال: 2,000,000" required/></label><label>اتجاه الرصيد<select aria-label="اتجاه الرصيد الافتتاحي" value={form.direction} onChange={e=>change('direction',e.target.value)}><option value="1">لنا على العميل</option><option value="-1">للعميل عندنا</option></select></label></div>}{editing&&<div className="openingEditSummary"><span>الافتتاحي المسجل <b>{money(Math.abs(editing.openingBalance))} د.ع {editing.openingBalance<0?'للعميل':'لنا'}</b></span><span>الرصيد الكلي بعد الحفظ <b>{money(Math.abs(proposedBalance))} د.ع {proposedBalance<0?'للعميل':'لنا'}</b></span><small>تعديل الافتتاحي يصحح الحساب ويحفظ سجل التغيير.</small></div>}</section>
   </fieldset><div className="customerEditorActions"><button className="customerPrimary" disabled={busy||duplicates.length>0||loading} type="submit">{busy?'جاري الحفظ…':uncertain?'إعادة تأكيد الحفظ':editing?'حفظ التعديل والرصيد':'إضافة الزبون'}</button>{editing&&<button type="button" disabled={busy||uncertain} onClick={cancel}>إلغاء التعديل</button>}</div></form>{editing&&Number(editing.balance)===0&&!(editing.rows||[]).length&&<button type="button" className="miniDelete" disabled={busy||uncertain} onClick={()=>remove(editing)}>حذف العميل</button>}</div></section>;
 return <section className="miniParty miniDirectory customerWorkspace"><header className="miniPageHead"><h1>العملاء</h1><button type="button" className="miniIcon" aria-label="تحديث العملاء" disabled={loading} onClick={refresh}><AppIcon name="refresh" size={18}/></button><button type="button" className="miniIcon add" aria-label="زبون جديد" disabled={busy||uncertain} onClick={()=>{cancel();setDetail(null);setEditorOpen(true);}}><AppIcon name="add" size={20}/></button></header>{alerts}
  <div className="miniSearchBar"><div className="miniSearch"><AppIcon name="search" size={17}/><input aria-label="بحث الزبائن المسجلين" value={query} onChange={e=>{setQuery(e.target.value);setPage(1);}} placeholder="بحث بالاسم أو الهاتف…"/></div><button type="button" className={'miniIcon '+(filtersOpen?'selected':'')} aria-label="تصفية العملاء" aria-expanded={filtersOpen} onClick={()=>setFiltersOpen(v=>!v)}><AppIcon name="filter" size={18}/></button></div>
  {filtersOpen&&<div className="miniDirectoryFilters"><label>النوع<select aria-label="تصفية نوع الزبون" value={type} onChange={e=>{setType(e.target.value);setPage(1);}}><option value="all">الكل</option><option value="system">مفرد</option><option value="wholesale">جملة</option></select></label><label>الحساب<select aria-label="تصفية رصيد الزبون" value={balance} onChange={e=>{setBalance(e.target.value);setPage(1);}}><option value="all">كل الأرصدة</option><option value="due">لنا على العميل</option><option value="credit">للعميل عندنا</option><option value="zero">مسدد</option></select></label></div>}
  {loading&&!records.length?<p className="miniEmpty" role="status">جاري تحميل العملاء…</p>:<div className="miniPartyRows">{visible.map(c=><button type="button" className="miniPartyRow customerCard" key={c.id} disabled={busy||editingId!==null} onClick={()=>showAccount(c.id)} aria-label={'حساب '+c.name}><span className="miniAvatar">{partyInitials(c.name)}</span><span className="miniRowIdentity"><b>{c.name}</b><small>{c.phone||typeLabel(c.customerType)}{isAdmin&&c.ownerName?' · '+c.ownerName:''}</small></span><span className={'miniRowBalance '+(c.balance>0?'credit':c.balance<0?'debit':'neutral')}><bdi>{money(c.balance)} <small>د.ع</small></bdi></span><AppIcon name="chevron" size={14}/></button>)}{!visible.length&&<p className="miniEmpty">{query?'لا يوجد عميل مطابق.':'لا يوجد عملاء مسجلون.'}</p>}</div>}
  {pages>1&&<nav className="miniPagination"><button disabled={currentPage===1} onClick={()=>setPage(currentPage-1)}>السابق</button><span>{currentPage} / {pages}</span><button disabled={currentPage===pages} onClick={()=>setPage(currentPage+1)}>التالي</button></nav>}
 </section>;
}
