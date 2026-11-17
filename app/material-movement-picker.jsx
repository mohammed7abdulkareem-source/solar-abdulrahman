'use client';
import {useEffect,useId,useMemo,useRef,useState} from 'react';
import AppIcon from './app-icons';
import {quantity} from './warehouse-utils.mjs';
import {filterMovementProducts,materialSelectionLabel} from './material-movement-utils.mjs';

// Same material identity/search as the sale catalog; selecting is explicit and
// zero-stock materials remain available for historical movement reports.
export default function MaterialMovementPicker({products,selectedId,query,onQuery,onSelect,onClear,onShowAll,loading=false,error=''}){
 const id=useId(),input=useRef(null),[open,setOpen]=useState(false),[active,setActive]=useState(-1);
 const matches=useMemo(()=>loading?[]:filterMovementProducts(products,query),[products,query,loading]);
 useEffect(()=>{if(open&&active>=0)document.getElementById(id+'-option-'+active)?.scrollIntoView({block:'nearest'});},[id,open,active]);
 const selected=products.find(product=>String(product.id)===String(selectedId));
 function select(product){if(loading)return;onSelect(product);setOpen(false);setActive(-1);}
 function edit(value){onQuery(value);setOpen(true);setActive(-1);}
 function change(){onClear();setOpen(true);setActive(-1);input.current?.focus();}
 return <section className="mmPicker" aria-label="اختيار مادة محددة" onBlur={event=>{if(!event.currentTarget.contains(event.relatedTarget))setOpen(false);}}>
  <div className="mmPickerLabel"><label htmlFor={id+'-input'}>ابحث عن المادة ثم اخترها</label>{onShowAll&&<button type="button" className="mmShowAll" onClick={()=>{onShowAll();setOpen(false);}}>عرض جميع المواد</button>}</div>
  <div className="mmPickerSearch"><AppIcon name="search" size={19}/><input ref={input} id={id+'-input'} role="combobox" aria-label="البحث عن مادة للحركة" aria-expanded={open} aria-controls={id+'-results'} aria-autocomplete="list" aria-activedescendant={open&&active>=0&&matches[active]?id+'-option-'+active:undefined} autoComplete="off" value={query} placeholder="ابحث عن اسم المادة أو الكود…" onFocus={()=>setOpen(true)} onChange={event=>edit(event.target.value)} onKeyDown={event=>{if(event.nativeEvent.isComposing)return;if(event.key==='Escape')setOpen(false);if(event.key==='ArrowDown'){event.preventDefault();setOpen(true);setActive(index=>Math.min(index+1,matches.length-1));}if(event.key==='ArrowUp'){event.preventDefault();setOpen(true);setActive(index=>Math.max(0,index-1));}if(event.key==='Enter'){event.preventDefault();if(open&&active>=0&&matches[active])select(matches[active]);else if(matches.length===1)select(matches[0]);else setOpen(true);}}}/><button type="button" aria-label="عرض قائمة المواد" aria-expanded={open} onClick={()=>setOpen(value=>!value)}><AppIcon name="package" size={17}/><span>اختيار مادة</span></button></div>
  {open&&<div className="mmPickerResults"><div className="mmPickerResultCount" role="status">{loading?'جاري تحميل المواد…':matches.length+' مادة مطابقة · اختر مادة واحدة'}</div><div id={id+'-results'} role="listbox" aria-label="المواد المطابقة" className="mmPickerList">{matches.map((product,index)=><button type="button" role="option" id={id+'-option-'+index} aria-selected={String(product.id)===String(selectedId)} aria-label={'اختيار '+materialSelectionLabel(product)} key={product.id} className={'mmMaterialOption'+(active===index?' active':'')} onMouseDown={event=>event.preventDefault()} onClick={()=>select(product)}><span className="mmMaterialMark"><AppIcon name="package" size={20}/></span><span className="mmMaterialIdentity"><b dir="auto">{product.name}</b><small dir="auto">{[product.brand,product.category,product.code&&'كود '+product.code].filter(Boolean).join(' · ')}</small><small>المتاح <bdi>{quantity(product.qty)}</bdi></small></span><span className="mmMaterialChoose">اختيار</span></button>)}</div>{!loading&&!matches.length&&<p className="mmPickerEmpty">لا توجد مادة مطابقة. جرّب الاسم أو الكود أو البراند.</p>}</div>}
  {selected&&<div className="mmSelectedMaterial" data-selected-product-id={selected.id}><span className="mmMaterialMark"><AppIcon name="check" size={19}/></span><div><small>المادة المحددة</small><strong dir="auto">{selected.name}</strong><span dir="auto">{[selected.brand,selected.category,selected.code&&'كود '+selected.code].filter(Boolean).join(' · ')}</span></div><button type="button" onClick={change}>تغيير المادة</button></div>}
  {error&&<p className="mlError" role="alert">{error}</p>}
 </section>;
}
