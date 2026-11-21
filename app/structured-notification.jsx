'use client';
import {useId,useState} from 'react';
import AppIcon from './app-icons';
import {formatMoney} from './money-format.mjs';
import {notificationQuantity} from './notification-details.mjs';

function PriceInfo({item}){
 if(item.enabled===null)return <span className="structuredNoticePrice">حالة التسعير غير متاحة</span>;
 if(item.minPrice!==null)return <>
  <strong className="structuredNoticePrice"><bdi>{formatMoney(item.minPrice)}</bdi><small>د.ع</small></strong>
  <span className="structuredNoticePriceState required">سعر يدوي مُفعّل</span>
 </>;
 return <>
  <strong className="structuredNoticePrice">تلقائي</strong>
  <span className="structuredNoticePriceState unknown">حسب متوسط كلفة الشراء</span>
  {item.inactiveManualPrice!=null&&<small>سعر يدوي كان محفوظاً وغير مفعّل <bdi>{formatMoney(item.inactiveManualPrice)} د.ع</bdi></small>}
 </>;
}

export default function StructuredNotification({notice,data,onRead}){
 const [expanded,setExpanded]=useState(false),id=useId();
 const label=data.purchase?'المواد المستلمة':'أسعار البيع المحدّثة';
 return <article className={'structuredNotice '+(data.purchase?'purchase':'pricing')+(notice.read_at?' read':'')} data-notification-id={notice.id}>
  <button type="button" className="structuredNoticeToggle" aria-expanded={expanded} aria-controls={id} aria-describedby={data.purchase&&data.warehouseName?id+'-warehouse':undefined} aria-label={(expanded?'إخفاء تفاصيل ':'عرض تفاصيل ')+label} onClick={()=>{setExpanded(value=>!value);if(!expanded)onRead();}}>
   <span className="structuredNoticeIcon"><AppIcon name={data.purchase?'package':'tag'} size={20}/></span>
   <span className="structuredNoticeHeading"><strong>{data.title}</strong>{data.purchase&&data.warehouseName&&<span id={id+'-warehouse'} className="structuredNoticeWarehouse"><AppIcon name="warehouse" size={14}/><span>المخزن: <bdi>{data.warehouseName}</bdi></span></span>}<span>{data.itemSummary||data.summary}</span><time dateTime={notice.created_at}>{new Date(notice.created_at).toLocaleString('ar-IQ',{timeZone:'Asia/Baghdad'})}</time></span>
   <AppIcon className="structuredNoticeArrow" name="chevron" size={17}/>
  </button>
  {expanded&&<div id={id} className="structuredNoticeDetails" role="region" aria-label={'تفاصيل '+label}>
   {data.items===null?<p className="structuredNoticeUnavailable">تفاصيل المواد غير متاحة حاليًا. حدّث قائمة الإشعارات وأعد فتح الإشعار.</p>:!data.items.length?<p className="structuredNoticeUnavailable">لا توجد فقرات مواد في هذا الإشعار.</p>:<>
    <table className="structuredNoticeTable"><caption>{label} · {data.items.length} فقرة</caption><colgroup><col/><col className="structuredNoticeValueColumn"/></colgroup><thead><tr><th scope="col">وصف المادة</th><th scope="col">{data.purchase?'العدد':'مرجع سعر الجملة'}</th></tr></thead><tbody>{data.items.map((item,index)=><tr key={index} data-notification-item={index}>
     <td><strong className="structuredNoticeMaterial" dir="auto">{item.name}</strong><dl className="structuredNoticeIdentity"><div><dt>النوع</dt><dd dir="auto">{item.category||'غير محدد'}</dd></div><div><dt>البراند</dt><dd dir="auto">{item.brand||'غير محدد'}</dd></div></dl></td>
     <td className="structuredNoticeValue">{data.purchase?<bdi className="structuredNoticeQuantity">{item.qty===null?'—':notificationQuantity(item.qty)}</bdi>:<PriceInfo item={item}/>}</td>
    </tr>)}</tbody></table>
    {!data.purchase&&<p className="structuredNoticeFootnote">عند تطبيق حد بيع الجملة، يعتمد السعر التلقائي متوسط كلفة الشراء بالدينار حسب سعر الصرف المعتمد وقت البيع.</p>}
   </>}
  </div>}
 </article>;
}
