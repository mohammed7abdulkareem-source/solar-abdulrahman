'use client';
import AppIcon from './app-icons';
import {money} from './supplier-utils.mjs';

export default function SystemPricingNotice({status,error,reload,quote,hiddenCost=false,price,onUseMinimum,minimumActionLabel,minimumActionDisabled=false}){
 if(error)return <div className="systemPricingPolicy error" role="alert">{error} <button type="button" onClick={reload}>تحديث حالة التسعير</button></div>;
 if(!status||typeof status.systemFreePricing!=='boolean')return <p className="systemPricingPolicy" role="status">جاري تحميل سياسة تسعير المنظومات…</p>;
 if(status.systemFreePricing)return <p className="systemPricingPolicy free"><AppIcon name="sun" size={17}/>البيع الحر للمنظومات متاح</p>;
 if(hiddenCost)return <p className="systemPricingPolicy" role="status">يتحقق النظام من الحد الأدنى لربح المنظومة عند الحفظ.</p>;
 if(!quote)return <p className="systemPricingPolicy">الحد الأدنى للبيع الجديد أو تعديل السعر والمواد: ربح {status.systemMarkupPercent}٪ من مجموع أسعار المواد والمصاريف. تظهر الأرقام بعد إدخال المواد والكميات.</p>;
 return <section className="systemPricingPolicy required" aria-label="الحد الأدنى لربح المنظومة"><div><AppIcon name="shield" size={18}/><strong>حد الربح الإلزامي: {quote.percent}٪ من مجموع أسعار المواد والمصاريف</strong></div><p>الربح يُحتسب على المنظومة كاملة، ويجوز البيع بسعر أعلى.</p><div className="systemPricingNumbers"><span>مجموع أسعار المواد والمصاريف<b>{money(quote.totalCost)} د.ع</b></span><span>الحد الأدنى لسعر المنظومة<b data-testid="system-minimum-price">{money(quote.minimum)} د.ع</b></span></div>{onUseMinimum&&<button type="button" disabled={minimumActionDisabled} onClick={onUseMinimum}>{minimumActionLabel||'استخدام الحد الأدنى للسعر'}</button>}{price!==''&&Number(price)<quote.minimum&&<p className="systemPricingLow" role="alert">السعر أقل من الحد المسموح. ارفع السعر إلى {money(quote.minimum)} د.ع أو أكثر.</p>}<small>المصاريف المعتمدة لاحقًا تُراجع ضمن ربح المنظومة؛ تصحيح السعر يبقى من الفاتورة.</small></section>;
}
