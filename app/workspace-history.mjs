export const WORKSPACE_HISTORY='solarWorkspace';
const routeKeys=['section','job','transfer','deleteRequest','profitTab','cashView','cashOwner','cashTab','cashMode','cashType','cashMovement','stockTransfer','updated','install'];
export function workspaceURL(section,href){
 const url=new URL(href);for(const key of routeKeys)url.searchParams.delete(key);
 if(section!=='home')url.searchParams.set('section',section);url.hash='';
 return url.pathname+url.search;
}
export function workspaceEntry(state,userId){
 const value=state?.[WORKSPACE_HISTORY];
 return value?.userId===userId&&Number.isSafeInteger(value.index)&&value.index>=0&&typeof value.page==='string'?value:null;
}
// Shared with the cash workspace's nested routes. Preserve Next.js history
// fields and the current scroll position when a subsection opens.
export function pushWorkspaceLocation(url,userId){
 const current=workspaceEntry(history.state,userId);
 if(current)history.replaceState({...history.state,[WORKSPACE_HISTORY]:{...current,scroll:window.scrollY}},'',location.href);
 const target=new URL(url,location.href),next={userId,index:(current?.index??0)+1,page:target.searchParams.get('section')||'home',scroll:0};
 history.pushState({...history.state,[WORKSPACE_HISTORY]:next},'',target);
 window.dispatchEvent(new Event('solar-workspace-location'));
 return next;
}
