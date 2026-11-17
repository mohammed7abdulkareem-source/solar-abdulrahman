import {isAdministrator,isEngineer,isWarehouse} from './access-utils.mjs';
export const cashPermissionOptions=[
 ['cashDeposit','إيداع نقدي'],['cashExpense','تسجيل مصروف'],
 ['cashTransferSend','تسليم القاصة'],['financeReceive','استلام القاصة'],
 ['cashExchange','صرافة دولار ودينار'],['cashExternalProfit','إضافة أرباح خارجية']
];
export const cashModePermission={deposit:'cashDeposit',expense:'cashExpense',buy_usd:'cashExchange',sell_usd:'cashExchange',external_profit:'cashExternalProfit',capital_deposit:'cashAdminTools',capital_withdraw:'cashAdminTools'};
export function canUseCash(profile,permission){if(permission==='cashAdminTools'||permission==='adminOnly')return canReconcileCash(profile);return !!profile?.active&&!isEngineer(profile)&&!isWarehouse(profile)&&(isAdministrator(profile)||profile.permissions?.[permission]===true);}
export const allowedCashModes=profile=>Object.keys(cashModePermission).filter(mode=>canUseCash(profile,cashModePermission[mode]));

// Balance reconciliation and administrative capital changes cannot be delegated by legacy flags.
export const canReconcileCash=profile=>profile?.active===true&&profile?.is_admin===true&&isAdministrator(profile);
export const cashViewAllowed=(profile,view)=>view==='reconcile'?canReconcileCash(profile):['admin','handover'].includes(view)?isAdministrator(profile):true;

export const canRetryCashAttempt=(profile,attempt)=>!!attempt?.payload&&allowedCashModes(profile).includes(attempt.payload.mode);
