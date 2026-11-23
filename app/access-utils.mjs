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
  if (page === 'home') return true;
  if (isEngineer(profile)) return page === 'installations';
  if (isWarehouse(profile)) return ['warehouse','stock','stockMovement'].includes(page);
  if (isAdministrator(profile)) return true;
  const permissions=profile.permissions||{};
  const has=key=>permissions[key]===true;
  const quoteAccess=permissions.tahseel===undefined?has('system'):has('tahseel');
  if (['users','userActivity','updates','operationControl','supplierPayment'].includes(page)) return false;
  if (page==='exchangeRate') return has('exchangeRate')||has('exchangeRateEdit');
  if (page==='warranty') return permissions.warranty===undefined?quoteAccess||has('sale')||has('system'):has('warranty');
  if (page==='salesHistory') return permissions.salesHistory===undefined?has('sale')||has('system'):has('salesHistory');
  if (page==='deletionRequests') return has('deletionRequests');
  if (page==='wholesalePricing') return has('wholesalePricingManage');
  if (page==='cash') return ['cash','cashDeposit','cashExpense','cashExchange','cashExternalProfit','cashTransferSend','financeReceive'].some(has);
  if (page==='purchasesHub') return has('purchase');
  if (page==='profit') return has('profit')||has('profitSettlement');
  if (page==='customerCreate'||page==='customers') return has('customerCreate')||has('customers');
  if (page==='tahseel') return quoteAccess;
  if (page==='cashTransfers') return has('cashTransferSend')||has('financeReceive');
  if (page==='installations') return has('installations')||has('system');
  if (page==='paymentHistory') return paymentKinds.some(([kind])=>canReadPaymentKind(profile,kind));
  return has(page);
}
export const canRequestReceiptDeletion = (profile,kind) => canOpenPage(profile,'deletionRequests') &&
  (kind!=='supplier_payment'||isAdministrator(profile));
export const canDeleteSale = (profile,ownerId,kind) => isAdministrator(profile) ||
  !!(ownerId&&profile?.id===ownerId&&(kind?['sale','system'].includes(kind)&&canOpenPage(profile,kind):canOpenPage(profile,'sale')||canOpenPage(profile,'system')));
export function canDeletePurchase(profile,receipt) {
  if (!canOpenPage(profile,'purchase') || receipt?.kind!=='purchase') return false;
  return isAdministrator(profile) || receipt.cash || !(Number(receipt.accountAmount)||Number(receipt.total));
}
export const canSeeCash = profile => !isEngineer(profile) && canOpenPage(profile,'cash');

export const canManageQuotes = profile => canOpenPage(profile,'tahseel') && (isAdministrator(profile) || profile.permissions?.tahseelFull === true);

export const canManageQuoteDefaults = profile => canManageQuotes(profile) && (isAdministrator(profile) || profile.permissions?.tahseelDefaults === true);

export const canManageWholesalePricing = profile => canOpenPage(profile,'wholesalePricing');
