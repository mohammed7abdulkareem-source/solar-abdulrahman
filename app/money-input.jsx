'use client';
import {useId,useLayoutEffect,useRef} from 'react';
import {amountInput,formatAmountInput} from './customer-utils.mjs';
export default function MoneyInput({value='',onChange,name,...props}){
 const input=useRef(null),caret=useRef(null),id=useId();
 const formatted=formatAmountInput(value);
 useLayoutEffect(()=>{if(caret.current==null||document.activeElement!==input.current)return;let count=0,position=0;while(position<formatted.length&&count<caret.current){if(/[0-9.]/.test(formatted[position]))count++;position++;}input.current.setSelectionRange(position,position);caret.current=null;},[formatted]);
 return <><input {...props} id={props.id||id} ref={input} dir="ltr" className={'moneyInput '+(props.className||'')} type="text" inputMode="decimal" autoComplete="off" value={formatted} onChange={e=>{const next=amountInput(e.target.value);if(!/^\d*(?:\.\d{0,2})?$/.test(next))return;caret.current=amountInput(e.target.value.slice(0,e.target.selectionStart)).length;onChange(next);}}/>{name&&<input type="hidden" name={name} value={value}/>}</>;
}
