export function formatMoney(value,currency='IQD'){
 const amount=Number(value||0),rounded=Math.round((amount+Number.EPSILON)*100)/100;
 return (Number.isFinite(amount)?amount:0).toLocaleString('en-US',{minimumFractionDigits:currency==='USD'&&!Number.isInteger(rounded)?2:0,maximumFractionDigits:2});
}
export const currencyName=currency=>currency==='USD'?'الدولار الأمريكي':'الدينار العراقي';
export const currencyUnit=currency=>currency==='USD'?'$':'د.ع';
export function purchaseDisplayTotal(row){
 const currency=row.sourceCurrency||'IQD',rate=Number(row.marketRate>1?row.marketRate:row.exchangeRate||1);
 const value=currency==='USD'?Math.round((Number(row.sourceSubtotal??(Number(row.total||0)-Number(row.expenses||0))/rate)+Number(row.expenses||0)/rate)*100)/100:Number(row.total||0);
 return {currency,value};
}
