'use client';
import AppIcon from './app-icons';
import {sections,sectionGroups} from './section-directory.mjs';
import {canOpenPage} from './access-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
const labels=new Map(sections.flatMap(([,rows])=>rows));
export default function AlternativeSectionDirectory({mode,profile,query='',onNavigate}){
 const needle=normalizeSearch(query),groups=sectionGroups.map(g=>({...g,rows:g.ids.filter(id=>canOpenPage(profile,id)&&normalizeSearch(labels.get(id)).includes(needle))})).filter(g=>g.rows.length);
 return <nav className={'alternativeSections '+(mode==='premium'?'premiumSectionDirectory':'deskSectionDirectory')} aria-label={mode==='premium'?'أقسام بتصميم بريميوم':'أقسام بتصميم المكتب'}>{groups.map((g,index)=><section className={'alternativeSection '+g.color} key={g.id}><header><span className="alternativeCategoryIcon"><AppIcon name={g.icon} size={21}/></span><div><small>{String(index+1).padStart(2,'0')} · {g.rows.length} أقسام</small><h2>{g.title}</h2>{mode==='premium'&&<p>{g.description}</p>}</div></header><div className="alternativeSectionLinks">{g.rows.map(id=><a key={id} href={'/?section='+id} onClick={e=>{e.preventDefault();onNavigate(id);}}><span><AppIcon name={id} size={20}/></span><b>{labels.get(id)}</b><AppIcon name="arrow" size={14}/></a>)}</div></section>)}{!groups.length&&<p className="uiEmpty">لا يوجد قسم بهذا الاسم.</p>}</nav>;
}
