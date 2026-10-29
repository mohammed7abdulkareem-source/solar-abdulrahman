import {cashKind} from './cash-utils.mjs';
export const baghdadDay=(date=new Date())=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).format(date);
export const monthStart=()=>baghdadDay().slice(0,8)+'01';
export const cashGroups={expenses:['expense','cash_expense','installation_payout','installation_refund','handover_expense','supplier_payment_refund','cash_income'],transfers:['admin_transfer_out','admin_transfer_in','transfer_out','transfer_in','transfer_refund','transfer_transit'],capital:['capital_deposit','capital_withdraw','external_profit','profit_distribution','distribution']};
export const cashTypes=['cash_income','expense','external_profit','capital_deposit','capital_withdraw','cash_reconcile','admin_transfer_out','admin_transfer_in','transfer_out','transfer_in','transfer_refund','buy_usd','sell_usd','sale','system','purchase','customer_payment','system_payment','supplier_payment','installation_payout','installation_refund','handover_expense','profit_distribution'];
export const cashTypeOptions=cashTypes.map(k=>[k,cashKind(k)]);
export const matchesCashType=(row,type='all')=>type==='all'||(cashGroups[type]?cashGroups[type].includes(row.kind):row.kind===type||(type==='expense'&&row.kind==='cash_expense'));
export function cashPage(data,type='all',offset=0,limit=50){
 if(type==='all')return data;
 if(data.count>5000)throw new Error('الحركات كثيرة؛ حدد فترة أقصر لتصفية نوع الحركة كاملة.');
 const rows=data.rows.filter(r=>matchesCashType(r,type));
 return {...data,count:rows.length,rows:rows.slice(offset,offset+limit),offset,limit};
}
export function statementByType(data,type='all'){
 if(type==='all')return data;
 const ledgers=data.ledgers.map(g=>({...g,rows:g.rows.filter(r=>matchesCashType(r,type))}));
 return {...data,ledgers,count:ledgers.reduce((n,g)=>n+g.rows.length,0),filterLabel:cashKind(type),unfilteredCount:data.count};
}
export const cashIcon=kind=>/transfer/.test(kind)?'exchange':/expense|payout|withdraw|distribution/.test(kind)?'receipt':/profit/.test(kind)?'chart':/usd|reconcile/.test(kind)?'coins':/purchase|supplier/.test(kind)?'truck':'wallet';
export const cashTone=row=>Number(row.delta)<0?'out':Number(row.delta)>0?'in':'neutral';
export const cashRole=user=>user?.honorific||({admin_staff:'إداري',accountant:'محاسب',finance:'مسؤول المالية'}[user?.user_type])||(user?.is_admin?'الإدارة':'');
export function cashTotals(owners=[]){const cents=owners.reduce((r,o)=>({IQD:r.IQD+Math.round(Number(o.IQD||0)*100),USD:r.USD+Math.round(Number(o.USD||0)*100)}),{IQD:0,USD:0});return{IQD:cents.IQD/100,USD:cents.USD/100};}
