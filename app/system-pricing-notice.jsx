'use client';
import AppIcon from './app-icons';
import {money} from './supplier-utils.mjs';

export default function SystemPricingNotice({status,error,reload,quote,price,onUseMinimum,minimumActionLabel}){
 if(error)return <div className="systemPricingPolicy error" role="alert">تعذر تأكيد تسعير المنظومات. <button type="button" onClick={reload}>تحديث حالة التسعير</button></div>;
 if(!status||typeof status.systemFreePricing!=='boolean')return <p className="systemPricingPolicy" role="status">جاري تحميل سياسة تسعير المنظومات…</p>;
 if(status.systemFreePricing)return <p className="systemPricingPolicy free"><AppIcon name="sun" size={17}/>البيع الحر للمنظومات متاح</p>;
 if(!quote)return <p className="systemPricingPolicy">الحد الأدنى للبيع الجديد أو تعديل السعر والمواد: ربح {status.systemMarkupPercent}٪ من الكلفة الكلية. تظهر الأرقام بعد إدخال المواد والكميات.</p>;
 return <section className="systemPricingPolicy required" aria-label="الحد الأدنى لربح المنظومة"><div><AppIcon name="shield" size={18}/><strong>حد الربح الإلزامي: {quote.percent}٪ من الكلفة الكلية</strong></div><p>الربح يُحتسب على المنظومة كاملة، ويجوز البيع بسعر أعلى.</p><div className="systemPricingNumbers"><span>الكلفة المثبتة مع المصاريف<b>{money(quote.totalCost)} د.ع</b></span><span>أقل سعر بيع مسموح<b data-testid="system-minimum-price">{money(quote.minimum)} د.ع</b></span></div>{onUseMinimum&&<button type="button" onClick={onUseMinimum}>{minimumActionLabel||'استخدام الحد الأدنى للسعر'}</button>}{price!==''&&Number(price)<quote.minimum&&<p className="systemPricingLow" role="alert">السعر أقل من الحد المسموح. ارفع السعر إلى {money(quote.minimum)} د.ع أو أكثر.</p>}<small>المصاريف المعتمدة لاحقًا تُراجع ضمن ربح المنظومة؛ تصحيح السعر يبقى من الفاتورة.</small></section>;
}
