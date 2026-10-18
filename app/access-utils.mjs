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
  if (['users','updates'].includes(page)) return false;
  if (page === 'profit') return !!(profile.permissions?.profit || profile.permissions?.profitSettlement);
  if (page === 'customers') return !!(profile.permissions?.customers || profile.permissions?.customerCreate);
  if (page === 'tahseel') return profile.permissions?.tahseel !== undefined ? !!profile.permissions.tahseel : !!profile.permissions?.system;
  if (page === 'cashTransfers') return !!(profile.permissions?.cashTransferSend || profile.permissions?.financeReceive);
  if (page === 'installations') return !!(profile.permissions?.installations || profile.permissions?.installationsAll || profile.permissions?.system);
  if (page === 'salesHistory') return !!(profile.permissions?.salesHistory || profile.permissions?.sale || profile.permissions?.system || profile.permissions?.installations || profile.permissions?.installationsAll || profile.permissions?.salesDeleteOwn || profile.permissions?.salesDeleteAll);
  return !!profile.permissions?.[page];
}
export const canSeeCash = profile => !isEngineer(profile) && canOpenPage(profile,'cash');

export const canManageQuotes = profile => canOpenPage(profile,'tahseel') && (isAdministrator(profile) || profile.permissions?.tahseelFull === true);
