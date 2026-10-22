'use client';
import {useState} from 'react';
import AppIcon from './app-icons';
import {sections,sectionGroups} from './section-directory.mjs';
import {canOpenPage} from './access-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
const labels=new Map(sections.flatMap(([,rows])=>rows));
const quickChoices={installer:['installations'],warehouse:['warehouse','stock','stockMovement'],default:['sale','system','salesHistory','cash','installations','purchase','customers']};
export default function PremiumCommandDirectory({profile,query='',onNavigate}){
 const [picked,setPicked]=useState('sales'),needle=normalizeSearch(query),groups=sectionGroups.map(g=>({...g,rows:g.ids.filter(id=>canOpenPage(profile,id)&&normalizeSearch(labels.get(id)).includes(needle))})).filter(g=>g.rows.length),active=groups.find(g=>g.id===picked)||groups[0];
 const quick=(quickChoices[profile.user_type]||quickChoices.default).filter(id=>canOpenPage(profile,id)&&normalizeSearch(labels.get(id)).includes(needle)).slice(0,3),count=groups.reduce((n,g)=>n+g.rows.length,0);
 function go(event,id){event.preventDefault();onNavigate(id);}
 function selectGroup(id){setPicked(id);}
 return <section className="premiumSectionDirectory premiumCommandDirectory" aria-label="مساحة بريميوم"><div className="premiumCommandHero"><div className="premiumHeroCopy"><div className="premiumEdition"><span/> PREMIUM WORKSPACE</div><h2>مساحة عملك،<br/><em>بأسلوب بريميوم.</em></h2><p>كل قسم بمكانه. وخطوتك الجاية أقرب.</p><div className="premiumHeroMeta"><span><b>{String(count).padStart(2,'0')}</b> قسم متاح لك</span><span><b>{String(groups.length).padStart(2,'0')}</b> مسارات عمل</span></div></div><div className="premiumOrbit" aria-hidden="true"><span className="premiumOrbitLine orbitOne"/><span className="premiumOrbitLine orbitTwo"/><span className="premiumOrbSun"/><span className="premiumOrbitDot"/><div>SOLAR<br/><b>PREMIUM</b></div></div></div>
  {quick.length>0&&<nav className="premiumLaunchpad" aria-label="إجراءات بريميوم السريعة">{quick.map((id,i)=><a className={i===0?'premiumLaunch featured':'premiumLaunch'} key={id} href={'/?section='+id} onClick={e=>go(e,id)}><span className="premiumLaunchIcon"><AppIcon name={id} size={21}/></span><div><small>{i===0?'ابدأ من هنا':'وصول سريع'}</small><b>{labels.get(id)}</b></div><AppIcon name="arrow" size={17}/></a>)}</nav>}
  <div className="premiumBrowseHeading"><div><span>دليل العمل</span><h3>أقسامك، بوضوح.</h3></div><small>{groups.length} مجموعات</small></div>
  {active?<div className="premiumCommandConsole"><nav className="premiumCategoryRail" aria-label="مجموعات بريميوم">{groups.map((g,i)=><button type="button" key={g.id} className={g.color} aria-pressed={g.id===active.id} onClick={()=>selectGroup(g.id)}><span className="premiumRailIcon"><AppIcon name={g.icon} size={19}/></span><span><small>{String(i+1).padStart(2,'0')}</small><b>{g.title}</b></span><i>{g.rows.length}</i></button>)}</nav><section className={'premiumFocusPanel '+active.color} aria-label={active.title}><header><div><small>المسار الحالي</small><h3>{active.title}</h3><p>{active.description}</p></div><span><AppIcon name={active.icon} size={22}/></span></header><div className="premiumCommandLinks">{active.rows.map((id,i)=><a key={id} href={'/?section='+id} onClick={e=>go(e,id)}><span className="premiumCommandIcon"><AppIcon name={id} size={20}/></span><div><b>{labels.get(id)}</b><small>فتح القسم</small></div><span className="premiumCommandEnd"><small>{String(i+1).padStart(2,'0')}</small><AppIcon name="arrow" size={15}/></span></a>)}</div></section></div>:<div className="premiumCommandEmpty">لا يوجد قسم بهذا الاسم.</div>}
 </section>;
}
