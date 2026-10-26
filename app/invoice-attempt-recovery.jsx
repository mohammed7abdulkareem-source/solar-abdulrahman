'use client';
import {useEffect,useRef} from 'react';
import {createPortal} from 'react-dom';
import {formatMoney} from './money-format.mjs';
const kindName=kind=>({system:'منظومة',sale:'بيع جملة',purchase:'شراء'})[kind]||'فاتورة';
export default function InvoiceAttemptRecovery({pending,recovery,busy,feedback,onCheck,onClose,onContinue,onReview,onDismiss}){
 const dialog=useRef(null),close=useRef(onClose),invoice=recovery?.invoice;close.current=onClose;
 useEffect(()=>{
  if(!invoice)return;const previous=document.activeElement,overflow=document.body.style.overflow;document.body.style.overflow='hidden';dialog.current?.querySelector('button')?.focus();
  const key=e=>{if(e.key==='Escape'){e.preventDefault();close.current();}if(e.key==='Tab'){const nodes=[...dialog.current.querySelectorAll('button:not([disabled])')],first=nodes[0],last=nodes.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}};
  document.addEventListener('keydown',key);return()=>{document.body.style.overflow=overflow;document.removeEventListener('keydown',key);previous?.focus?.();};
 },[invoice]);
 return createPortal(invoice?<div className="invoiceAttemptOverlay"><section ref={dialog} role="dialog" aria-modal="true" aria-label="نتيجة تأكيد حفظ الفاتورة" className="invoiceAttemptDialog"><button className="invoiceAttemptClose" type="button" aria-label="إغلاق نتيجة الحفظ" onClick={onClose}>×</button><h2>الفاتورة محفوظة بالفعل</h2><p>وصل {kindName(invoice.kind)} <b>#{invoice.receiptNo}</b></p><div className="invoiceAttemptReceipt"><strong>{invoice.party||'نقدي'}</strong><b><bdi>{formatMoney(invoice.total)}</bdi> د.ع</b></div><p>لم نحفظ المسودة الحالية مرة ثانية. راجع الوصل المحفوظ لتعديله؛ متابعة المسودة كعملية أخرى قد تُنشئ فاتورة مستقلة.</p><div className="invoiceAttemptActions">{onReview&&<button type="button" onClick={()=>onReview(invoice)}>مراجعة الوصل المحفوظ</button>}<button type="button" className="secondary" onClick={onContinue}>سأكمل بعملية أخرى</button><button type="button" className="secondary" onClick={onClose}>الرجوع للمسودة</button></div></section></div>:<aside className="invoiceAttemptNotice" aria-label="متابعة محاولة حفظ الفاتورة"><div><strong>{pending?'حفظ سابق يحتاج تأكيدًا':'حالة حفظ الفاتورة'}</strong><p role="status">{feedback||(pending?'تحقق من '+kindName(pending.payload.kind)+' · '+(pending.payload.party||'نقدي')+' قبل إعادة الحفظ.':'')}</p></div>{pending&&<button type="button" disabled={busy} onClick={onCheck}>{busy?'جاري التحقق…':'التحقق من الحفظ السابق'}</button>}{!pending&&<button type="button" aria-label="إغلاق حالة الحفظ" onClick={onDismiss}>×</button>}</aside>,document.body);
}
