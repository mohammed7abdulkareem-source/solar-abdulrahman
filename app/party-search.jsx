'use client';
import {useId,useState} from 'react';
import {filterParties} from './party-search-utils.mjs';

export default function PartySearch({rows=[],value:controlledValue,onChange,name,placeholder='ابحث عن الزبون بالاسم أو الهاتف…'}){
 const [localValue,setLocalValue]=useState(''),value=controlledValue??localValue;
 const update=value=>{setLocalValue(value);onChange?.(value)};
 const [query,setQuery]=useState(''),[open,setOpen]=useState(false),[index,setIndex]=useState(0);
 const id=useId(),matches=filterParties(rows,query),visible=matches.slice(0,40);
 const choose=row=>{update(row.name);setQuery('');setOpen(false);setIndex(0)};
 return <div className="partySearch" onBlur={e=>{if(!e.currentTarget.contains(e.relatedTarget))setOpen(false)}}>
  {name&&<input type="hidden" name={name} value={value}/>}
  <div className="partySearchInput"><input role="combobox" aria-label={placeholder} aria-expanded={open} aria-controls={id} aria-autocomplete="list" aria-activedescendant={open&&visible[index]?id+'-'+index:undefined} autoComplete="off" placeholder={placeholder} value={open?query:value} onFocus={()=>{setQuery('');setOpen(true);setIndex(0)}} onChange={e=>{setQuery(e.target.value);setOpen(true);setIndex(0)}} onKeyDown={e=>{if(e.key==='Escape'){setOpen(false);return}if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();setOpen(true);setIndex(i=>Math.max(0,Math.min(visible.length-1,i+(e.key==='ArrowDown'?1:-1))))}if(e.key==='Enter'&&open){e.preventDefault();if(visible[index])choose(visible[index])}}}/>{value&&<button type="button" aria-label="إلغاء اختيار الزبون" onClick={()=>{update('');setQuery('');setOpen(false)}}>×</button>}</div>
  {open&&<div className="partySearchResults" id={id} role="listbox">{value&&<small>المحدد حالياً: {value}</small>}{visible.map((row,i)=><button type="button" role="option" aria-selected={i===index} id={id+'-'+i} key={row.id} onMouseDown={e=>e.preventDefault()} onClick={()=>choose(row)}><b>{row.name}</b><small>{[row.phone,row.customerType].filter(Boolean).join(' • ')}</small></button>)}{!visible.length&&<p>ماكو زبون مطابق للبحث</p>}{matches.length>40&&<small>اكتب جزءاً إضافياً من الاسم لتقليل النتائج</small>}</div>}
 </div>;
}
