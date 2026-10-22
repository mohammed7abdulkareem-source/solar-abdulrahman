'use client';
import PhoneActions from './phone-actions';
import {useEffect,useRef,useState} from 'react';
import {supabase} from './supabase';
import AppIcon from './app-icons';
import {sections} from './section-directory.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {searchCategories,searchSections,balanceCaption} from './quick-search-utils.mjs';
import {formatMoney as money,currencyUnit as unit} from './money-format.mjs';

const labels={all:'الكل',customers:'العملاء',products:'المواد',suppliers:'الموردون'};
const empty={customers:[],products:[],suppliers:[],more:{}};
export default function QuickSearch({open,onClose,profile,onNavigate,onOpenAccount}){
 const dialog=useRef(null),input=useRef(null),[query,setQuery]=useState(''),[category,setCategory]=useState('all'),[response,setResponse]=useState({key:'',data:empty,status:'idle',error:''}),[retry,setRetry]=useState(0);
 const permissionKey=JSON.stringify(profile.permissions||{});
 const normalized=normalizeSearch(query),ready=normalized.length>=2,allowed=searchCategories(profile),sectionRows=category==='all'?searchSections(sections,profile,query):[];
 const requestKey=JSON.stringify([query,category,profile.id,profile.active,profile.user_type,profile.is_admin,permissionKey,retry]);
 const current=response.key===requestKey?response:{data:empty,status:ready?'loading':'idle',error:''};
 const result=current.data,loading=open&&ready&&current.status==='loading',error=current.error;
 useEffect(()=>{
  if(!open)return;
  const previousFocus=document.activeElement;
  dialog.current?.showModal();input.current?.focus();
  const before=document.body.style.overflow;document.body.style.overflow='hidden';
  return()=>{document.body.style.overflow=before;if(previousFocus?.isConnected)previousFocus.focus();};
 },[open]);
 useEffect(()=>{
  if(!open){setQuery('');setCategory('all');setResponse({key:'',data:empty,status:'idle',error:''});return;}
  if(!ready){setResponse({key:requestKey,data:empty,status:'idle',error:''});return;}
  let live=true,requestTimer;const controller=new AbortController();setResponse({key:requestKey,data:empty,status:'loading',error:''});
  const timer=setTimeout(async()=>{
   requestTimer=setTimeout(()=>controller.abort(),8000);
   try{
    const {data,error:failure}=await supabase.rpc('solar_quick_search',{term:query.trim(),category}).abortSignal(controller.signal);
    if(failure)throw failure;
    if(live)setResponse({key:requestKey,data:data||empty,status:'ready',error:''});
   }catch(e){if(live)setResponse({key:requestKey,data:empty,status:'error',error:e.code==='42501'?'تغيرت صلاحية البحث. حدّث البرنامج أو راجع الإدارة.':'تعذر البحث. تحقق من الاتصال وأعد المحاولة.'});}
   finally{clearTimeout(requestTimer);}
  },240);
  return()=>{live=false;clearTimeout(timer);clearTimeout(requestTimer);controller.abort();};
 },[open,query,category,ready,profile.id,profile.active,profile.user_type,profile.is_admin,permissionKey,retry,requestKey]);
 const count=result.customers.length+result.products.length+result.suppliers.length+sectionRows.length;
 function account(kind,row){onClose();onOpenAccount(kind,row);}
 function navigate(id){onClose();onNavigate(id);}
 function more(kind){if(category===kind)input.current?.focus();setCategory(kind);dialog.current?.querySelector('.quickSearchBody')?.scrollTo({top:0});}
 if(!open)return null;
 return <dialog ref={dialog} className="quickSearchDialog" aria-labelledby="quick-search-title" onCancel={e=>{e.preventDefault();onClose();}} onClick={e=>{if(e.target===e.currentTarget){const r=e.currentTarget.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)onClose();}}}>
  <header className="quickSearchHeader"><div><h2 id="quick-search-title">البحث السريع</h2><small>حساب زبون، مادة، مورد أو قسم</small></div><button type="button" className="quickSearchClose" onClick={onClose} aria-label="إغلاق البحث"><AppIcon name="close" size={20}/></button></header>
  <div className="quickSearchInput"><AppIcon name="search" size={21}/><input ref={input} value={query} maxLength={100} onChange={e=>setQuery(e.target.value)} placeholder="اكتب الاسم، رقم الهاتف أو كود المادة…" aria-label="البحث العام" autoComplete="off" enterKeyHint="search"/>{query&&<button type="button" aria-label="مسح البحث" onClick={()=>{setQuery('');input.current?.focus();}}><AppIcon name="close" size={16}/></button>}</div>
  <div className="quickSearchTabs" role="group" aria-label="نوع نتائج البحث">{allowed.map(id=><button key={id} type="button" aria-pressed={category===id} onClick={()=>setCategory(id)}>{labels[id]}</button>)}</div>
  <div className="quickSearchBody" aria-busy={loading}>
   {!ready&&<div className="quickSearchEmpty"><AppIcon name="search" size={28}/><b>المعلومة بسرعة من مكان واحد</b><p>اكتب حرفين أو أكثر. تظهر أرصدة الزبائن وكميات المواد وأسعارها ضمن صلاحياتك.</p></div>}
   {loading&&<p className="quickSearchState" role="status">جاري البحث…</p>}
   {error&&<div className="quickSearchError" role="alert">{error}<button type="button" onClick={()=>setRetry(v=>v+1)}>إعادة المحاولة</button></div>}
   {ready&&!loading&&!error&&count===0&&<p className="quickSearchState" role="status">لا توجد نتائج ضمن صلاحياتك. جرّب اسماً أو كوداً آخر.</p>}
   {result.customers.length>0&&<section className="quickSearchGroup" aria-label="نتائج العملاء"><h3><AppIcon name="customers" size={17}/>العملاء <small>{result.customers.length}{result.more.customers?'+':''}</small></h3>{result.customers.map(row=><div className="quickSearchPartyEntry" key={row.id}><button type="button" className="quickSearchParty" onClick={()=>account('customers',row)}><span><b>{row.name}</b><small>{row.customerType==='system'?'زبون منظومات':'زبون جملة'}</small></span><span className={Number(row.balance)>0?'quickSearchDebt':'quickSearchCredit'}><small>{balanceCaption(row.balance)}</small><strong><bdi>{money(Math.abs(row.balance))} د.ع</bdi></strong></span><AppIcon name="chevron" size={16}/></button><PhoneActions phone={row.phone} label={row.name}/></div>)}{result.more.customers&&<button type="button" className="quickSearchMore" onClick={()=>more('customers')}>{category==='customers'?'توجد نتائج أخرى؛ أكمل الاسم أو رقم الهاتف':'المزيد من العملاء'}</button>}</section>}
   {result.products.length>0&&<section className="quickSearchGroup" aria-label="نتائج المواد"><h3><AppIcon name="products" size={17}/>المواد <small>{result.products.length}{result.more.products?'+':''}</small></h3><p className="quickSearchScope">الكميات المتاحة في المخازن المسموحة لك</p>{result.products.map(row=><details className="quickSearchProduct" key={row.id}><summary><span className="quickSearchProductName"><b dir="auto">{row.name}</b><small>{[row.brand,row.category,row.code&&'كود '+row.code].filter(Boolean).join(' · ')}</small></span><span className={Number(row.qty)>0?'quickSearchStock':'quickSearchOut'}><small>المتوفر</small><strong>{money(row.qty)}</strong></span><AppIcon name="chevron" size={16}/>{Object.hasOwn(row,'cost')&&<span className="quickSearchPrices"><span><small>آخر سعر بيع مسجّل</small><b>{row.lastSale?<bdi>{money(row.lastSale.amount)} د.ع</bdi>:'غير مسجّل'}</b></span><span><small>كلفة الوحدة</small><b><bdi>{money(row.cost)} د.ع</bdi></b></span></span>}</summary><div className="quickSearchProductDetail">{row.warehouses.map(w=><div key={w.id}><span>{w.name}{!w.active&&<small> · متوقف</small>}</span><b>{money(w.qty)} متاح{Number(w.reserved)>0&&<small> · {money(w.reserved)} محجوز</small>}</b></div>)}{row.lastSale&&<p>آخر سعر بيع مسجّل ضمن صلاحياتك بتاريخ {new Date(row.lastSale.date).toLocaleDateString('en-GB',{timeZone:'Asia/Baghdad'})}. يتحدد سعر البيع عند إصدار الفاتورة.</p>}</div></details>)}{result.more.products&&<button type="button" className="quickSearchMore" onClick={()=>more('products')}>{category==='products'?'توجد نتائج أخرى؛ أكمل الاسم أو كود المادة':'المزيد من المواد'}</button>}</section>}
   {result.suppliers.length>0&&<section className="quickSearchGroup" aria-label="نتائج الموردين"><h3><AppIcon name="suppliers" size={17}/>الموردون <small>{result.suppliers.length}{result.more.suppliers?'+':''}</small></h3>{result.suppliers.map(row=><div className="quickSearchPartyEntry" key={row.id}><button type="button" className="quickSearchParty" onClick={()=>account('suppliers',row)}><span><b>{row.name}</b><small>حساب المورد</small></span><span className="quickSearchDebt"><small>{balanceCaption(row.balance,true)}</small><strong><bdi>{money(Math.abs(row.balance),row.currency)} {unit(row.currency)}</bdi></strong></span><AppIcon name="chevron" size={16}/></button><PhoneActions phone={row.phone} label={row.name}/></div>)}{result.more.suppliers&&<button type="button" className="quickSearchMore" onClick={()=>more('suppliers')}>{category==='suppliers'?'توجد نتائج أخرى؛ أكمل اسم المورد':'المزيد من الموردين'}</button>}</section>}
   {ready&&sectionRows.length>0&&<section className="quickSearchGroup" aria-label="نتائج الأقسام"><h3><AppIcon name="grid" size={17}/>أقسام البرنامج</h3><div className="quickSearchSections">{sectionRows.map(([id,label])=><button key={id} type="button" onClick={()=>navigate(id)}><AppIcon name={id} size={18}/>{label}</button>)}</div></section>}
  </div>
 </dialog>;
}
