// These sections load their own scoped data and can open after profile checking.
const independentPages=new Set(['home','salesHistory','paymentHistory','cash','cashTransfers','capital','installations','warehouse','stock','stockMovement','customerDebts','supplierBalances','exchangeRate','operationControl','warranty','users','updates']);
export const needsCloudSnapshot=page=>!independentPages.has(page);
