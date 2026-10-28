import {canReadPaymentKind,paymentKinds} from './record-browser-utils.mjs';
export const cashOwner = row => row.cashboxUserId || row.createdBy || null;
export const isWarehouse = profile => profile?.user_type === 'warehouse';
export const isEngineer = profile => profile?.user_type === 'installer';
export const isAdministrator = profile => !!profile?.active && !!profile?.is_admin && !isEngineer(profile) && !isWarehouse(profile);
export function cashRowsFor(rows, userId, all = false) {
  return rows.filter(row => row.cash && row.cashCurrency!=='USD' && (all || (!!userId && cashOwner(row) === userId)));
}
export function cashBalance(rows, userId, all = false) {
  return cashRowsFor(rows,userId,all).reduce((sum,row) =>
    sum + (row.cashDelta!==undefined ? Number(row.cashDelta) : (['purchase','supplier_payment','cash_expense','profit_distribution'].includes(row.kind) ? -1 : 1) * Number(row.total || 0)),0);
}
export function canOpenPage(profile, page) {
  if (!profile?.active) return false;
  if (page === 'exchangeRate') return !isEngineer(profile) && !isWarehouse(profile);
  if (page === 'home') return true;
  if (page === 'warranty') return !isEngineer(profile) && !isWarehouse(profile);
  if (isEngineer(profile)) return page === 'installations';
  if (isWarehouse(profile)) return ['warehouse','stock','stockMovement'].includes(page);
  if (isAdministrator(profile)) return true;
  if (['users','updates','operationControl'].includes(page)) return false;
  if (page === 'cash') return !!profile.permissions?.cash || ['cashDeposit','cashExpense','cashExchange','cashExternalProfit','cashAdminTools','cashTransferSend','financeReceive'].some(key=>profile.permissions?.[key]===true);
  if (page === 'profit') return !!(profile.permissions?.profit || profile.permissions?.profitSettlement);
  if (page === 'customerCreate') return !!(profile.permissions?.customerCreate || profile.permissions?.customers);
  if (page === 'customers') return !!(profile.permissions?.customers || profile.permissions?.customerCreate);
  if (page === 'tahseel') return profile.permissions?.tahseel !== undefined ? !!profile.permissions.tahseel : !!profile.permissions?.system;
  if (page === 'cashTransfers') return !!(profile.permissions?.cashTransferSend || profile.permissions?.financeReceive);
  if (page === 'installations') return !!(profile.permissions?.installations || profile.permissions?.system);
  if (page === 'paymentHistory') return paymentKinds.some(([kind])=>canReadPaymentKind(profile,kind));
  if (page === 'salesHistory' || page === 'deletionRequests') return true;
  return !!profile.permissions?.[page];
}
export const canDeleteSale = (profile, ownerId) => !!profile?.active && !isEngineer(profile) && !isWarehouse(profile) && (isAdministrator(profile) || (!!ownerId && profile.id === ownerId));
export const canSeeCash = profile => !isEngineer(profile) && canOpenPage(profile,'cash');

export const canManageQuotes = profile => canOpenPage(profile,'tahseel') && (isAdministrator(profile) || profile.permissions?.tahseelFull === true);
