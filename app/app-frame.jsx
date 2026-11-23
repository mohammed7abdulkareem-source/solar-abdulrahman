'use client';
import {useCallback,useEffect,useRef,useState} from 'react';
import {userDisplayName} from './user-name-utils.mjs';
import {salesAuthorizationKey} from './sales-read-scope.mjs';
import {searchCategories} from './quick-search-utils.mjs';
import {canOpenPage} from './access-utils.mjs';
import {useSectionLayout,SectionLayoutContext} from './section-layout';
import {sections} from './section-directory.mjs';
import SectionDesignSelector from './section-design-selector';
import QuickSearch from './quick-search';
import AppIcon from './app-icons';
import ExchangeRateSync from './exchange-rate-sync';
import WorkspaceDialog from './workspace-dialog';
import WorkspaceSections from './workspace-sections';
import WorkspaceBoundary from './workspace-boundary';
import PasswordChange from './password-change.jsx';
import {APP_VERSION} from './app-update';
const titles=new Map(sections.flatMap(([,rows])=>rows));
export default function AppFrame(props){
 return <ScopedAppFrame key={salesAuthorizationKey(props.profile)} {...props}/>;
}
function ScopedAppFrame({profile,page,onNavigate,onOpenAccount,toolbar,accountTools,status,onLogout,children}){
 const [searching,setSearching]=useState(false),[menu,setMenu]=useState(''),[offline,setOffline]=useState(false),[keyboard,setKeyboard]=useState(false),frameRef=useRef(null),passwordPending=useRef(false);
 const passwordBusyChange=useCallback(value=>{passwordPending.current=value;},[]);
 const sectionState=useSectionLayout(profile.id),name=userDisplayName(profile),authorized=canOpenPage(profile,page),title=authorized?(titles.get(page)||'الرئيسية'):'الرئيسية';
 useEffect(()=>{const previous=document.body.dataset.workspaceDesign;document.body.dataset.workspaceDesign=sectionState.layout.mode;return()=>{if(previous===undefined)delete document.body.dataset.workspaceDesign;else document.body.dataset.workspaceDesign=previous;};},[sectionState.layout.mode]);
 useEffect(()=>{const meta=document.querySelector('meta[name=theme-color]');if(!meta)return;const previous=meta.content;meta.content=sectionState.layout.mode==='premium'?'#090f1b':'#f7fafb';return()=>{meta.content=previous;};},[sectionState.layout.mode]);
 function go(event,id){if(passwordPending.current||!canOpenPage(profile,id)){event?.preventDefault();return false;}if(event&&(event.ctrlKey||event.metaKey||event.shiftKey||event.altKey))return;event?.preventDefault();if(onNavigate(id)===false)return false;setSearching(false);setMenu('');return true;}
 useEffect(()=>{setSearching(false);setMenu('');document.title=title+' | عبدالرحمن سولار';},[page,title]);
 useEffect(()=>{
  const keys=e=>{if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='k'){e.preventDefault();if(passwordPending.current)return;setMenu('');setSearching(v=>!v);}};
  const online=()=>setOffline(!navigator.onLine);online();window.addEventListener('keydown',keys);window.addEventListener('online',online);window.addEventListener('offline',online);
  return()=>{window.removeEventListener('keydown',keys);window.removeEventListener('online',online);window.removeEventListener('offline',online);};
 },[]);
 useEffect(()=>{
  const viewport=window.visualViewport, frame=frameRef.current;
  if(!viewport||!frame)return;
  let lastWidth=window.innerWidth, restingHeight=viewport.height, animation=0;
  function update(){
   const editing=document.activeElement?.matches('input:not([type=checkbox]):not([type=radio]),textarea');
   const layoutHeight=document.documentElement.clientHeight;
   if(lastWidth!==window.innerWidth||!editing)restingHeight=viewport.height;
   lastWidth=window.innerWidth;
   // Safari can pan the visible window independently while a form field is focused.
   const atNormalScale=Math.abs(viewport.scale-1)<0.01;
   const top=atNormalScale?Math.max(0,viewport.offsetTop):0;
   const bottom=atNormalScale?Math.max(0,layoutHeight-viewport.height-top):0;
   frame.style.setProperty('--workspace-viewport-top',top+'px');
   frame.style.setProperty('--workspace-viewport-bottom',bottom+'px');
   setKeyboard(!!editing&&atNormalScale&&Math.max(layoutHeight-viewport.height,restingHeight-viewport.height)>120);
  }
  function schedule(){cancelAnimationFrame(animation);animation=requestAnimationFrame(update);}
  update();
  viewport.addEventListener('scroll',schedule);viewport.addEventListener('resize',schedule);
  window.addEventListener('resize',schedule);
  document.addEventListener('focusin',schedule);document.addEventListener('focusout',schedule);
  return ()=>{
   cancelAnimationFrame(animation);
   viewport.removeEventListener('scroll',schedule);viewport.removeEventListener('resize',schedule);
   window.removeEventListener('resize',schedule);
   document.removeEventListener('focusin',schedule);document.removeEventListener('focusout',schedule);
  };
 },[]);
 const shortcuts=[['home','الرئيسية'],...['sale','cash','warehouse','installations','tahseel','warranty'].filter(id=>canOpenPage(profile,id)).slice(0,2).map(id=>[id,{sale:'بيع جديد',cash:'الصندوق',warehouse:'المخزن',installations:'المهام',tahseel:'التحصيل',warranty:'الضمان'}[id]])];
 return <div ref={frameRef} className={'appFrame clarityFrame smoothFrame'+(keyboard?' workspaceKeyboard':'')+(sectionState.layout.mode==='general'?' generalDesignTheme':sectionState.layout.mode==='solar'?' solarHorizonTheme':sectionState.layout.mode==='premium'?' premiumExperience':'')}><ExchangeRateSync profile={profile}/><div className="appContent"><header className="premiumTopbar"><a className="premiumMobileBrand" href="/" onClick={e=>go(e,'home')}><img src="/icon-192.png" alt="" width="38" height="38"/><div><b>عبدالرحمن سولار</b><small>{page==='home'?name:title}</small></div></a><button type="button" className="sectionsTopButton" onClick={()=>setMenu('sections')} aria-expanded={menu==='sections'}><AppIcon name="grid" size={19}/>الأقسام</button><button type="button" className="globalSearchTopButton" onClick={()=>{setMenu('');setSearching(true);}} aria-label="فتح البحث العام"><AppIcon name="search" size={19}/><span>{searchCategories(profile).length>1?'البحث في البرنامج…':'البحث عن قسم…'}</span><kbd>⌘ K</kbd></button><div className="premiumTopTools">{toolbar}<button type="button" className="workspaceAccountButton" aria-label="فتح قائمة حسابي" aria-expanded={menu==='account'} title={name} onClick={()=>setMenu('account')}><span>{name.trim().slice(0,1)||'ح'}</span></button></div></header><div className="workspaceStatusArea">{offline&&<p className="workspaceOffline" role="status"><AppIcon name="info" size={17}/>غير متصل — قد تكون البيانات المعروضة قديمة.</p>}{status}<div id="workspace-update-notice"/></div><SectionLayoutContext.Provider value={{userId:profile.id,...sectionState}}><WorkspaceBoundary section={page} onHome={()=>go(null,'home')}>{authorized?children:<main><p className="uiEmpty" role="status">هذا القسم غير متاح لحسابك.</p><button type="button" onClick={()=>go(null,'home')}>العودة للرئيسية</button></main>}</WorkspaceBoundary></SectionLayoutContext.Provider></div><nav className="appMobileBar" aria-label="التنقل السريع">{shortcuts.map(([id,label])=><a href={id==='home'?'/?':'/?section='+id} onClick={e=>go(e,id)} key={id} aria-current={page===id?'page':undefined}><span><AppIcon name={id}/></span><span>{label}</span></a>)}<button type="button" onClick={()=>{setMenu('');setSearching(true);}} aria-label="فتح البحث العام" aria-expanded={searching}><span><AppIcon name="search"/></span><span>بحث</span></button><button type="button" onClick={()=>setMenu('sections')} aria-expanded={menu==='sections'}><span><AppIcon name="grid"/></span><span>الأقسام</span></button></nav><QuickSearch open={searching} onClose={()=>setSearching(false)} profile={profile} onNavigate={id=>go(null,id)} onOpenAccount={onOpenAccount}/><WorkspaceDialog open={menu==='sections'} onClose={()=>setMenu('')} title="جميع الأقسام" className="workspaceSectionsDialog">{menu==='sections'&&<WorkspaceSections profile={profile} page={page} onNavigate={id=>go(null,id)} showAll={sectionState.layout.mode==='general'} order={sectionState.layout.order}/>}</WorkspaceDialog><WorkspaceDialog open={menu==='account'} onClose={()=>setMenu('')} title="حسابي" className="workspaceAccountDialog"><div className="workspaceAccountIdentity"><span>{name.trim().slice(0,1)||'ح'}</span><div><b>{name}</b><small>{profile.is_admin?'إدارة البرنامج':profile.user_type==='installer'?'مهندس تنصيب':profile.user_type==='warehouse'?'مسؤول مخزن':'حساب مستخدم'}</small></div></div><div className="workspaceAccountActions"><button type="button" className="passwordChangeMenuButton" onClick={()=>setMenu('password')}><AppIcon name="shield" size={19}/>تغيير الرقم السري</button>{accountTools}<SectionDesignSelector state={sectionState} embedded/><button type="button" className="workspaceLogout" onClick={onLogout}><AppIcon name="signout" size={19}/>تسجيل خروج</button></div><footer>عبدالرحمن سولار <bdi>V{APP_VERSION}</bdi></footer></WorkspaceDialog>{menu==='password'&&<PasswordChange key={profile.id} userId={profile.id} onClose={()=>setMenu('account')} onBusyChange={passwordBusyChange}/>}</div>;
}
