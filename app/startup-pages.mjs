// These sections load their own scoped data and can open after profile checking.
const independentPages=new Set(['userActivity','wholesalePricing','home','salesHistory','paymentHistory','cash','cashTransfers','capital','installations','warehouse','stock','stockMovement','customerDebts','customerCreate','customers','supplierBalances','exchangeRate','operationControl','warranty','users','updates']);
export const needsCloudSnapshot=page=>!independentPages.has(page);
