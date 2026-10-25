'use client';
import {useState} from 'react';
import {salesDocument} from './sales-document.mjs';
import {formatMoney} from './money-format.mjs';
import {warrantyUrl} from './warranty-utils.mjs';
import ReportActions from './report-actions';
import AppIcon from './app-icons';

export default function SavedSaleReceipt({invoice,a4,onNew}){
 const [warehouseOpen,setWarehouseOpen]=useState(false);
 const customer=salesDocument(invoice),warehouse=salesDocument(invoice,false);
 return <section className="invoiceSavedReceipt" aria-label="الفاتورة المحفوظة">
  <header><span className="invoiceSavedCheck"><AppIcon name="check" size={22}/></span><div role="status"><h1>تم حفظ الفاتورة وإرسالها للمخزن</h1><p>فاتورة بيع جملة <bdi>#{invoice.receiptNo}</bdi> · {invoice.warehouseName}</p></div></header>
  <div className="invoiceSavedTotal"><span>مبلغ الفاتورة المحفوظة</span><strong><bdi>{formatMoney(invoice.total)} د.ع</bdi></strong></div>
  <h2>نسخة الزبون</h2>
  <ReportActions enabled html={a4(customer.title,customer.body,customer.total,customer.subtitle)} filename={'فاتورة-بيع-'+invoice.receiptNo}/>
  {invoice.warranty?.enabled&&invoice.warrantyToken&&<a className="invoiceSavedWarranty" target="_blank" rel="noopener noreferrer" href={warrantyUrl(invoice.warrantyToken)}>فتح شهادة الضمان</a>}
  <details className="invoiceSavedWarehouse" open={warehouseOpen} onToggle={e=>setWarehouseOpen(e.currentTarget.open)}><summary>نسخة المخزن</summary>{warehouseOpen&&<ReportActions enabled html={a4(warehouse.title,warehouse.body,warehouse.total,warehouse.subtitle)} filename={'فاتورة-مخزنية-'+invoice.receiptNo}/>}</details>
  <button type="button" className="invoiceSavedNew" onClick={onNew}><AppIcon name="add" size={17}/>فاتورة جديدة</button>
 </section>;
}
