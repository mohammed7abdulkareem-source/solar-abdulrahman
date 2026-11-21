import {escapeHtml as escape,invoiceDate} from './document-format.mjs';
import {materialQuantity,materialItemTotal} from './material-quantity.mjs';
import {warrantyDocument,warrantyQrSvg} from './warranty-utils.mjs';

const statuses={
 pending:'بانتظار التجهيز',ready:'تم التجهيز',pricing:'بانتظار تسعير المواد',
 posted:'تم تجهيز النقل',cancelled:'ملغى قبل التجهيز',reversed:'ملغى بعد التجهيز'
};

const receiptStyle=`<style>
.warehouseSlip{line-height:1.6;color:#173849;print-color-adjust:exact;-webkit-print-color-adjust:exact}
.warehouseSlip .wsHead{padding:15px 18px;background:#eaf4f4;border:1px solid #bad7d6;border-inline-start:6px solid #146b73;border-radius:8px;display:flex;align-items:center;gap:16px;justify-content:space-between}
.warehouseSlip .wsIdentifier{display:grid;gap:1px}.warehouseSlip .wsIdentifier small{font-size:12px;color:#3b6269;font-weight:700}.warehouseSlip .wsIdentifier strong{font-size:28px;color:#103e4a;line-height:1.2}
.warehouseSlip .wsWhen{font-size:13px;color:#405b67;text-align:end;display:grid;gap:5px;justify-items:end}
.warehouseSlip .wsStatus{display:inline-block;padding:3px 12px;border:1px solid;border-radius:4px;font-weight:800;font-size:14px;line-height:1.6}
.warehouseSlip .wsStatus.pending{color:#794500;background:#fff1cc;border-color:#d7b96e}
.warehouseSlip .wsStatus.ready,.warehouseSlip .wsStatus.posted{color:#16533c;background:#dbf1e7;border-color:#80bda2}
.warehouseSlip .wsStatus.pricing{color:#633f87;background:#f2eafa;border-color:#b69bcc}
.warehouseSlip .wsStatus.cancelled,.warehouseSlip .wsStatus.reversed{color:#763c42;background:#f8e9e9;border-color:#cfaaac}
.warehouseSlip .wsInfo{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:0 18px;margin:10px 0 15px}
.warehouseSlip .wsInfo>div{padding:8px 1px;border-bottom:1px solid #d9e4e7;min-width:0}.warehouseSlip .wsInfo dt{font-size:12px;color:#4a6773;font-weight:700}.warehouseSlip .wsInfo dd{margin:0;font-size:16px;font-weight:700;color:#183a47;overflow-wrap:anywhere}
.warehouseSlip .wsInfo .wsQr svg{height:84px;width:84px;max-width:100%}
.warehouseSlip .wsMaterials{border:0;margin:14px 0 0;font-size:14px;table-layout:fixed}
.warehouseSlip .wsMaterials caption{text-align:start;color:#164b56;font-size:17px;font-weight:800;margin:0 0 6px}
.warehouseSlip .wsMaterials th{font-size:13px;background:#184f5c!important;color:white!important;padding:7px 10px}
.warehouseSlip .wsMaterials th,.warehouseSlip .wsMaterials td{border:1px solid #cadadf!important}
.warehouseSlip .wsMaterials td{padding:8px 10px;font-weight:500!important;font-size:15px}
.warehouseSlip .wsMaterials .wsMaterial,.warehouseSlip .wsMaterials th:nth-child(2){text-align:start}
.warehouseSlip .wsMaterial b,.warehouseSlip .wsMaterial small{display:block;overflow-wrap:anywhere}.warehouseSlip .wsMaterial small{font-size:12px;color:#4e6873!important;font-weight:400!important}
.warehouseSlip .wsMaterials .wsQty{font-variant-numeric:tabular-nums;font-size:17px;font-weight:800!important;color:#075a62!important;background:#eff7f5}
.warehouseSlip .wsMaterials tfoot td{background:#e1f0ed!important;color:#164e54!important;font-size:14px;font-weight:800!important}
.warehouseSlip .wsTotal{text-align:start}.warehouseSlip .wsTotal small{color:#47656c!important;font-size:12px;font-weight:500!important;margin-inline-start:10px}
.warehouseSlip .wsNotes{color:#263f4d;font-size:14px;white-space:pre-line;margin:10px 0 0;overflow-wrap:anywhere}.warehouseSlip .wsNotes b{display:block;color:#184c55}
</style>`;

function field(label,value,ltr=false){
 if(value==null||value==='')return '';
 return '<div><dt>'+label+'</dt><dd><bdi dir="'+(ltr?'ltr':'auto')+'">'+escape(value)+'</bdi></dd></div>';
}

function note(label,text){
 return text?'<div class="wsNotes" data-pdf-end><b>'+label+'</b>'+escape(text)+'</div>':'';
}

export function warehouseReceiptDocument(row,transfer=false){
 const items=row.items||[];
 const state=!transfer&&row.status==='pending'&&row.pricingPending?'pricing':row.status;
 const status=Object.hasOwn(statuses,state)?state:'unknown';
 const prepared=['ready','posted','reversed'].includes(status);
 const qr=!transfer&&row.warranty?.enabled?warrantyQrSvg(row.warehouseQrToken):'';
 const fields=transfer?
  field('المخزن المصدر',row.fromName)+field('المخزن المستلم',row.toName)+field('طلب النقل',row.actor):
  field('مخزن التجهيز',row.warehouseName)+field('الزبون',row.party||'زبون نقدي')+
  field('هاتف الزبون',row.phone,true)+field('عنوان التجهيز',row.address)+field('مسؤول الفاتورة',row.creatorName);
 const preparation=prepared?field('جهّز الوصل',row.preparedBy||'اسم المجهّز غير مسجّل')+field('تاريخ التجهيز',row.preparedAt?invoiceDate(row.preparedAt):null,true):'';
 const cancelledDate=status==='cancelled'?row.cancelledAt:status==='reversed'?row.reversedAt:null;
 const info=fields+preparation+field('تاريخ الإلغاء',cancelledDate?invoiceDate(cancelledDate):null,true)+
  (qr?'<div class="wsQr"><dt>فحص ضمان الوصل</dt><dd>'+qr+'</dd></div>':'');
 const scope=transfer?'رقم طلب النقل':row.kind==='system'?'رقم فاتورة المنظومة':'رقم فاتورة البيع';
 const head='<header class="wsHead"><div class="wsIdentifier"><small>'+scope+'</small><strong><bdi dir="ltr">#'+escape(row.receiptNo??'—')+'</bdi></strong></div><div class="wsWhen"><span class="wsStatus '+status+'">'+(statuses[status]||'حالة غير محددة')+'</span><bdi dir="ltr">'+invoiceDate(row.date)+'</bdi></div></header>';
 const lines=items.map((item,index)=>{
  const details=[item.code,item.brand,item.category].filter(Boolean).map(value=>'<bdi>'+escape(value)+'</bdi>').join(' · ');
  return '<tr><td>'+(index+1)+'</td><td class="wsMaterial"><b dir="auto">'+escape(item.name)+'</b>'+(details?'<small>'+details+'</small>':'')+'</td><td class="wsQty"><bdi dir="ltr">'+escape(materialQuantity(item.qty))+'</bdi></td></tr>';
 }).join('');
 const table='<table class="wsMaterials" data-pdf-paginate data-pdf-keep-footer-with-row><caption>'+(transfer?'مواد طلب النقل':'مواد التجهيز')+'</caption><colgroup><col style="width:7%"><col style="width:74%"><col style="width:19%"></colgroup><thead><tr><th scope="col">ت</th><th scope="col">المادة</th><th scope="col">'+(prepared?'الكمية المجهّزة':'الكمية المطلوبة')+'</th></tr></thead><tbody>'+
  (lines||'<tr><td colspan="3">لا توجد مواد مسجّلة في الوصل.</td></tr>')+'</tbody><tfoot><tr><td colspan="2" class="wsTotal">مجموع الكميات <small>عدد الفقرات '+items.length+'</small></td><td class="wsQty"><bdi dir="ltr">'+escape(materialItemTotal(items))+'</bdi></td></tr></tfoot></table>';
 const warranty=!transfer&&row.warranty?.enabled?warrantyDocument({created_at:row.date,warranty:row.warranty,items:items.map(item=>({product_id:item.productId,product_name:item.name,category:item.category,brand_name:item.brand}))},{hasQr:!!qr}):'';
 return '<section class="warehouseSlip" data-slip-status="'+status+'">'+receiptStyle+head+'<dl class="wsInfo">'+info+'</dl>'+table+
  note(transfer?'ملاحظات النقل':'ملاحظات التجهيز',row.note)+(transfer&&['cancelled','reversed'].includes(status)?note('سبب الإلغاء',row.cancellationNote):'')+warranty+'</section>';
}
