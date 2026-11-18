'use client';
import {useMemo,useState} from 'react';
import AppIcon from './app-icons';
import {matchesReceipt,receiptNumber} from './supplier-utils.mjs';
import {purchaseCorrectionNumber as preciseNumber} from './purchase-correction.mjs';
import {currencyUnit,formatMoney,purchaseDisplayTotal,purchaseUnitPrice} from './money-format.mjs';
import './purchases-hub.css';

const pageSize=20;
const dateFormat=new Intl.DateTimeFormat('ar-IQ',{year:'numeric',month:'short',day:'numeric',timeZone:'Asia/Baghdad'});

function PurchaseReceipt({row,onEdit,onDelete,renderExport}){
 const [open,setOpen]=useState(false);
 const number=receiptNumber(row),{value,currency}=purchaseDisplayTotal(row);
 const money=amount=>formatMoney(amount,currency)+' '+currencyUnit(currency);
 return <article className="purchaseHubReceipt" data-purchase-id={row.id}>
  <button className="purchaseHubSummary" type="button" onClick={()=>setOpen(v=>!v)} aria-expanded={open} aria-controls={'purchase-details-'+row.id}>
   <span className="purchaseHubMark"><AppIcon name="receipt" size={20}/></span>
   <span className="purchaseHubIdentity"><strong>فاتورة شراء رقم <bdi>{number}</bdi></strong><span>{row.party||'مورد غير محدد'}</span></span>
   <span className="purchaseHubAmount"><strong><bdi>{money(value)}</bdi></strong><time dateTime={row.date}>{dateFormat.format(new Date(row.date))}</time></span>
   <AppIcon className="purchaseHubChevron" name="chevron" size={16}/>
  </button>
  {open&&<div className="purchaseHubDetails" id={'purchase-details-'+row.id}>
   <div className="purchaseHubMeta"><span><AppIcon name="wallet" size={16}/>{row.cash?'شراء نقدي':'شراء آجل'}</span>{row.warehouseName&&<span><AppIcon name="warehouse" size={16}/>{row.warehouseName}</span>}</div>
   {(row.items||[]).length>0&&<div className="purchaseHubItems"><table><thead><tr><th scope="col">المادة</th><th scope="col">العدد</th><th scope="col">سعر الوحدة</th><th scope="col">المجموع</th></tr></thead><tbody>{row.items.map((item,index)=>{
    const unitPrice=purchaseUnitPrice(item,currency,row.exchangeRate);
    return <tr key={item.id+':'+index}><th scope="row">{item.name}<small>{[item.brand,item.category].filter(Boolean).join(' · ')}</small></th><td>{preciseNumber(item.qty)}</td><td><bdi>{preciseNumber(unitPrice)} {currencyUnit(currency)}</bdi></td><td><bdi>{money(item.qty*unitPrice)}</bdi></td></tr>;
   })}</tbody></table></div>}
   {row.expenses>0&&<p>مصاريف إضافية <bdi>{formatMoney(row.expenses)} د.ع</bdi></p>}
   {row.notes&&<p>{row.notes}</p>}
   <div className="purchaseHubReceiptActions"><button type="button" aria-label={'تعديل الوصل رقم '+number} onClick={()=>onEdit(row)}><AppIcon name="edit" size={16}/>تعديل الوصل</button><button type="button" className="purchaseHubDelete" aria-label={'حذف الوصل رقم '+number} onClick={()=>onDelete(row)}><AppIcon name="trash" size={16}/>حذف الوصل</button>{renderExport(row)}</div>
  </div>}
 </article>;
}

export default function PurchasesHub({history,onNew,onMaterial,onEdit,onDelete,onRefresh,refreshing,renderExport}){
 const [query,setQuery]=useState(''),[limit,setLimit]=useState(pageSize);
 const ordered=useMemo(()=>history.slice().sort((a,b)=>new Date(b.date)-new Date(a.date)||b.id-a.id),[history]);
 const filtered=useMemo(()=>ordered.filter(row=>matchesReceipt(row,query)),[ordered,query]);
 return <section className="purchasesHub" data-purchases-hub="" aria-label="المشتريات">
  <nav className="purchaseHubActions" aria-label="إجراءات المشتريات">
   <button type="button" onClick={onNew}><AppIcon name="add" size={20}/>فاتورة شراء جديدة</button>
   {onMaterial&&<button className="purchaseHubMaterial" type="button" onClick={onMaterial}><AppIcon name="package" size={20}/>تعريف مادة جديدة</button>}
  </nav>
  <section className="purchaseHubArchive" aria-labelledby="purchase-archive-title">
   <header><div><h2 id="purchase-archive-title">المشتريات السابقة</h2><small>{history.length.toLocaleString('ar-IQ')} فاتورة شراء</small></div><button type="button" className="purchaseHubRefresh" onClick={onRefresh} disabled={refreshing} aria-label="تحديث المشتريات"><AppIcon name="refresh" size={19}/></button></header>
   <label className="purchaseHubSearch"><AppIcon name="search" size={18}/><input type="search" aria-label="بحث المشتريات السابقة" placeholder="ابحث برقم الوصل أو اسم المورد" value={query} onChange={e=>{setQuery(e.target.value);setLimit(pageSize);}}/></label>
   {filtered.length?filtered.slice(0,limit).map(row=><PurchaseReceipt key={row.id} row={row} onEdit={onEdit} onDelete={onDelete} renderExport={renderExport}/>):<p className="purchaseHubEmpty" role="status">{query?'لا توجد فواتير مطابقة للبحث.':'لا توجد فواتير شراء محفوظة.'}</p>}
   {filtered.length>limit&&<button type="button" className="purchaseHubMore" onClick={()=>setLimit(n=>n+pageSize)}>عرض المزيد <AppIcon name="chevron" size={16}/></button>}
  </section>
 </section>;
}
