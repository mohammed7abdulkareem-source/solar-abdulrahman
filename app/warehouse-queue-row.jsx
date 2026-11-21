'use client';
import {useEffect,useId,useState} from 'react';
import AppIcon from './app-icons';
import {materialItemTotal} from './material-quantity.mjs';
import {quantity} from './warehouse-utils.mjs';

export function QueueStates({label,choices,counts,value,onChange}){
 return <nav className="warehouseQueueTabs" aria-label={label}>
  {choices.map(([key,text])=><button type="button" className="warehouseStateFilter" key={key} data-queue-filter={key||'all'} aria-pressed={value===key} onClick={()=>onChange(key)}>
   <span>{text}</span>
   <span className="warehouseMetric"><bdi>{counts?.[key||'all']==null?'—':quantity(counts[key||'all'])}</bdi>
    <AppIcon name={key==='pending'?'package':key?'check':'grid'} size={17}/></span>
  </button>)}
 </nav>;
}

export default function WarehouseQueueRow({id,selected,className,detailsClass,state,transfer=false,label,identity,title,context,status,items,quantityLabel,quantityTestId,children}){
 const [open,setOpen]=useState(selected),description=useId(),statusDescription=useId();
 useEffect(()=>{if(selected)setOpen(true);},[selected]);
 const count=items.length;
 const total=materialItemTotal(items);
 return <article id={id} tabIndex={-1} className={'warehouseQueueRow '+className+(selected?' highlighted':'')} data-row-state={state}
  data-transfer-state={transfer?state:undefined} data-preparation-state={transfer?undefined:state}>
  <details className={detailsClass} open={open} onToggle={event=>setOpen(event.currentTarget.open)}>
   <summary className="warehouseRowSummary" aria-label={label} aria-describedby={description+' '+statusDescription}>
    <span className="warehouseRowMain" id={description}>
     <span className="warehouseRowIdentity"><AppIcon name={transfer?'truck':'receipt'} size={15}/>{identity}</span>
     <strong className="warehouseRowTitle">{title}</strong>
     <span className="warehouseRowContext">{context}</span>
    </span>
    <span className="warehouseRowStats" id={statusDescription}><span className={'warehouseBadge '+state}>{status}</span>
     <span className="warehouseRowCounts"><span>{quantity(count)} فقرة</span><span>{quantityLabel} <bdi data-testid={quantityTestId}>{total}</bdi></span></span>
    </span>
    <span className="warehouseExpandIcon" aria-hidden="true"><AppIcon name="chevron" size={14}/></span>
   </summary>
   {open&&<div className="warehouseRowBody">{children()}</div>}
  </details>
 </article>;
}
