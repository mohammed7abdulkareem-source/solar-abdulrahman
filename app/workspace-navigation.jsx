'use client';
import {useEffect,useRef} from 'react';
import {sections} from './section-directory.mjs';
import {canOpenPage} from './access-utils.mjs';
import {WORKSPACE_HISTORY,workspaceURL,workspaceEntry,pushWorkspaceLocation} from './workspace-history.mjs';

export default function useWorkspaceNavigation({page,onPage,userId,profile,dirty,onLeave}){
 const latest=useRef(null),current=useRef(null),restoring=useRef(null),skipPop=useRef(false);
 latest.current={page,onPage,userId,profile,dirty,onLeave};
 const ready=!!userId&&profile?.id===userId&&profile?.active===true;
 const allowed=next=>sections.some(([,rows])=>rows.some(([id])=>id===next))&&canOpenPage(latest.current.profile,next);
 function canGo(next){return allowed(next)&&(next===latest.current.page||!latest.current.dirty||window.confirm('توجد تعديلات غير محفوظة في التحصيل. مغادرة القسم؟'));}
 function go(next,{confirmed=false}={}){
  const state=latest.current;if(!state.userId||!allowed(next)||!confirmed&&!canGo(next))return false;
  if(next===state.page)return true;
  restoring.current=null;
  current.current=pushWorkspaceLocation(workspaceURL(next,location.href),state.userId);
  state.onLeave?.(state.page,next);state.onPage(next);window.scrollTo({top:0,behavior:'instant'});return true;
 }
 function back(){if((workspaceEntry(history.state,latest.current.userId)?.index||0)>0)history.back();else go('home');}
 useEffect(()=>{
  if(!ready){current.current=null;return;}
  const old=workspaceEntry(history.state,userId),entry=old&&old.page===latest.current.page?old:{userId,page:latest.current.page,index:0,scroll:0};
  const addressPage=new URL(location.href).searchParams.get('section')||'home';
  history.replaceState({...history.state,[WORKSPACE_HISTORY]:entry},'',addressPage===entry.page?location.href:workspaceURL(entry.page,location.href));current.current=entry;
  const oldRestoration=history.scrollRestoration;history.scrollRestoration='manual';
  const locationChanged=()=>{current.current=workspaceEntry(history.state,userId);};
  const onScroll=()=>{const state=workspaceEntry(history.state,userId);if(state&&!restoring.current)current.current={...state,scroll:window.scrollY};};
  const onPop=()=>{
   if(skipPop.current){skipPop.current=false;return;}
   const from=current.current,target=workspaceEntry(history.state,userId),next=target?.page||new URL(location.href).searchParams.get('section')||'home';
   if(!canGo(next)){
    if(!allowed(next)){history.replaceState({...history.state,[WORKSPACE_HISTORY]:{userId,page:'home',index:target?.index||0,scroll:0}},'',workspaceURL('home',location.href));latest.current.onPage('home');current.current=workspaceEntry(history.state,userId);return;}
    skipPop.current=true;history.go(from&&target?from.index-target.index||1:1);return;
   }
   current.current=target||{userId,page:next,index:0,scroll:0};restoring.current={page:next,scroll:target?.scroll||0};
   latest.current.onLeave?.(latest.current.page,next);latest.current.onPage(next);
   // Nested cash routes keep the same page component and handle their own pop.
   if(next===latest.current.page){window.scrollTo({top:target?.scroll||0,behavior:'instant'});restoring.current=null;}
  };
  window.addEventListener('popstate',onPop);window.addEventListener('solar-workspace-location',locationChanged);window.addEventListener('scroll',onScroll,{passive:true});
  return()=>{history.scrollRestoration=oldRestoration;window.removeEventListener('popstate',onPop);window.removeEventListener('solar-workspace-location',locationChanged);window.removeEventListener('scroll',onScroll);};
 },[ready,userId]);
 useEffect(()=>{
  const target=restoring.current;if(!target||target.page!==page)return;
  let stopped=false,frame,timer;const apply=()=>{if(stopped)return;window.scrollTo({top:target.scroll,behavior:'instant'});if(document.documentElement.scrollHeight>=target.scroll+innerHeight-2)stop();};
  const stop=()=>{stopped=true;restoring.current=null;observer.disconnect();cancelAnimationFrame(frame);clearTimeout(timer);window.removeEventListener('pointerdown',stop);window.removeEventListener('wheel',stop);};
  const observer=new ResizeObserver(apply);observer.observe(document.body);frame=requestAnimationFrame(apply);timer=setTimeout(stop,2000);window.addEventListener('pointerdown',stop,{once:true});window.addEventListener('wheel',stop,{once:true,passive:true});return stop;
 },[page]);
 return {go,back,canGo};
}
