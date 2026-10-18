export function cashProjection({mode,currency,amount,rate,iqd=0,usd=0}) {
 const value=Number(amount||0),r=Number(rate||0),exchange=['buy_usd','sell_usd'].includes(mode);
 const out=['expense','capital_withdraw'].includes(mode);
 return {
  IQD:Number(iqd)+(exchange?(mode==='buy_usd'?-value*r:value*r):currency==='IQD'?(out?-value:value):0),
  USD:Number(usd)+(exchange?(mode==='buy_usd'?value:-value):currency==='USD'?(out?-value:value):0)
 };
}
export function cashEntryProblem({ownerId,mode,currency,amount,rate,note,iqd=0,usd=0}) {
 if(!ownerId)return 'اختر قاصة مستخدم أولاً.';
 const value=Number(amount),r=Number(rate),exchange=['buy_usd','sell_usd'].includes(mode);
 if(amount===''||!Number.isFinite(value)||value<=0||value>1e12||Math.abs(value*100-Math.round(value*100))>0.00001)return 'أدخل مبلغاً أكبر من صفر، وبحد أقصى مرتبتين بعد الفارزة.';
 if((exchange||currency==='USD')&&(!Number.isFinite(r)||r<=0||r>1e6))return 'أدخل سعر صرف صحيحاً للدولار.';
 if(!String(note||'').trim())return 'اكتب بيان الحركة حتى تعرف سببها عند مراجعة الصندوق.';
 if(String(note).length>2000)return 'بيان الحركة طويل؛ اختصره إلى 2000 حرف.';
 if(mode==='buy_usd'&&value*r>Number(iqd))return 'رصيد الدينار لا يكفي لشراء هذا المبلغ من الدولار.';
 if(mode==='sell_usd'&&value>Number(usd))return 'رصيد الدولار لا يكفي لبيع هذا المبلغ.';
 if(['expense','capital_withdraw'].includes(mode)&&value>Number(currency==='USD'?usd:iqd))return 'رصيد العملة المختارة لا يكفي للصرف. قلّل المبلغ أو اختر عملة متوفرة.';
 return '';
}
