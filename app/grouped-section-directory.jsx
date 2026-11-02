'use client';
import {useState} from 'react';
import AppIcon from './app-icons';
import {sections,sectionGroups} from './section-directory.mjs';
import {orderedSections} from './section-layout-utils.mjs';
import {canOpenPage} from './access-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';

const all=sections.flatMap(([,rows])=>rows),labels=new Map(all);
export default function GroupedSectionDirectory({profile,order=[],query='',onNavigate}){
 const [picked,setPicked]=useState(()=>{try{return sessionStorage.getItem('solar-section-group:'+profile.id)||'sales';}catch{return 'sales';}});
 const filtered=sectionGroups.map(group=>({...group,rows:orderedSections(group.ids.map(id=>[id,labels.get(id)]).filter(([id])=>canOpenPage(profile,id)),group.fixedOrder?[]:order)
  .filter(([,label])=>normalizeSearch(label).includes(normalizeSearch(query)))})).filter(g=>g.rows.length);
 const active=filtered.find(g=>g.id===picked)||filtered[0],searching=!!normalizeSearch(query),shown=searching?filtered:active?[active]:[],short={sales:'المبيعات',purchases:'المشتريات',inventory:'المخزون',finance:'المالية',reports:'التحصيل والضمان',settings:'الإعدادات'};
 const quick=['sale','system','salesHistory','tahseel','cash','warehouse','installations'].filter(id=>canOpenPage(profile,id)).slice(0,3);
 function go(e,id){if(e.ctrlKey||e.metaKey||e.shiftKey||e.altKey)return;e.preventDefault();onNavigate(id);}
 function select(id){setPicked(id);try{sessionStorage.setItem('solar-section-group:'+profile.id,id);}catch{}}
 return <nav className="groupedSectionDirectory workspaceHomeDirectory" aria-label="أقسام البرنامج حسب المجموعات">{!searching&&<><div className="workspaceQuickHeading">وصول سريع</div><div className="workspaceHomeQuick">{quick.map(id=><a href={'/?section='+id} key={id} onClick={e=>go(e,id)}><AppIcon name={id} size={21}/><span>{labels.get(id)}</span></a>)}</div><div className="workspaceHomeTabs" aria-label="مجموعات أقسام البرنامج">{filtered.map(g=><button type="button" key={g.id} aria-pressed={active?.id===g.id} onClick={()=>select(g.id)}><AppIcon name={g.icon} size={21}/><span>{short[g.id]}</span></button>)}</div></>}{shown.map(group=><section className={'workspaceHomeGroup '+group.color} key={group.id}><header><div><h2>{group.title}</h2><p>{group.description}</p></div><small>{group.rows.length} قسم</small></header><div className="workspaceHomeLinks">{group.rows.map(([id,label])=><a key={id} href={'/?section='+id} onClick={e=>go(e,id)}><span className="workspaceHomeIcon"><AppIcon name={id} size={22}/></span><b>{label}</b><AppIcon name="arrow" size={16}/></a>)}</div></section>)}{!filtered.length&&<p className="uiEmpty">لا يوجد قسم بهذا الاسم.</p>}</nav>;
}
