'use client';
import {useState} from 'react';
import AppIcon from './app-icons';
import {sections,sectionGroups} from './section-directory.mjs';
import {canOpenPage} from './access-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
const labels=new Map(sections.flatMap(([,rows])=>rows));
export default function WorkspaceSections({profile,page,onNavigate}){
 const [query,setQuery]=useState(''),[picked,setPicked]=useState(()=>sectionGroups.find(g=>g.ids.includes(page))?.id||'sales');
 const groups=sectionGroups.map(g=>({...g,ids:g.ids.filter(id=>canOpenPage(profile,id))})).filter(g=>g.ids.length),active=groups.find(g=>g.id===picked)||groups[0],needle=normalizeSearch(query);
 const rows=(needle?groups.flatMap(g=>g.ids):active?.ids||[]).filter(id=>normalizeSearch(labels.get(id)).includes(needle));
 return <div className="workspaceSectionPicker"><label className="workspaceSectionSearch"><AppIcon name="search" size={19}/><input aria-label="البحث عن قسم" value={query} onChange={e=>setQuery(e.target.value)} placeholder="أي قسم تريد تفتح؟" autoComplete="off"/>{query&&<button type="button" aria-label="مسح بحث الأقسام" onClick={()=>setQuery('')}><AppIcon name="close" size={17}/></button>}</label>{!needle&&<nav className="workspaceCategoryTabs" aria-label="مجموعات الأقسام">{groups.map(g=><button type="button" key={g.id} aria-pressed={active?.id===g.id} onClick={()=>setPicked(g.id)}><AppIcon name={g.icon} size={18}/><span>{g.title}</span></button>)}</nav>}<div className="workspaceSectionResults" aria-live="polite"><span>{needle?'نتائج البحث':active?.title}</span><small>{rows.length} قسم</small></div><div className="workspaceSectionLinks">{rows.map(id=><a key={id} href={'/?section='+id} aria-current={page===id?'page':undefined} onClick={e=>{if(e.ctrlKey||e.metaKey||e.shiftKey||e.altKey)return;e.preventDefault();onNavigate(id);}}><span><AppIcon name={id} size={21}/></span><b>{labels.get(id)}</b><AppIcon name="arrow" size={15}/></a>)}</div>{!rows.length&&<p className="uiEmpty">ماكو قسم بهذا الاسم.</p>}</div>;
}
