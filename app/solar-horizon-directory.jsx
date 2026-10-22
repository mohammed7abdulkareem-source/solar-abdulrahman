'use client';
import {useState} from 'react';
import AppIcon from './app-icons';
import {sections,sectionGroups} from './section-directory.mjs';
import {canOpenPage} from './access-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
const labels=new Map(sections.flatMap(([,rows])=>rows));
export default function SolarHorizonDirectory({profile,query='',onNavigate}){
 const [selected,setSelected]=useState('sales'),needle=normalizeSearch(query),groups=sectionGroups.map(g=>({...g,rows:g.ids.filter(id=>canOpenPage(profile,id)&&normalizeSearch(labels.get(id)).includes(needle))})).filter(g=>g.rows.length),active=groups.find(g=>g.id===selected)||groups[0];
 const quick=['sale','system','purchase','warehouse','installations','cash','customerStatement'].filter(id=>canOpenPage(profile,id)&&normalizeSearch(labels.get(id)).includes(needle)).slice(0,4);
 function moveTab(event){const index=groups.findIndex(g=>g.id===active.id);let next;if(event.key==='ArrowLeft')next=(index+1)%groups.length;else if(event.key==='ArrowRight')next=(index+groups.length-1)%groups.length;else if(event.key==='Home')next=0;else if(event.key==='End')next=groups.length-1;else return;event.preventDefault();setSelected(groups[next].id);requestAnimationFrame(()=>document.getElementById('solar-tab-'+groups[next].id)?.focus());}
 const link=(event,id)=>{event.preventDefault();onNavigate(id);};
 return <section className="solarHorizonDirectory" aria-label="أقسام أفق سولار"><header className="solarHorizonHero"><div><small><span/> مساحة عمل الطاقة الشمسية</small><h2>أفق <strong>سولار</strong></h2><p>أعمالك اليومية بمكان واحد</p><div className="solarHorizonCounts"><span>{groups.reduce((n,g)=>n+g.rows.length,0)} قسم متاح</span><span>{groups.length} مسارات عمل</span></div></div><div className="solarHorizonArt" aria-hidden="true"><AppIcon name="sun" size={49}/><span>{Array.from({length:8},(_,i)=><i key={i}/>)}</span></div></header>
  {groups.length?<div className="solarHorizonConsole"><nav role="tablist" aria-label="مسارات أفق سولار" onKeyDown={moveTab}>{groups.map(g=><button type="button" key={g.id} id={'solar-tab-'+g.id} role="tab" tabIndex={g.id===active.id?0:-1} aria-selected={g.id===active.id} aria-controls="solar-horizon-panel" onClick={()=>setSelected(g.id)}><AppIcon name={g.icon} size={18}/><span>{g.title}</span><small>{g.rows.length}</small></button>)}</nav><div className="solarHorizonPanel" role="tabpanel" id="solar-horizon-panel" aria-labelledby={'solar-tab-'+active.id}><header><div><small>مسار العمل</small><h3>{active.title}</h3><p>{active.description}</p></div><span><AppIcon name={active.icon} size={23}/></span></header><div className="solarHorizonActions">{active.rows.map((id,i)=><a key={id} href={'/?section='+id} onClick={e=>link(e,id)}><small>{String(i+1).padStart(2,'0')}</small><span><AppIcon name={id} size={21}/></span><b>{labels.get(id)}</b><AppIcon name="arrow" size={16}/></a>)}</div></div></div>:<p className="uiEmpty">لا يوجد قسم بهذا الاسم.</p>}
  {quick.length>1&&<aside className="solarHorizonQuick"><h3>وصول سريع</h3><div>{quick.map(id=><a key={id} href={'/?section='+id} onClick={e=>link(e,id)}><AppIcon name={id} size={17}/>{labels.get(id)}</a>)}</div></aside>}
 </section>;
}
