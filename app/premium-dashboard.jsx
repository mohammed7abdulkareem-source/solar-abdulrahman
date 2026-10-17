'use client';
import {useState} from 'react';
import {sections} from './section-directory.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import AppIcon from './app-icons';
import SalesTrend from './sales-trend';
import {canOpenPage,canSeeCash,isAdministrator} from './access-utils.mjs';
import {capitalAccounts} from './capital-reports.mjs';
import {formatMoney as money} from './money-format.mjs';
import {dateKey} from './supplier-utils.mjs';
export default function PremiumDashboard({profile,ready,tx,products,customers,cash,onNavigate,onRefresh}){
 const can=id=>canOpenPage(profile,id),admin=isAdministrator(profile),field=['installer','warehouse'].includes(profile.user_type),today=dateKey(new Date()),daily=tx.filter(t=>['sale','system'].includes(t.kind)&&dateKey(t.date)===today),dailySales=daily.reduce((s,t)=>s+Number(t.total||0),0),stock=products.reduce((s,p)=>s+Math.max(0,Number(p.qty||0))*Number(p.cost||0),0),debt=capitalAccounts(tx,customers).total;
 const metrics=[...(can('sale')||can('system')?[{id:'salesHistory',title:'إجمالي مبيعات اليوم',value:dailySales,detail:daily.length+' فاتورة',icon:'receipt',color:'teal'}]:[]),...(!field&&can('stock')?[{id:'stock',title:'المخزون بالكلفة',value:stock,detail:'رصيد المواد الحالي',icon:'package',color:'blue'}]:[]),...(canSeeCash(profile)?[{id:'cash',title:admin?'الصندوق بالدينار':'قاصتي بالدينار',value:cash.IQD,detail:admin?'كل القاصات':'قاصة المستخدم',icon:'wallet',color:'gold'}]:[]),...(!field&&can('customerDebts')?[{id:'customerDebts',title:'ديون العملاء لنا',value:debt,detail:'أرصدة الحسابات',icon:'users',color:'violet'}]:[])];
 const [sectionQuery,setSectionQuery]=useState('');
 const colors={sale:'blue',system:'teal',purchase:'purple',stock:'teal',customerPayment:'green',systemPayment:'green',supplierPayment:'red',customers:'pink',suppliers:'purple',products:'orange',customerDebts:'orange',profit:'blue',cash:'green'};
 const visible=sections.map(([title,rows])=>[title,rows.filter(([id,label])=>id!=='home'&&can(id)&&normalizeSearch(label).includes(normalizeSearch(sectionQuery)))]).filter(([,rows])=>rows.length);
 return <section className="premiumDashboard clarityDashboard"><header className="clarityHomeHeading"><div><h1>أقسام البرنامج</h1><p>أهلًا {profile.display_name||profile.username}</p></div><button type="button" className="premiumButton secondary" onClick={onRefresh}><AppIcon name="refresh" size={17}/>تحديث</button></header>
 <label className="sectionGridSearch"><AppIcon name="search" size={18}/><input aria-label="البحث في الأقسام" placeholder="ابحث عن القسم المطلوب…" value={sectionQuery} onChange={e=>setSectionQuery(e.target.value)}/></label>
 <nav className="sectionDirectory" aria-label="كل أقسام البرنامج">{visible.map(([title,rows],groupIndex)=><section key={title}><h2>{title}</h2><div className="sectionTileGrid">{rows.map(([id,label],index)=><a key={id} className={'sectionTile '+(colors[id]||['blue','purple','teal','orange','green','pink'][(index+groupIndex)%6])} href={'/?section='+id} onClick={e=>{e.preventDefault();onNavigate(id);}}><span><AppIcon name={id} size={25}/></span><b>{label}</b></a>)}</div></section>)}{!visible.length&&<p className="uiEmpty">لا يوجد قسم بهذا الاسم.</p>}</nav>
 {!!metrics.length&&<div className="premiumMetrics">{metrics.map(m=><button type="button" key={m.id} onClick={()=>can(m.id)&&onNavigate(m.id)} disabled={!can(m.id)} aria-label={'فتح '+m.title}><div><span>{m.title}</span><i className={m.color}><AppIcon name={m.icon}/></i></div><strong>{ready?money(m.value):'—'} <small>د.ع</small></strong><small>{m.detail}{m.id==='cash'&&Number(cash.USD)!==0&&<bdi> · {money(cash.USD,'USD')} $</bdi>}</small></button>)}</div>}
 {!field&&(can('sale')||can('system')||can('profit'))&&<SalesTrend rows={tx}/>}
 </section>;
}
