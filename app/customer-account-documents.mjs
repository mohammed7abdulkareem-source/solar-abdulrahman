import {salesDocument} from './sales-document.mjs';
import {systemPaymentDocument} from './system-payment-utils.mjs';
import {compactMovementBody} from './compact-party-utils.mjs';
import {formatMoney as money} from './money-format.mjs';
import {escapeHtml as e} from './document-format.mjs';

export const periodDocumentLabel=category=>category==='invoices'?'مبيعات الفترة':category==='payments'?'تسديدات الفترة':'حركات الفترة';
export function customerMovementDocument(data,account){
 if(data.type==='invoice')return salesDocument({...data.invoice,customer_phone:data.invoice.customer_phone||account.phone},true);
 if(data.type==='payment')return systemPaymentDocument(data.receipt);
 const movement=data.movement;
 return {title:movement.label,body:compactMovementBody(account,{...movement,original:movement}),total:money(movement.amount)+' د.ع',subtitle:account.name};
}
export function movementHtml(data,account,a4){
 const d=customerMovementDocument(data,account);
 return a4(e(d.title),d.body,d.total,e(d.subtitle));
}
// Preserve each original invoice's own heading, totals, warranty and QR in a single file.
export function combineCustomerDocuments(rows,account,a4,title){
 if(!rows.length)return '';
 const parser=new DOMParser(),documents=rows.map(row=>parser.parseFromString(movementHtml(row,account,a4),'text/html'));
 const sheets=documents.map(doc=>{const sheet=doc.querySelector('.sheet');if(!sheet)throw new Error('تعذر تجهيز أحد الوصولات');return sheet.cloneNode(true);});
 const result=documents[0];result.title=title;result.body.replaceChildren();
 for(const sheet of sheets)result.body.append(result.importNode(sheet,true));
 const style=result.createElement('style');style.textContent='.sheet{break-after:page}.sheet:last-child{break-after:auto}';result.head.append(style);
 return '<!doctype html>'+result.documentElement.outerHTML;
}
