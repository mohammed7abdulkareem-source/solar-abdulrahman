'use client';
import {useEffect,useRef,useState} from 'react';
import AppIcon from './app-icons';
import CompactPartyAccount from './compact-party-account';
import CustomerNameEditor from './customer-name-editor';
import {canRenameCustomer} from './customer-utils.mjs';
import CustomerOwnerTransfer from './customer-owner-transfer';
import CustomerOwnershipGuard from './customer-ownership-guard';
import StatementPaymentEditor from './statement-payment-editor';
import {canOpenPage,isAdministrator} from './access-utils.mjs';
import {deletionResultMessage} from './receipt-deletion.mjs';

const saleKinds=['sale','system'];
const paymentPages={customer_payment:'customerPayment',system_payment:'systemPayment'};

export default function CustomerAccountView(props){
 const {account,profile,onBack,backLabel,onRefresh}=props;
 const view=<AccountContents {...props}/>;
 if(isAdministrator(profile))return view;
 return <CustomerOwnershipGuard key={profile.id+':'+account.id} customerId={account.id} userId={profile.id} onBack={onBack} backLabel={backLabel} onLost={onRefresh}>{view}</CustomerOwnershipGuard>;
}

function AccountContents({profile,account,onAccountChanged,renderSaleEditor,onDeleteInvoice,...props}){
 const [editor,setEditor]=useState(null),[saving,setSaving]=useState(false),[revision,setRevision]=useState(0),[error,setError]=useState(''),[notice,setNotice]=useState('');
 const mutating=useRef(false),origin=useRef(null),editorRegion=useRef(null),live=useRef(true);
 useEffect(()=>{if(editor)editorRegion.current?.focus({preventScroll:true});},[editor]);
 useEffect(()=>{live.current=true;return()=>{live.current=false;};},[]);

 function rememberOrigin(button){origin.current={button,top:window.scrollY};}
 function restoreOrigin(){
  const previous=origin.current;
  origin.current=null;
  if(previous)requestAnimationFrame(()=>{
   if(!live.current)return;
   if(previous.button?.isConnected)previous.button.focus({preventScroll:true});
   window.scrollTo({top:previous.top,behavior:'instant'});
  });
 }
 function cancel(){setEditor(null);restoreOrigin();}
 async function refreshAfterSave(result){
  if(result?.message)setNotice(result.message);
  setSaving(true);
  try{await onAccountChanged();}catch{if(live.current)setError('تم حفظ التغيير. أعد تحديث الحساب لعرض الرصيد والوصل.');}
  finally{if(live.current){setRevision(n=>n+1);setEditor(null);setSaving(false);restoreOrigin();}}
 }

 async function act(row,action,button){
  if(mutating.current||saving||editor||row.receiptRestricted)return;
  const sale=saleKinds.includes(row.kind);
  rememberOrigin(button);setError('');setNotice('');
  if(sale&&action==='delete'){
   mutating.current=true;setSaving(true);
   try{
    const result=await onDeleteInvoice({id:row.id,kind:row.kind});
    if(result)await refreshAfterSave({message:deletionResultMessage(result)});
   }
   catch(e){if(live.current)setError(e.message||'تعذّر إتمام حذف وصل البيع.');}
   finally{mutating.current=false;if(live.current){setSaving(false);restoreOrigin();}}
   return;
  }
  setEditor({id:row.id,kind:row.kind,action});
  window.scrollTo({top:0,behavior:'instant'});
 }
 function receiptPermissions(row){
  if(row.receiptRestricted||['opening_balance','account_reconciliation'].includes(row.mode))return null;
  const sale=saleKinds.includes(row.kind),page=sale?row.kind:paymentPages[row.kind];
  if(!page||!canOpenPage(profile,page))return null;
  const edit=row.canEditReceipt===true&&(!sale||!!renderSaleEditor);
  const remove=row.canDeleteReceipt===true&&(sale?!!onDeleteInvoice:canOpenPage(profile,'deletionRequests'));
  return edit||remove?{sale,edit,remove}:null;
 }
 function receiptActions(row){
  const allowed=receiptPermissions(row);
  if(!allowed)return null;
  const {edit,remove,sale}=allowed;
  const label=sale?'وصل البيع':'وصل التسديد',disabled=saving||props.balanceStatus!=='ready';
  return <div className="customerReceiptActions" role="group" aria-label={'إجراءات '+label+(row.receiptNo?' #'+row.receiptNo:'')}>
   {edit&&<button type="button" aria-label={'تعديل '+label} disabled={disabled} onClick={e=>act(row,'update',e.currentTarget)}><AppIcon name="edit" size={15}/>تعديل <span>{label}</span></button>}
   {remove&&<button type="button" className="customerReceiptDelete" aria-label={'حذف '+label} disabled={disabled} onClick={e=>act(row,'delete',e.currentTarget)}><AppIcon name="trash" size={15}/>حذف <span>{label}</span></button>}
  </div>;
 }
 let canEdit=false,canDelete=false;
 const manageableRows=account.rows.filter(row=>{
  const allowed=receiptPermissions(row);
  if(!allowed)return false;
  canEdit||=allowed.edit;canDelete||=allowed.remove;
  return true;
 });
 const canRename=canRenameCustomer(profile,account),canTransfer=isAdministrator(profile);
 const manageLabel=canEdit&&canDelete?'تعديل وحذف الوصولات':canEdit?'تعديل الوصولات':canDelete?'حذف الوصولات':'إدارة الوصولات';
 const receiptManagement=manageableRows.length||canTransfer?{rows:manageableRows,label:manageLabel}:null;
 const selected=editor&&account.rows.find(row=>String(row.id)===String(editor.id)&&row.kind===editor.kind&&!row.receiptRestricted);
 useEffect(()=>{
  if(editor&&!selected&&!saving){setEditor(null);restoreOrigin();}
 },[editor,selected,saving]);
 const form=selected&&(saleKinds.includes(selected.kind)
  ? renderSaleEditor({movementId:selected.id,customerId:account.id,onSaved:()=>refreshAfterSave({message:'تم تعديل وصل البيع.'}),onCancel:cancel})
  : <StatementPaymentEditor profile={profile} movement={selected} action={editor.action} onBack={cancel} onChanged={refreshAfterSave}/>);
 return <>
  {notice&&<p className="miniSuccess" role="status">{notice}</p>}
  {error&&<p className="miniAlert" role="alert">{error}</p>}
  <div hidden={!!form}>
   <CompactPartyAccount {...props} account={account} documentRevision={revision} renderReceiptActions={receiptActions} receiptManagement={receiptManagement}
    identityActions={(canRename||canTransfer)&&<>
     {canRename&&<div className="statementIdentityItem"><CustomerNameEditor key={account.id} profile={profile} account={account} onSaved={refreshAfterSave}/></div>}
     {canTransfer&&<div className="statementIdentityItem"><CustomerOwnerTransfer key={profile.id+':'+account.id} account={account}
      disabled={saving||props.balanceStatus!=='ready'} onSaved={refreshAfterSave}/></div>}
    </>}/>
  </div>
  {form&&<div ref={editorRegion} tabIndex={-1} aria-label="إدارة الوصل" role="region">{form}</div>}
 </>;
}
