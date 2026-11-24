import {escapeHtml,invoiceDate} from './document-format.mjs';
import {formatMoney,currencyUnit} from './money-format.mjs';
import {phoneContactDocument} from './phone-contact-utils.mjs';

function hasAmount(value){
 return value!=null && String(value).trim()!=='' && Number.isFinite(Number(value));
}

function moneyText(value,currency){
 return '<span class="svMoney"><bdi dir="ltr">'+formatMoney(value,currency)+'</bdi> <small>'+currencyUnit(currency)+'</small></span>';
}

function fact(label,html){
 return '<div class="svFact"><span>'+label+'</span><strong>'+html+'</strong></div>';
}

function balance(label,value,currency,closing=false){
 if(!hasAmount(value))return '';
 return '<div class="svBalance'+(closing?' svClosing':'')+'"><span>'+label+'</span><strong>'+moneyText(value,currency)+'</strong></div>';
}

export function supplierPaymentDocument(row,receiptNo,chargeReason){
 const charge=Boolean(chargeReason);
 const title=charge?'وصل إضافة على حساب مورد':'وصل تسديد مورد';
 const saved=Boolean(row.id&&!row.draft);
 const sourceCurrency=row.sourceCurrency||'IQD';
 const accountCurrency=row.accountCurrency||'IQD';
 // A legacy total is a booked IQD value. Always take a stored amount and its currency together.
 const cashRecorded=!charge && hasAmount(row.cashAmount);
 const sourceRecorded=hasAmount(row.sourceSubtotal);
 const primaryAmount=cashRecorded?row.cashAmount:sourceRecorded?row.sourceSubtotal:row.total;
 const primaryCurrency=cashRecorded?(row.cashCurrency||sourceCurrency):sourceRecorded?sourceCurrency:'IQD';
 const primary=hasAmount(primaryAmount)?Math.abs(Number(primaryAmount)):null;
 const foreign=primaryCurrency!==accountCurrency;
 const accountValue=hasAmount(row.accountAmount)?Math.abs(Number(row.accountAmount)):
  accountCurrency==='IQD' && hasAmount(row.total)?Math.abs(Number(row.total)):null;
 const recordedRate=Number(row.marketRate)>1?row.marketRate:Number(row.exchangeRate)>1?row.exchangeRate:null;
 const date=invoiceDate(row.date);
 const time=date==='—'?'':new Intl.DateTimeFormat('ar-IQ',{timeZone:'Asia/Baghdad',hour:'numeric',minute:'2-digit',numberingSystem:'latn'}).format(new Date(row.date));
 const subtitle=saved?'وصل محفوظ #'+receiptNo:'مسودة — غير محفوظة';
 const status=row.voided?'<p class="svStatus">وصل ملغى · سُجّل إلغاء أثره في كشف المورد.</p>':
  !saved?'<p class="svStatus">مسودة · غير محفوظة</p>':'';
 const receiptFact=receiptNo!=='مسودة'?fact('رقم الوصل','<bdi dir="ltr">'+escapeHtml(receiptNo)+'</bdi>'):'';
 const dateFact=date==='—'?'':fact('تاريخ الوصل','<bdi dir="ltr">'+date+'</bdi> <span class="svTime">'+escapeHtml(time)+'</span>');
 const identity='<div class="svIdentity"><div class="svParty"><span>المورد</span><strong><bdi>'+escapeHtml(row.party||'—')+'</bdi></strong></div><div class="svFacts">'+receiptFact+dateFact+'</div></div>';
 const rateText=recordedRate?'<bdi dir="ltr">'+formatMoney(recordedRate)+'</bdi> د.ع لكل دولار':'';
 const rate=foreign && rateText?'<small class="svRate">سعر الصرف المثبّت · '+rateText+'</small>':'';
 const sameCurrencyNote=!foreign && row.accountCurrency?'<small class="svRate">عملة حساب المورد: '+escapeHtml(accountCurrency)+
  (accountCurrency==='USD' && rateText?' · الصرف المثبّت '+rateText:'')+'</small>':'';
 const conversion=foreign && (accountValue!==null||rate)?'<div class="svConversion">'+
  (accountValue===null?'':'<span>المبلغ بعملة حساب المورد</span><strong>'+moneyText(accountValue,accountCurrency)+'</strong>')+rate+'</div>':'';
 const payment='<div class="svPayment"><div class="svPaid"><span>'+(charge?'المبلغ المضاف على الحساب':'المدفوع من القاصة')+'</span><strong>'+
  (primary===null?'غير متوفر':moneyText(primary,primaryCurrency))+'</strong>'+sameCurrencyNote+'</div>'+conversion+'</div>';
 const balances=balance('الرصيد قبل الحركة',row.beforeBalance,accountCurrency)+
  balance(charge?'الرصيد بعد الإضافة':'الرصيد بعد التسديد',row.afterBalance,accountCurrency,true);
 const breakdown=balances?'<section class="svBalances"><h3>رصيد حساب المورد</h3><div class="svBalanceGrid">'+balances+'</div></section>':'';
 const contact=(row.creatorName?fact('صاحب الوصل','<bdi>'+escapeHtml(row.creatorName)+'</bdi>'):'')+
  (row.creatorPhone?fact('هاتف صاحب الوصل',phoneContactDocument(row.creatorPhone)):'');
 const notes=row.notes?'<section class="svNotes" data-pdf-end><h3>الملاحظات</h3> <p>'+escapeHtml(row.notes)+'</p></section>':'';
 const expense=Number(row.expenses)>0?'<div class="svExpenses">'+fact('المصاريف',moneyText(row.expenses,'IQD'))+'</div>':'';
 const reason=charge?'<p class="svStatus">'+escapeHtml(chargeReason)+' · حركة غير نقدية لا تخصم من القاصة.</p>':'';
 return {title,subtitle,total:primary===null?'':formatMoney(primary,primaryCurrency)+' '+currencyUnit(primaryCurrency),
  body:'<section class="supplierVoucher'+(charge?' isCharge':'')+(row.voided?' isVoid':'')+'" data-pdf-flow>'+
   status+identity+payment+reason+breakdown+expense+(contact?'<div class="svContact">'+contact+'</div>':'')+notes+'</section>'};
}
