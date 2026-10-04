export const cashOwner = row => row.cashboxUserId || row.createdBy || null;
export const isEngineer = profile => profile?.user_type === 'installer';
export const isAdministrator = profile => !!profile?.active && !!profile?.is_admin && !isEngineer(profile);
export function cashRowsFor(rows, userId, all = false) {
  return rows.filter(row => row.cash && (all || (!!userId && cashOwner(row) === userId)));
}
export function cashBalance(rows, userId, all = false) {
  return cashRowsFor(rows,userId,all).reduce((sum,row) =>
    sum + (['purchase','supplier_payment','cash_expense','profit_distribution'].includes(row.kind) ? -1 : 1) * Number(row.total || 0),0);
}
export function canOpenPage(profile, page) {
  if (!profile?.active) return false;
  if (page === 'home') return true;
  if (isEngineer(profile)) return page === 'installations';
  if (isAdministrator(profile)) return true;
  if (['users','updates'].includes(page)) return false;
  if (page === 'installations') return !!(profile.permissions?.installations || profile.permissions?.installationsAll || profile.permissions?.system);
  if (page === 'salesHistory') return !!(profile.permissions?.salesHistory || profile.permissions?.sale || profile.permissions?.system || profile.permissions?.installations || profile.permissions?.installationsAll);
  return !!profile.permissions?.[page];
}
export const canSeeCash = profile => !isEngineer(profile) && canOpenPage(profile,'cash');
