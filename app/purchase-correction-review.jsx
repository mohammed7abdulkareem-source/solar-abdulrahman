'use client';
import AppIcon from './app-icons';
import {purchaseCorrectionLines,purchaseCorrectionNumber as number,purchaseCorrectionSigned as signed} from './purchase-correction.mjs';
import './purchase-correction.css';

const unit=currency=>currency==='USD'?'$':'د.ع';
function Comparison({label,before,after,beforeUnit='',afterUnit=beforeUnit}){
 return <div className="purchaseCompare"><span>{label}</span><div><small>قبل</small><bdi>{number(before)} {before!=null&&beforeUnit}</bdi><span aria-hidden="true">←</span><small>بعد</small><strong><bdi>{number(after)} {after!=null&&afterUnit}</bdi></strong></div></div>;
}
function MaterialReview({stock, line, originalCurrency, draftCurrency}) {
 const added = line?.beforePrice === null && line.afterQty > 0;
 return (
  <article data-purchase-correction-product={stock?.id ?? line.id}>
   <div className="purchaseCorrectionMaterialHead">
    <strong dir="auto">{stock?.name || line?.name}</strong>
    {added && <span>مادة مضافة للوصل</span>}
    {stock && <span>فرق الكمية <bdi>{signed(stock.quantityDelta)}</bdi></span>}
   </div>
   {line && <div className="purchaseCorrectionLineValues">
    <Comparison label="كمية الفاتورة" before={line.beforeQty} after={line.afterQty}/>
    <Comparison label="سعر شراء الوحدة" before={line.beforePrice} after={line.afterPrice}
     beforeUnit={unit(originalCurrency)} afterUnit={unit(draftCurrency)}/>
   </div>}
   {stock && <div className="purchaseCorrectionStock">
    <Comparison label="المتاح في مخزن الوصل" before={stock.availableBefore} after={stock.availableAfter}/>
    <Comparison label="متوسط كلفة المخزون" before={stock.before.cost} after={stock.after.cost} beforeUnit="د.ع"/>
   </div>}
  </article>
 );
}
export default function PurchaseCorrectionReview({review,original,payload}){
 const lines=new Map(purchaseCorrectionLines(original,{...payload,items:review.candidate?.items||payload.items}).map(row=>[row.id,row])),data=review.data;
 const changedLines=[...lines.values()].filter(row=>row.changed);
 return <section className="purchaseCorrectionReview" aria-label="معاينة تعديل الشراء" tabIndex={-1} data-purchase-correction-review>
  <header><span className="purchaseCorrectionIcon"><AppIcon name="receipt" size={23}/></span><div><small>مراجعة قبل الحفظ · #{data.receiptNo}</small><h2>أثر تعديل وصل الشراء</h2><p>هذه معاينة فقط. لم تُحفظ التغييرات بعد.</p></div><span className={'purchaseCorrectionStatus '+(!data.canApply?'blocked':'')}>{data.canApply?'جاهز للتأكيد':'يحتاج مراجعة'}</span></header>
  {!data.canApply&&<p className="purchaseCorrectionAlert" role="alert">{data.blockedReason}</p>}
  {data.canApply&&<>
  {!data.changed&&<p className="purchaseCorrectionNote">لم تتغير كميات الشراء أو أسعاره أو مصاريفه. راجع البيانات والملاحظات قبل التأكيد.</p>}
  <div className="purchaseCorrectionMoney">
   <article><h3>قيمة وصل الشراء</h3><Comparison label="الإجمالي بالدينار" before={data.before.total} after={data.after.total} beforeUnit="د.ع"/><Comparison label="المصاريف" before={data.before.expenses} after={data.after.expenses} beforeUnit="د.ع"/><p>الفرق <bdi>{signed(data.delta.total)} د.ع</bdi></p></article>
   <article><h3>حساب المورد</h3><Comparison label="المبلغ بعملة الحساب" before={data.before.accountAmount} after={data.after.accountAmount} beforeUnit={unit(data.before.accountCurrency)} afterUnit={unit(data.after.accountCurrency)}/>{data.before.accountCurrency===data.after.accountCurrency&&<p>فرق مبلغ الوصل <bdi>{signed(data.delta.accountAmount)} {unit(data.after.accountCurrency)}</bdi></p>}<small>تسديدات المورد المسجلة بصورة مستقلة لا تتغير.</small></article>
   <article><h3>القاصة</h3><Comparison label="المدفوع من القاصة" before={data.before.cashAmount} after={data.after.cashAmount} beforeUnit={unit(data.before.cashCurrency)} afterUnit={unit(data.after.cashCurrency)}/>{data.before.cashCurrency===data.after.cashCurrency&&<p>{Number(data.delta.cashAmount)>0?'دفع إضافي':Number(data.delta.cashAmount)<0?'استرجاع إلى القاصة':'لا فرق على القاصة'} <bdi>{Number(data.delta.cashAmount)!==0?number(Math.abs(Number(data.delta.cashAmount)))+' '+unit(data.after.cashCurrency):''}</bdi></p>}</article>
  </div>
  <section className="purchaseCorrectionProfit" aria-label="أثر التصحيح على الأرباح"><h3>كلفة وربح الكميات المتأثرة فقط</h3><p>الوصولات المتأثرة المتاحة لك: <b>{number(data.affectedSales.count)}</b></p><Comparison label="أرباح هذه الوصولات" before={data.affectedSales.profitBefore} after={data.affectedSales.profitAfter} beforeUnit="د.ع"/><p>فرق الربح <bdi>{signed(data.affectedSales.profitDelta)} د.ع</bdi></p><small>أسعار بيع الزبائن وحساباتهم والتسديدات والتوزيعات الفعلية لا تتغير. يظهر فرق الربح في المستحق المتبقي.</small></section>
  {(data.items.length>0||changedLines.length>0)&&<div className="purchaseCorrectionMaterials"><div className="purchaseCorrectionSectionTitle"><h3>{data.items.length?'المواد والمخزون':'مواد الفاتورة المعدّلة'}</h3><span>{data.items.length||changedLines.length} صنف</span></div>
   {data.items.length
    ? data.items.map(stock => <MaterialReview key={stock.id} stock={stock} line={lines.get(String(stock.id))}
        originalCurrency={original.sourceCurrency} draftCurrency={payload.sourceCurrency}/>)
    : changedLines.map(line => <MaterialReview key={line.id} line={line}
        originalCurrency={original.sourceCurrency} draftCurrency={payload.sourceCurrency}/>)}
  </div>}
  <p className="purchaseCorrectionNote">الأرقام مبنية على الرصيد الحالي عند المعاينة. إذا تغيرت البيانات قبل الحفظ، يلزم تحديث المعاينة.</p>
  </>}
 </section>;
}
