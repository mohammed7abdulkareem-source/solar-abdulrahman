'use client';
import {useId} from 'react';
import AppIcon from './app-icons';
import {sections,sectionGroups} from './section-directory.mjs';
import {orderedSections} from './section-layout-utils.mjs';
import {canOpenPage} from './access-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';

const labels=new Map(sections.flatMap(([,rows])=>rows));
const tones={sale:'blue',system:'teal',salesHistory:'indigo',deletionRequests:'rose',customerCreate:'sky',customerPayment:'emerald',systemPayment:'teal',customerDebts:'amber',customerStatement:'cyan',customers:'violet',purchase:'blue',suppliers:'violet',supplierPayment:'amber',supplierStatement:'cyan',supplierBalances:'indigo',products:'sky',stock:'teal',stockMovement:'blue',warehouse:'amber',installations:'violet',brands:'rose',cash:'emerald',capital:'indigo',cashTransfers:'cyan',profit:'teal',paymentHistory:'blue',exchangeRate:'amber',tahseel:'amber',warranty:'teal',users:'violet',operationControl:'rose',updates:'slate'};

// Every permitted section stays in the page. Category links only scroll;
// they never replace or collapse another category's contents.
export default function GeneralSectionDirectory({profile,order=[],query='',onNavigate,compact=false,page='home'}){
 const prefix='general-'+useId().replace(/:/g,''),needle=normalizeSearch(query);
 const groups=sectionGroups.map(group=>({...group,rows:orderedSections(group.ids.map(id=>[id,labels.get(id)]).filter(([id])=>canOpenPage(profile,id)),order)
  .filter(([,label])=>!needle||normalizeSearch(label+' '+group.title).includes(needle))})).filter(group=>group.rows.length);
 const total=groups.reduce((sum,group)=>sum+group.rows.length,0);
 function go(event,id){if(event.ctrlKey||event.metaKey||event.shiftKey||event.altKey)return;event.preventDefault();onNavigate(id);}
 function jump(event,id){event.preventDefault();document.getElementById(prefix+'-'+id)?.scrollIntoView({block:'start',behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'});}
 return <div className={'generalDirectory'+(compact?' generalDirectoryCompact':'')}>
  <div className="generalDirectorySummary"><span><AppIcon name="grid" size={17}/>{needle?'نتائج البحث':'كل أقسامك بمكان واحد'}</span><b aria-live="polite">{total} قسم</b></div>
  {!needle&&groups.length>1&&<nav className="generalCategoryNav" aria-label="الانتقال إلى مجموعة أقسام">{groups.map(group=><a key={group.id} href={'#'+prefix+'-'+group.id} onClick={event=>jump(event,group.id)}><AppIcon name={group.icon} size={17}/><span>{group.title}</span></a>)}</nav>}
  <nav className="generalSectionGroups" aria-label="جميع أقسام التصميم العام">{groups.map(group=><section className={'generalSectionGroup '+group.color} key={group.id} id={prefix+'-'+group.id} aria-labelledby={prefix+'-'+group.id+'-title'}>
   <header><span className="generalGroupMark"><AppIcon name={group.icon} size={18}/></span><h2 id={prefix+'-'+group.id+'-title'}>{group.title}</h2><small>{group.rows.length} قسم</small></header>
   <div className="generalSectionGrid">{group.rows.map(([id,label])=><a className={'generalSectionCard tone-'+(tones[id]||'teal')} key={id} href={'/?section='+id} aria-current={page===id?'page':undefined} onClick={event=>go(event,id)}><span className="generalSectionIcon"><AppIcon name={id} size={24}/></span><b>{label}</b><AppIcon name="arrow" size={15}/></a>)}</div>
  </section>)}</nav>
  {!total&&<div className="generalSearchEmpty" role="status"><AppIcon name="search" size={26}/><b>لا توجد أقسام بهذا الاسم</b><p>جرّب اسم القسم أو المجموعة.</p></div>}
 </div>;
}
