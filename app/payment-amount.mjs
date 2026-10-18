import {convertAmount} from './fx-utils.mjs';
export function fullPaymentAmount(balance,from='IQD',to='IQD',rate=1){
 const amount=Number(balance),exchange=Number(rate);
 if(!Number.isFinite(amount)||amount<=0||!['IQD','USD'].includes(from)||!['IQD','USD'].includes(to)||!Number.isFinite(exchange)||exchange<=0)return '';
 const value=convertAmount(amount,from,to,exchange);
 return Number.isFinite(value)&&value>0&&value<=1e12?String(Math.round(value*100)/100):'';
}
