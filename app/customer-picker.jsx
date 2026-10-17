'use client';
import {useId,useRef,useState} from 'react';
import {filterAccountCustomers} from './party-balances-utils.mjs';
import {ReportIcon} from './report-actions';
export default function CustomerPicker({rows=[],value='',onChange,loading=false}){
 const [query,setQuery]=useState(''),[open,setOpen]=useState(false),[index,setIndex]=useState(0);const id=useId(),input=useRef(null);
 const selected=rows.find(c=>String(c.id)===String(value));
 const matches=filterAccountCustomers(rows,query),visible=matches.slice(0,30);
 const choose=row=>{onChange(String(row.id));setQuery('');setOpen(false);setIndex(0);input.current?.focus();};
 return <div className="accountPicker" onBlur={e=>{if(!e.currentTarget.contains(e.relatedTarget))setOpen(false);}}><label htmlFor={id+'-input'}>ابحث واختر العميل</label><div className="accountPickerInput"><ReportIcon name="search"/><input id={id+'-input'} ref={input} role="combobox" aria-label="بحث عميل الكشف" aria-expanded={open} aria-controls={id} aria-autocomplete="list" aria-activedescendant={open&&visible[index]?id+'-'+index:undefined} autoComplete="off" placeholder={loading?'جاري تحميل دليل العملاء…':'اكتب الاسم أو رقم الهاتف…'} disabled={loading} value={open?query:selected?.name||query} onFocus={()=>{setOpen(true);setQuery('');setIndex(0);}} onChange={e=>{setQuery(e.target.value);if(value)onChange('');setOpen(true);setIndex(0);}} onKeyDown={e=>{if(e.key==='Escape'){setOpen(false);return;}if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();setOpen(true);setIndex(i=>Math.max(0,Math.min(visible.length-1,i+(e.key==='ArrowDown'?1:-1))));}if(e.key==='Enter'&&open){e.preventDefault();if(visible[index])choose(visible[index]);}}}/>{selected&&<button type="button" aria-label="إلغاء اختيار عميل الكشف" onClick={()=>{onChange('');setQuery('');setOpen(true);input.current?.focus();}}>×</button>}</div>
 {open&&<div className="accountPickerResults" role="listbox" id={id} aria-label="نتائج بحث العملاء">{visible.map((row,i)=><button type="button" role="option" id={id+'-'+i} aria-selected={i===index} className={i===index?'highlighted':''} key={row.id} onMouseDown={e=>e.preventDefault()} onClick={()=>choose(row)}><span className="accountPickerAvatar">{row.name.slice(0,1)}</span><span><b>{row.name}</b><small><bdi>{row.phone||'بدون رقم هاتف'}</bdi> · {row.owner_name||'غير مخصص'}</small></span><em>{row.customer_type==='wholesale'?'جملة':'منظومات'}</em></button>)}{!visible.length&&<p>لا يوجد عميل مطابق للاسم أو الهاتف.</p>}{matches.length>30&&<p>اكتب جزءاً إضافياً من الاسم لعرض نتائج أدق.</p>}</div>}
 </div>;
}
