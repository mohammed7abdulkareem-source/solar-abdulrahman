import {isAdministrator,isEngineer,isWarehouse} from './access-utils.mjs';
export const cashPermissionOptions=[
 ['cashDeposit','إيداع نقدي'],['cashExpense','تسجيل مصروف'],
 ['cashTransferSend','تسليم القاصة'],['financeReceive','استلام القاصة'],
 ['cashExchange','صرافة دولار ودينار'],['cashExternalProfit','إضافة أرباح خارجية'],
 ['cashAdminTools','أدوات إدارة قاصته فقط']
];
export const cashModePermission={deposit:'cashDeposit',expense:'cashExpense',buy_usd:'cashExchange',sell_usd:'cashExchange',external_profit:'cashExternalProfit',capital_deposit:'cashAdminTools',capital_withdraw:'cashAdminTools'};
export function canUseCash(profile,permission){return !!profile?.active&&!isEngineer(profile)&&!isWarehouse(profile)&&(isAdministrator(profile)||profile.permissions?.[permission]===true);}
export const allowedCashModes=profile=>Object.keys(cashModePermission).filter(mode=>canUseCash(profile,cashModePermission[mode]));
