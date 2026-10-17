import {roundMoney} from './currency-utils.mjs';
export const currencyLabel=c=>c==='USD'?'$':'د.ع';
export const convertAmount=(amount,from,to,rate)=>from===to?Number(amount):to==='USD'?roundMoney(Number(amount)/Number(rate)):roundMoney(Number(amount)*Number(rate));
export const usdBalance=(tx,uid,all=false)=>tx.filter(t=>t.fxWalletPosting&&t.cashCurrency==='USD'&&(all||t.createdBy===uid)).reduce((s,t)=>s+Number(t.cashDelta),0);
export const usdBook=(tx,uid,all=false)=>tx.filter(t=>t.fxWalletPosting&&t.cashCurrency==='USD'&&(all||t.createdBy===uid)).reduce((s,t)=>s+Number(t.bookDelta),0);
export function fxCloudRows(data={}){
 const wallet=(data.walletEntries||[]).map(e=>({id:'fxwallet:'+e.id,systemCash:true,fxWalletPosting:true,linkedTransaction:e.transaction_id,kind:e.entry_type,cash:true,cashCurrency:e.currency,cashDelta:Number(e.delta),bookDelta:Number(e.book_delta),total:Math.abs(Number(e.delta)),createdBy:e.owner_id,cashboxUserId:e.owner_id,date:e.created_at,notes:e.note}));
 const account=(data.accountEntries||[]).map(e=>({id:'fxaccount:'+e.id,systemCash:true,fxAccountEntry:true,linkedTransaction:e.transaction_id,kind:'supplier_fx_book',partyId:e.supplier_id,total:Number(e.book_delta),accountAmount:Number(e.delta),accountCurrency:e.currency,accountRevision:e.revision,createdBy:e.owner_id,cashboxUserId:e.owner_id,cash:false,date:e.created_at}));
 const gains=[...(data.accountEntries||[]),...(data.walletEntries||[])].filter(e=>Number(e.gain||0)!==0).map((e,i)=>({id:'fxgain:'+i+':'+e.id,systemCash:true,kind:'fx_gain',total:Number(e.gain),createdBy:e.owner_id,cashboxUserId:e.owner_id,cash:false,date:e.created_at}));
 return [...wallet,...account,...gains];
}
