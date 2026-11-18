'use client';
import {useEffect, useId, useMemo, useState} from 'react';
import {filterMovementProducts} from './material-movement-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import './material-name-field.css';

export default function MaterialNameField({products, editing, value, onChange, onChoose, disabled}) {
 const id = useId();
 const [open, setOpen] = useState(false);
 const [active, setActive] = useState(-1);
 const needle = normalizeSearch(value);
 const matches = useMemo(() => {
  if (!needle) return [];
  const found = filterMovementProducts(products, needle).filter(product => product.id !== editing?.id);
  const rank = product => {
   const name = normalizeSearch(product.name);
   if (name === needle) return 0;
   return name.startsWith(needle) ? 1 : 2;
  };
  return found.sort((a, b) => rank(a) - rank(b));
 }, [products, editing?.id, needle]);
 const expanded = open && matches.length > 0 && !disabled;
 const activeId = expanded && matches[active] ? id + '-option-' + matches[active].id : undefined;
 useEffect(() => {
  if (activeId) document.getElementById(activeId)?.scrollIntoView({block: 'nearest'});
 }, [activeId]);

 function close() {
  setOpen(false);
  setActive(-1);
 }
 function choose(product) {
  if (onChoose(product)) close();
 }
 function keyDown(event) {
  if (event.nativeEvent.isComposing) return;
  if (event.key === 'Escape' && expanded) {
   event.preventDefault();
   close();
  } else if (matches.length && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
   event.preventDefault();
   setOpen(true);
   if (event.key === 'ArrowDown') setActive(index => Math.min(index + 1, matches.length - 1));
   else setActive(index => index < 0 ? matches.length - 1 : Math.max(0, index - 1));
  } else if (event.key === 'Enter' && activeId) {
   event.preventDefault();
   choose(matches[active]);
  }
 }

 return <div className="materialNameField" onBlur={event => {
  if (!event.currentTarget.contains(event.relatedTarget)) close();
 }}>
  <label htmlFor={id}>اسم المادة</label>
  <input id={id} name="name" required disabled={disabled} value={value} placeholder="اسم المادة"
   role="combobox" autoComplete="off" aria-expanded={expanded} aria-autocomplete="list"
   aria-controls={expanded ? id + '-list' : undefined} aria-activedescendant={activeId}
   onFocus={() => { if (value && value !== editing?.name) setOpen(true); }}
   onChange={event => { onChange(event.target.value); setOpen(true); setActive(-1); }}
   onKeyDown={keyDown}/>
  {expanded && <div className="materialNameSuggestions">
   <p role="status">مواد مشابهة ({matches.length}) · اختر لفتح المادة المسجّلة</p>
   <div id={id + '-list'} role="listbox" aria-label="المواد المشابهة">
    {matches.map((product, index) =>
     <button key={product.id} id={id + '-option-' + product.id} type="button" role="option"
      tabIndex={-1} aria-selected={active === index}
      onMouseDown={event => event.preventDefault()} onClick={() => choose(product)}>
      <strong dir="auto">{product.name}</strong>
      <small>{[product.brand, product.category, product.code && 'كود ' + product.code].filter(Boolean).join(' · ')}</small>
     </button>
    )}
   </div>
  </div>}
 </div>;
}
