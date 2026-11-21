'use client';
import ReportActions from './report-actions';
import {warehouseReceiptDocument} from './warehouse-receipt-document.mjs';

export default function WarehouseReceiptActions({row,transfer=false,a4}){
 const title=transfer?(row.status==='pending'?'طلب تجهيز نقل مخزني':'وصل نقل مخزني'):'وصل تجهيز مخزني';
 const html=a4(title,warehouseReceiptDocument(row,transfer));
 const filename=title+' #'+(row.receiptNo??row.id);
 return <section className="warehouseReceiptActions" aria-label={title}>
  <ReportActions html={html} filename={filename} enabled shareLabel="مشاركة وإرسال" previewVariant="warehouse"/>
 </section>;
}
