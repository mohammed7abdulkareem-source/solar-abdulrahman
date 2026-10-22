let pending=null;
export function confirmLogout(){
 if(pending)return pending;
 const previous=document.activeElement;
 pending=new Promise(resolve=>{
  const dialog=document.createElement('dialog');dialog.className='logoutConfirmation';dialog.setAttribute('aria-labelledby','logout-confirm-title');dialog.setAttribute('aria-describedby','logout-confirm-description');
  const title=document.createElement('h2');title.id='logout-confirm-title';title.textContent='تسجيل الخروج؟';const description=document.createElement('p');description.id='logout-confirm-description';description.textContent='تريد تطلع من حسابك على هذا الجهاز؟';const actions=document.createElement('div'),no=document.createElement('button'),yes=document.createElement('button');no.type=yes.type='button';no.textContent='لا، أبقى بالحساب';yes.textContent='نعم، تسجيل الخروج';yes.className='logoutConfirmYes';actions.append(no,yes);dialog.append(title,description,actions);
  const finish=value=>{dialog.close();dialog.remove();pending=null;previous?.focus?.();resolve(value);};no.onclick=()=>finish(false);yes.onclick=()=>finish(true);dialog.addEventListener('cancel',e=>{e.preventDefault();finish(false);});document.body.append(dialog);dialog.showModal();no.focus();
 });return pending;
}
