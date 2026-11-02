'use client';
import {useEffect,useRef} from 'react';
import AppIcon from './app-icons';
export default function WorkspaceDialog({open,onClose,title,className='',children}){
 const ref=useRef(null);
 useEffect(()=>{
  if(!open){ref.current?.close();return;}
  const previous=document.activeElement,overflow=document.body.style.overflow;
  ref.current?.showModal();document.body.style.overflow='hidden';
  return()=>{ref.current?.close();document.body.style.overflow=overflow;if(previous?.isConnected)previous.focus({preventScroll:true});};
 },[open]);
 return <dialog ref={ref} className={'workspaceDialog '+className} aria-label={title} onCancel={e=>{e.preventDefault();onClose();}} onClick={e=>{if(e.target===e.currentTarget)onClose();}}><div className="workspaceDialogBody"><header><div><span className="workspaceDialogHandle"/><h2>{title}</h2></div><button type="button" aria-label={'إغلاق '+title} onClick={onClose}><AppIcon name="close" size={20}/></button></header>{children}</div></dialog>;
}
