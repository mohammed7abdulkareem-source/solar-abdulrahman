'use client';
import {useRef,useState} from 'react';
import {filteredStock} from './warehouse-utils.mjs';
import {materialsByCode} from './record-browser-utils.mjs';
import {RecordNavigator} from './record-browser';
import AppIcon from './app-icons';
import MaterialNameField from './material-name-field';
import {normalizeSearch} from './party-search-utils.mjs';
const categories=['انفيرتر','انفيرتر زراعي','All in One','بطارية','ألواح','مستلزمات','أخرى'];
export default function ProductsManager({products,setProducts,addProduct,brands}){
 const [edit,setEdit]=useState(null),[query,setQuery]=useState(''),[open,setOpen]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState('');const form=useRef(null),dirty=useRef(false);
 const [draftName,setDraftName]=useState(''),[duplicate,setDuplicate]=useState(null);
 const brandNames=brands.map(brand=>brand.name);
 const formBrands=edit?.brand&&!brandNames.includes(edit.brand)?[edit.brand,...brandNames]:brandNames;
 const formCategories=edit?.category&&!categories.includes(edit.category)?[edit.category,...categories]:categories;
 const ordered=materialsByCode(products),position=ordered.findIndex(p=>p.id===edit?.id);
 const next=products.reduce((m,p)=>Math.max(m,parseInt(String(p.code||'').replace(/\D/g,''))||0),0)+1,shown=materialsByCode(filteredStock(products,query));
 async function submit(event) {
  event.preventDefault();
  if (busy) return;
  const fields = new FormData(event.currentTarget);
  const item = {name: fields.get('name').trim(), brand: fields.get('brand'), category: fields.get('category')};
  const key = value => normalizeSearch(value).replace(/\s+/g, ' ');
  const existing = products.find(product => product.id !== edit?.id &&
   ['name','brand','category'].every(field => key(product[field]) === key(item[field])));
  setMessage('');
  if (existing) { setDuplicate(existing); return; }
  setBusy(true);
  try {
   if (edit) {
    const updated = {...edit, ...item};
    const ok = await setProducts(products.map(product => product.id === edit.id ? {...product,...item} : product));
    if (ok !== false) {
     setEdit(updated); setDraftName(updated.name); dirty.current = false; setMessage('تم حفظ تعديل المادة.');
    }
   } else {
    const ok = await addProduct(event);
    if (ok !== false) {
     setDraftName(''); dirty.current = false; setMessage('تم حفظ المادة. يمكنك البحث عنها أدناه للتعديل.');
    }
   }
  } finally { setBusy(false); }
 }
 function beginEdit(product, focus = false, fromName = false) {
  if (busy) return false;
  const fields = form.current?.elements;
  const typedOnlyName = fromName && !edit && !fields?.brand?.value && !fields?.category?.value;
  if (dirty.current && !typedOnlyName && !confirm('توجد تغييرات غير محفوظة. الانتقال بدون حفظها؟')) return false;
  dirty.current = false;
  setEdit(product); setDraftName(product?.name || ''); setDuplicate(null); setMessage('');
  if (focus) {
   window.scrollTo({top: 0, behavior: 'smooth'});
   requestAnimationFrame(() => form.current?.elements.name?.focus({preventScroll: true}));
  }
  return true;
 }
 return <section className="productsManager"><form onChange={()=>{dirty.current=true;setDuplicate(null);setMessage('');}} ref={form} key={edit?.id||'new'} onSubmit={submit} className="card reconcileForm"><div className="materialCodeNavigator"><div className="autoCode"><span>{edit?'تعديل المادة حسب تسلسل الكود':'مادة جديدة · الكود التالي'}</span></div><RecordNavigator label="التنقل حسب كود المادة" index={position} total={ordered.length} busy={busy} previousDisabled={!ordered.length||position===0} nextDisabled={position<0||position+1>=ordered.length} onPrevious={()=>beginEdit(ordered[position<0?ordered.length-1:position-1])} onNext={()=>beginEdit(ordered[position+1])}><bdi>{edit?.code||String(next).padStart(4,'0')}</bdi><small>{edit?'المادة '+(position+1)+' من '+ordered.length:'مادة جديدة'}</small></RecordNavigator></div><MaterialNameField products={products} editing={edit} value={draftName} onChange={setDraftName} onChoose={product=>beginEdit(product,true,true)} disabled={busy}/><div className="reconcilePair"><label>البراند<select name="brand" defaultValue={edit?.brand||''} required disabled={busy}><option value="" disabled>اختر البراند</option>{formBrands.map(name=><option key={name} value={name}>{name}</option>)}</select></label><label>الصنف<select name="category" defaultValue={edit?.category||''} required disabled={busy}><option value="" disabled>اختر الصنف</option>{formCategories.map(c=><option key={c}>{c}</option>)}</select></label></div>{duplicate&&<div className="materialDuplicate" role="alert"><p>هذه المادة مسجّلة بنفس الاسم والبراند والصنف.</p><button type="button" className="miniSecondary" onClick={()=>beginEdit(duplicate,true)}>فتح المادة المسجّلة</button></div>}<button disabled={busy}>{busy?'جاري الحفظ…':edit?'حفظ التعديل':'حفظ المادة'}</button>{edit&&<button type="button" disabled={busy} onClick={()=>beginEdit(null)}>إلغاء التعديل</button>}</form>{edit&&<button type="button" className="miniSecondary materialsNewButton" disabled={busy} onClick={()=>beginEdit(null)}><AppIcon name="add" size={15}/>مادة جديدة</button>}{message&&<p role="status" className="workflowSuccess">{message}</p>}<div className="card materialsSearch"><label>بحث المواد المحفوظة<input aria-label="بحث المواد المحفوظة" placeholder="اسم المادة، الكود، البراند أو الصنف" value={query} onChange={e=>{setQuery(e.target.value);if(e.target.value.trim())setOpen(true)}}/></label><button className="materialsToggle" aria-expanded={open} aria-controls="saved-materials" onClick={()=>setOpen(v=>!v)}><span>المواد المحفوظة ({shown.length})</span><span aria-hidden="true">{open?'▴':'▾'}</span></button>{open&&<div id="saved-materials" className="savedMaterials">{shown.map(p=><article key={p.id} className="savedMaterial"><div><b>{p.name}</b><small>كود: {p.code} • {p.brand} • {p.category}</small></div><div className="rowActions"><button disabled={busy} onClick={()=>beginEdit(p,true)}>تعديل</button><button disabled={busy} className="dangerMini" onClick={async()=>{if(!confirm('حذف المادة؟'))return;setBusy(true);try{const ok=await setProducts(products.filter(x=>x.id!==p.id));if(ok!==false&&edit?.id===p.id){dirty.current=false;setEdit(null);setDraftName('');setDuplicate(null);}}finally{setBusy(false)}}}>حذف</button></div></article>)}{!shown.length&&<p className="empty">لا توجد مادة مطابقة للبحث</p>}</div>}</div></section>;
}
