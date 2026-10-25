// An explicitly approved zero never falls back to an older engineer proposal.
export const approvedExpenseValue=job=>String(job.installationExpenses??0);
export const installationPaidExpense=job=>Number(job.installationPaidExpenses??job.installationExpenses??0);
export const installationExpenseDifference=(job,amount)=>Number(amount||0)-installationPaidExpense(job);
export function operatingExpenseAmount(row){
 if(row.kind==='handover_expense')return row.cashDelta==null?Number(row.total||0):-Number(row.cashDelta);
 if(row.kind==='profit_expense'||row.cashPurpose==='expense')return Number(row.total||0);
 return 0;
}
