'use client';
import {useMemo,useState} from 'react';
import AppIcon from './app-icons';
import {balanceDate} from './party-balances-utils.mjs';
import {formatMoney,currencyUnit} from './money-format.mjs';
import {normalizeSearch} from './party-search-utils.mjs';

const tabs=[['all','كل الوصولات'],['sales','مبيعات'],['payments','تسديدات']];
const pageSize=20;

export default function CustomerReceiptManager({rows,currency,renderActions}){
 const [tab,setTab]=useState('all'),[query,setQuery]=useState(''),[limit,setLimit]=useState(pageSize);
 const selected=useMemo(()=>{
  const words=normalizeSearch(query).replace(/^#\s*/,'').split(/\s+/).filter(Boolean);
  return rows.filter(row=>{
   const sale=['sale','system'].includes(row.kind);
   if((tab==='sales'&&!sale)||(tab==='payments'&&sale))return false;
   const text=normalizeSearch([row.receiptNo??row.id,row.label,balanceDate(row.date),row.notes].join(' '));
   return words.every(word=>text.includes(word));
  }).sort((a,b)=>new Date(b.date)-new Date(a.date)||Number(b.id)-Number(a.id));
 },[rows,tab,query]);
 return <section className="statementReceiptManager" aria-label="إدارة وصولات العميل">
  <div className="miniSegments" role="group" aria-label="نوع الوصل">{tabs.map(([value,label])=><button type="button" key={value} aria-pressed={tab===value} onClick={()=>{setTab(value);setLimit(pageSize);}}>{label}</button>)}</div>
  <label className="miniSearch"><AppIcon name="search" size={18}/><input type="search" aria-label="بحث في الوصولات المتاحة" placeholder="رقم الوصل أو البيان" value={query} onChange={e=>{setQuery(e.target.value);setLimit(pageSize);}}/></label>
  <div className="statementReceiptList">{selected.slice(0,limit).map(row=><article key={row.id} className="statementManageReceipt" aria-label={row.label+' رقم '+(row.receiptNo??row.id)}>
   <div className="statementManageReceiptInfo"><div><strong>{row.label} <bdi>#{row.receiptNo??row.id}</bdi></strong><small>{balanceDate(row.date)}</small></div><bdi>{formatMoney(row.amount,currency)} {currencyUnit(currency)}</bdi></div>
   {renderActions(row)}
  </article>)}</div>
  {!selected.length&&<p className="miniEmpty">{query.trim()?'لا توجد وصولات تطابق البحث.':'لا توجد وصولات متاحة للتعديل أو الحذف ضمن هذا الاختيار.'}</p>}
  {selected.length>limit&&<button type="button" className="miniSecondary" onClick={()=>setLimit(n=>n+pageSize)}>عرض المزيد من الوصولات</button>}
 </section>;
}
