'use client';
import {userDisplayName} from './user-name-utils.mjs';

import {useEffect,useState} from 'react';
import {canOpenPage} from './access-utils.mjs';
import {useSectionLayout} from './section-layout';
import SectionDesignSelector from './section-design-selector';
import QuickSearch from './quick-search';
import AppIcon from './app-icons';
import ExchangeRateSync from './exchange-rate-sync';
export default function AppFrame({profile,page,onNavigate,onOpenAccount,toolbar,onLogout,children}){
 const [searching,setSearching]=useState(false);
 const sectionState=useSectionLayout(profile.id);
 useEffect(()=>{const meta=document.querySelector('meta[name=theme-color]');if(!meta)return;const previous=meta.content;meta.content=sectionState.layout.mode==='premium'?'#090f1b':'#123c48';return()=>{meta.content=previous;};},[sectionState.layout.mode]);
 const go=(event,id)=>{event?.preventDefault();setSearching(false);onNavigate(id);};
 useEffect(()=>{setSearching(false);},[page]);
 useEffect(()=>{const keys=e=>{if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='k'){e.preventDefault();setSearching(v=>!v);}};window.addEventListener('keydown',keys);return()=>window.removeEventListener('keydown',keys);},[]);
 const baseShortcuts=[['home','الرئيسية'],...['sale','cash','warehouse','installations'].filter(id=>canOpenPage(profile,id)).slice(0,2).map(id=>[id,{sale:'بيع جديد',cash:'الصندوق',warehouse:'المخزن',installations:'المهام'}[id]])];
 const partyPage=['customers','customerCreate','customerStatement','suppliers','supplierStatement'].includes(page),shortcuts=partyPage?[['home','الرئيسية'],...[['customers','العملاء'],['suppliers','الموردون']].filter(([id])=>canOpenPage(profile,id))]:baseShortcuts;
 return <div className={'appFrame clarityFrame'+(sectionState.layout.mode==='solar'?' solarHorizonTheme':sectionState.layout.mode==='premium'?' premiumExperience':'')}><ExchangeRateSync profile={profile}/><div className="appContent"><header className="premiumTopbar"><a className="premiumMobileBrand" href="/" onClick={e=>go(e,'home')}><span><img src="/icon-192.png" alt="" width="34" height="34" style={{borderRadius:9}}/></span><div><b>عبدالرحمن سولار</b><small>{userDisplayName(profile)}</small></div></a><button type="button" className="sectionsTopButton" onClick={e=>go(e,'home')}><AppIcon name="grid" size={18}/>الأقسام</button><button type="button" className="globalSearchTopButton" onClick={()=>setSearching(true)} aria-label="فتح البحث العام"><AppIcon name="search" size={18}/><span>بحث عن زبون، مادة أو قسم…</span><kbd>Ctrl K</kbd></button>{sectionState.layout.mode==='premium'&&<span className="premiumFrameBadge">PREMIUM</span>}<div className="premiumTopTools"><SectionDesignSelector state={sectionState}/>{toolbar}<button type="button" className="clarityLogout" aria-label="تسجيل خروج" title="تسجيل خروج" onClick={onLogout}><AppIcon name="signout" size={17}/></button></div></header>{children}</div><nav className="appMobileBar" aria-label="التنقل السريع">{shortcuts.map(([id,label])=><a href={id==='home'?'/?':'/?section='+id} onClick={e=>go(e,id)} key={id} aria-current={page===id||(id==='customers'&&(page==='customerStatement'||page==='customerCreate'))||(id==='suppliers'&&page==='supplierStatement')?'page':undefined}><span><AppIcon name={id}/></span><span>{label}</span></a>)}<button type="button" onClick={()=>setSearching(true)} aria-label="فتح البحث العام" aria-expanded={searching}><span><AppIcon name="search"/></span><span>بحث</span></button><button type="button" onClick={e=>go(e,'home')}><span><AppIcon name="grid"/></span><span>الأقسام</span></button></nav><QuickSearch open={searching} onClose={()=>setSearching(false)} profile={profile} onNavigate={onNavigate} onOpenAccount={onOpenAccount}/></div>;
}
