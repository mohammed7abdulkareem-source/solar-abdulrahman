'use client';
import {useEffect,useState} from 'react';
import AppIcon from './app-icons';

export function useRecordView(userId,section,allowPeriod=false){
 const [mode,setMode]=useState('list');
 const key='solar-record-view:'+userId+':'+section;
 useEffect(()=>{try{const stored=localStorage.getItem(key);setMode(stored==='single'||allowPeriod&&stored==='period'?stored:'list');}catch{setMode('list');}},[key,allowPeriod]);
 const choose=value=>{if(!['list','single',...(allowPeriod?['period']:[])].includes(value))return;setMode(value);try{localStorage.setItem(key,value);}catch{}};
 return [mode,choose];
}
export function RecordViewSwitch({mode,onChange,label='طريقة عرض الوصولات',disabled=false,allowPeriod=false}){
 return <div className={'recordViewSwitch'+(allowPeriod?' hasPeriod':'')} role="group" aria-label={label}>{[['list','العرض الحالي','list'],['single','وصل واحد مع الأسهم','receipt'],...(allowPeriod?[['period','مبيعات الفترة','chart']]:[])].map(([value,text,icon])=><button type="button" key={value} aria-pressed={mode===value} disabled={disabled} onClick={()=>onChange(value)}><AppIcon name={icon} size={16}/><span>{text}</span></button>)}</div>;
}
export function RecordNavigator({index,total,onPrevious,onNext,busy=false,label='التنقل بين الوصولات',children,previousDisabled,nextDisabled}){
 const first=previousDisabled??index<=0,last=nextDisabled??index+1>=total;
 function keyboard(e){
  if(e.target.tagName!=='BUTTON')return;
  if(e.key==='ArrowRight'){e.preventDefault();if(!first&&!busy)onPrevious();}
  if(e.key==='ArrowLeft'){e.preventDefault();if(!last&&!busy)onNext();}
 }
 return <nav className="recordNavigator" aria-label={label} onKeyDown={keyboard}>
  <button type="button" aria-label={label+' — السابق'} disabled={busy||first} onClick={onPrevious}><AppIcon name="arrow" size={16}/><span>السابق</span></button>
  <span className="recordPosition" aria-live="polite" aria-atomic="true">{children||<><bdi>{total?index+1:0} / {total}</bdi><small>ضمن النتائج المحددة</small></>}</span>
  <button type="button" aria-label={label+' — التالي'} disabled={busy||last} onClick={onNext}><span>التالي</span><AppIcon className="recordNextArrow" name="arrow" size={16}/></button>
 </nav>;
}
