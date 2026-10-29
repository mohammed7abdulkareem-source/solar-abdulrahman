'use client';
import AppIcon from './app-icons';
import WarehouseBadge from './warehouse-badge';
import SalePreparation from './sale-preparation';
import WarrantyManage from './warranty-manage';
import {statusLabel,formatMoney} from './sales-document.mjs';
import {receiptNumber} from './supplier-utils.mjs';

function CopyActions({row,customer,doc,openA4,saveA4,shareA4}){
 const copy=customer?'الزبون':'المخزن',number=receiptNumber(row),filename=(customer?'وصل-زبون-':'وصل-مخزني-')+number;
 return <div className="saleHistoryCopyGroup" role="group" aria-label={'وصل '+copy}>
  <button type="button" className="saleHistoryAction share" aria-label={'مشاركة PDF '+copy} onClick={()=>shareA4(filename,customer?'فاتورة '+number+' - '+(row.party_name||'زبون نقدي'):'وصل مخزني '+number,doc(row,customer))}><span className="saleHistoryActionIcon"><AppIcon name="share" size={21}/></span><span>مشاركة<br/>{copy}</span></button>
  <button type="button" className="saleHistoryAction pdf" aria-label={'حفظ PDF '+copy} onClick={()=>saveA4(doc(row,customer),filename)}><span className="saleHistoryActionIcon"><AppIcon name="document" size={21}/><small>PDF</small></span><span>حفظ<br/>{copy}</span></button>
  <button type="button" className={'saleHistoryAction '+(customer?'customerPreview':'warehousePreview')} aria-label={customer?'معاينة وصل الزبون':'معاينة الوصل المخزني'} onClick={()=>openA4(doc(row,customer))}><span className="saleHistoryActionIcon"><AppIcon name={customer?'eye':'warehouse'} size={21}/></span><span>معاينة<br/>{copy}</span></button>
 </div>;
}
export default function SalesArchiveCard({row,profile,warehouseStatus,doc,openA4,saveA4,shareA4,onFollow,onDelete,deleting,onWarrantyChanged,onPrepared,onEdit,editBusy=false}){
 const system=row.kind==='system',items=row.items||[],date=new Date(row.created_at).toLocaleDateString('en-CA',{timeZone:'Asia/Baghdad'}).replaceAll('-','/');
 return <article className="card archiveInvoice saleHistoryCard" aria-label={(system?'بيع منظومة':'بيع جملة')+' رقم '+receiptNumber(row)}>
  <header className="saleHistoryHeader">
   <div className="saleHistoryIdentity"><div className="saleHistoryReceipt"><AppIcon name={system?'sun':'truck'} size={18}/><span>{system?'بيع منظومة':'بيع جملة'}</span><bdi>#{receiptNumber(row)}</bdi></div>
    <div className="saleHistoryCustomer"><span className="saleHistoryCustomerIcon"><AppIcon name="building" size={21}/></span><h3>{row.party_name||'زبون نقدي'}</h3></div>
    <div className="saleHistoryMeta"><span><AppIcon name="calendar" size={15}/><time dateTime={row.created_at}><bdi>{date}</bdi></time></span><span><AppIcon name="user" size={15}/>{row.creatorName||'—'}</span></div>
   </div>
   <div className="saleHistoryTotal" data-wide-amount={formatMoney(row.total).length>12}><div><span className="saleHistoryMoneyIcon"><AppIcon name="coins" size={20}/></span><strong><bdi dir="ltr">{formatMoney(row.total)}</bdi><small>د.ع</small></strong></div><span>{system?'إجمالي قيمة المنظومة':'إجمالي قيمة الجملة'}</span></div>
  </header>
  <div className={'saleHistoryWarehouse '+(warehouseStatus==='ready'?'ready':'pending')}><span><AppIcon name="warehouse" size={20}/>مخزن التجهيز: {row.warehouse_name||row.warehouseName||'غير محدد'}</span><WarehouseBadge status={warehouseStatus} compact/></div>
  {!system&&<SalePreparation invoice={{...row,warehouse_status:warehouseStatus}} profile={profile} onPrepared={onPrepared}/>}
  {system&&<div className="saleHistoryInstallation"><AppIcon name="tools" size={15}/><span>{statusLabel[row.installation_status]||'غير محدد'} · المهندس: {row.installerName||'غير محدد'}</span></div>}
  <details className="saleHistoryMaterials"><summary><span><AppIcon name="package" size={19}/>تفاصيل المواد ({items.length})</span><AppIcon name="chevron" size={17}/></summary><div className="saleHistoryMaterialRows">{items.map((item,i)=><div className="archiveLine" key={item.id||i}><span>{item.product_name}<small>{[item.brand_name,item.category].filter(Boolean).join(' · ')}</small></span><b>× <bdi>{formatMoney(item.qty)}</bdi></b></div>)}</div></details>
  <div className="saleHistoryCopies"><CopyActions {...{row,doc,openA4,saveA4,shareA4}} customer/><CopyActions {...{row,doc,openA4,saveA4,shareA4}} customer={false}/></div>
  {((profile?.is_admin||(row.created_by===profile?.id&&profile?.permissions?.[row.kind]))||(system&&onFollow)||onEdit)&&<div className="saleHistoryUtilities">{onEdit&&<button type="button" className="saleHistoryEdit" disabled={deleting!==null||editBusy} onClick={()=>onEdit(row)}><AppIcon name="edit" size={16}/>تعديل الفاتورة</button>}
   {(profile?.is_admin||(row.created_by===profile?.id&&profile?.permissions?.[row.kind]))&&<WarrantyManage invoiceId={row.id} onChanged={onWarrantyChanged}/>}
   {system&&onFollow&&<button type="button" className="workflowSecondary archiveFollow" onClick={()=>onFollow(String(row.id))}><AppIcon name="tools" size={15}/>متابعة ملف التنصيب</button>}
  </div>}
  {row.canDelete&&<button type="button" className="dangerMini archiveDelete saleHistoryDelete" disabled={deleting!==null} onClick={()=>onDelete(row)}><AppIcon name="trash" size={18}/>{deleting===row.id?'جاري إرسال الطلب…':'طلب حذف الوصل'}</button>}
 </article>;
}
