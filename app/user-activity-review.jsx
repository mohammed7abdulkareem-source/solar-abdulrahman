'use client';
import {useState} from 'react';
import MoneyInput from './money-input';
import {formatMoney,currencyUnit} from './money-format.mjs';
import {dateKey} from './supplier-utils.mjs';
import './user-activity-review.css';

const sources={
 transfer_out:'خصم من القاصة المرسلة',transfer_in:'إضافة إلى القاصة المستلمة',transfer_refund:'إرجاع إلى القاصة المرسلة',
 handover_expense:'مصروف عند التسليم',transfer_transit:'حساب المبالغ قيد التسليم',
 admin_transfer_out:'خصم التسليم المباشر',admin_transfer_in:'إضافة التسليم المباشر'
};
const amount=(value,currency)=><><bdi dir="ltr">{formatMoney(value,currency)}</bdi> {currencyUnit(currency)}</>;

function CashCount({book}){
 const [currency,setCurrency]=useState('IQD'),[entered,setEntered]=useState('');
 const valid=entered!==''&&Number.isFinite(Number(entered))&&Number.isSafeInteger(Math.round(Number(entered)*100));
 const difference=valid?Math.round((Number(entered)-Number(book[currency]))*100)/100:null;
 return <section className="activityCard activityCashCount">
  <h3>مطابقة الجرد الفعلي</h3><p>عدّ النقد الموجود بالقاصة وأدخله للمقارنة مع الرصيد الحالي. هذه المقارنة للعرض فقط.</p>
  <div className="activityCountFields"><label>عملة الجرد<select value={currency} onChange={event=>{setCurrency(event.target.value);setEntered('');}}>
   <option value="IQD">دينار عراقي</option><option value="USD">دولار أمريكي</option></select></label>
   <label>المبلغ المعدود فعلياً<MoneyInput value={entered} currency={currency} onChange={setEntered} placeholder="أدخل المبلغ"/></label>
  </div>
  <div className="activityCountBook">الرصيد المسجّل الآن <strong>{amount(book[currency],currency)}</strong></div>
  {valid&&<p className={'activityCountResult '+(difference?'hasGap':'matches')} aria-live="polite">{difference===0?'الجرد مطابق للرصيد المسجّل':difference<0?'النقد المعدود أقل من المسجّل بمقدار':'النقد المعدود أكثر من المسجّل بمقدار'} {difference!==0&&<strong>{amount(Math.abs(difference),currency)}</strong>}</p>}
 </section>;
}

export default function UserActivityReview({review}){
 if(!review)return <p role="status">بيانات المطابقة غير متاحة.</p>;
 return <div className="activityReview">
  {review.book?.IQD!=null&&review.book?.USD!=null&&<CashCount key={[review.ownerId,review.book.IQD,review.book.USD].join('|')} book={review.book}/>}
  <section className="activityCard"><h3>مطابقة قيود التسليم</h3>
   <p>تُطابَق وصولات التسليم مع الخصم والاستلام أو الإرجاع حسب حالة كل تحويل في الفترة المختارة.</p>
   <dl className="activityReviewTotals"><div><dt>التحويلات المفحوصة</dt><dd>{formatMoney(review.checkedTransfers)}</dd></div>
    <div><dt>قيود تحتاج مراجعة</dt><dd>{formatMoney(review.differenceCount)}</dd></div></dl>
   {review.differenceCount===0?<p className="activityReviewStatus">{review.checkedTransfers?'تطابقت قيود التحويلات المفحوصة.':'ماكو تحويلات ضمن هالفترة.'}</p>:
   <><p>راجع الوصل مع القاصتين لمعرفة سبب الفرق.</p><ul className="activityReviewList">{review.differences.map((r,i)=><li key={[r.ref,r.kind,r.currency,i].join('/')}>
    <strong>{sources[r.kind]||'قيد تحويل'}</strong> <small>{dateKey(r.at)}</small>
    <div>{r.receiptNo?'وصل التسليم #'+r.receiptNo:'مرجع التحويل'} <bdi dir="ltr">{!r.receiptNo&&r.ref}</bdi></div>
    <dl><div><dt>المتوقّع</dt><dd>{amount(r.expected,r.currency)}</dd></div><div><dt>المسجّل</dt><dd>{amount(r.posted,r.currency)}</dd></div><div><dt>الفرق · المسجّل ناقص المتوقّع</dt><dd>{amount(Number(r.posted)-Number(r.expected),r.currency)}</dd></div></dl>
    {r.expectedCount!==r.postedCount&&<small>عدد القيود المتوقّع {r.expectedCount}، والمسجّل {r.postedCount}.</small>}
   </li>)}</ul>{review.differenceCount>review.differences.length&&<p>تظهر أحدث {review.differences.length} نتيجة. حدّد فترة أقصر لمراجعة الباقي.</p>}</>}
  </section>
 </div>;
}
