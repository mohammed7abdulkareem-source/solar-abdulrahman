import {iconPath} from './ui-icons.mjs';
export default function AppIcon({name,size=22,...props}){return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" {...props}><path d={iconPath(name)}/></svg>;}
