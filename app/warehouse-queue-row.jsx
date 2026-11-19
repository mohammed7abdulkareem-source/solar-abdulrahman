'use client';
import {useEffect,useId,useState} from 'react';
import AppIcon from './app-icons';
import {materialQuantity} from './material-movement-utils.mjs';
import {quantity} from './warehouse-utils.mjs';

export function QueueStates({label,choices,counts,value,onChange}){
 return <nav className="warehouseQueueTabs" aria-label={label}>
  {choices.map(([key,text])=><button type="button" key={key} aria-pressed={value===key} onClick={()=>onChange(key)}>
   <span>{text}</span><bdi>{counts?.[key||'all']==null?'—':quantity(counts[key||'all'])}</bdi>
  </button>)}
 </nav>;
}

function itemTotal(items){
 const numbers=items.map(({qty})=>materialQuantity(qty).replaceAll(',','').replace('−','-'));
 if(numbers.some(value=>!/^-?\d+(?:\.\d+)?$/.test(value)))return '—';
 const parts=numbers.map(value=>value.split('.'));
 const scale=parts.reduce((largest,[,fraction=''])=>Math.max(largest,fraction.length),0);
 const sum=parts.reduce((total,[whole,fraction=''])=>total+BigInt(whole+fraction.padEnd(scale,'0')),0n);
 const digits=(sum<0n?-sum:sum).toString().padStart(scale+1,'0');
 const value=scale?digits.slice(0,-scale)+'.'+digits.slice(-scale):digits;
 return materialQuantity((sum<0n?'-':'')+value);
}

export default function WarehouseQueueRow({id,selected,className,detailsClass,state,transfer=false,label,identity,title,context,status,items,quantityLabel,quantityTestId,children}){
 const [open,setOpen]=useState(selected),description=useId(),statusDescription=useId();
 useEffect(()=>{if(selected)setOpen(true);},[selected]);
 const count=items.length;
 const total=itemTotal(items);
 return <article id={id} tabIndex={-1} className={'warehouseQueueRow '+className+(selected?' highlighted':'')} data-row-state={state}
  data-transfer-state={transfer?state:undefined} data-preparation-state={transfer?undefined:state}>
  <details className={detailsClass} open={open} onToggle={event=>setOpen(event.currentTarget.open)}>
   <summary className="warehouseRowSummary" aria-label={label} aria-describedby={description+' '+statusDescription}>
    <span className="warehouseRowMain" id={description}>
     <span className="warehouseRowIdentity">{identity}</span>
     <strong className="warehouseRowTitle">{title}</strong>
     <span className="warehouseRowContext">{context}</span>
    </span>
    <span className="warehouseRowStats" id={statusDescription}><span className={'warehouseBadge '+state}>{status}</span>
     <span className="warehouseRowCounts">{quantity(count)} فقرة <span aria-hidden="true">·</span> {quantityLabel} <bdi data-testid={quantityTestId}>{total}</bdi></span>
    </span>
    <span className="warehouseExpandIcon" aria-hidden="true"><AppIcon name="chevron" size={14}/></span>
   </summary>
   {open&&<div className="warehouseRowBody">{children()}</div>}
  </details>
 </article>;
}
