import {installationCost} from './review-utils.mjs';

export function companyInvoiceCost(invoice){
 if(invoice.kind==='system')return installationCost(invoice);
 if(invoice.fxPricing && invoice.cost!=null)return Number(invoice.cost);
 return (invoice.items||[]).reduce((sum,item)=>sum+Number(item.qty||0)*Number(item.cost||0),0);
}

export function companyMovementTotals(rows){
 let expenses=0,fx=0,externalProfit=0;
 for(const row of rows){
  const amount=Number(row.value);
  if(row.kind==='external_profit')externalProfit+=amount;
  else if(row.kind==='fx_gain')fx+=amount;
  else if(!['sale','system','external_adjustment','personal_distribution'].includes(row.kind))expenses-=amount;
 }
 return {expenses,fx,externalProfit};
}
