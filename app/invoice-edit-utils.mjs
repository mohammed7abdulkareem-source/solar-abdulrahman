import {canOpenPage,isAdministrator,isEngineer,isWarehouse} from './access-utils.mjs';
export function canEditArchivedInvoice(profile,row){
 if(!profile?.active||isEngineer(profile)||isWarehouse(profile)||!['sale','system'].includes(row?.kind))return false;
 return isAdministrator(profile)||((row.created_by||row.createdBy)===profile.id&&canOpenPage(profile,row.kind));
}
export function archiveInvoiceDraft(row){
 return {...row,createdBy:row.created_by||row.createdBy,party:row.party_name||row.party||'',partyId:row.party_id??row.partyId,receiptNo:row.receipt_no??row.receiptNo,date:row.created_at||row.date,
  sourceCurrency:row.source_currency||row.sourceCurrency||'IQD',exchangeRate:Number(row.exchange_rate??row.exchangeRate??1),marketRate:Number(row.market_rate??row.marketRate??1),cashCurrency:row.cash_currency||row.cashCurrency||'IQD',cashboxUserId:row.cashbox_user_id||row.cashboxUserId,
  pricingRevision:Number(row.pricing_revision??row.pricingRevision??0),warrantyRevision:Number(row.warranty_revision??row.warrantyRevision??0),warehouseId:row.warehouse_id??row.warehouseId,warehouseName:row.warehouse_name||row.warehouseName,
  invoiceAccount:row.invoice_account||row.invoiceAccount,warehouseQrToken:row.warehouse_qr_token||row.warehouseQrToken,warrantyToken:row.warranty_token||row.warrantyToken,
  installerId:row.installer_id||row.installerId,installDate:row.install_date||row.installDate||'',installTime:row.install_time||row.installTime||'',customerAddress:row.customer_address||row.customerAddress||'',customerPhone:row.customer_phone||row.customerPhone||'',
  installationRevision:Number(row.installation_revision??row.installationRevision??0),installationStatus:row.installation_status||row.installationStatus,installationExpenses:Number(row.installation_expenses??row.installationExpenses??0),
  items:(row.items||[]).map(i=>({...i,id:i.product_id??i.productId??i.id,name:i.product_name||i.name,brand:i.brand_name||i.brand||'',qty:Number(i.qty),price:Number(i.price||0),cost:Number(i.cost||0)}))};
}

export function canEditInstallationExpenses(profile,row){return !!profile?.active&&!isEngineer(profile)&&!isWarehouse(profile)&&(isAdministrator(profile)||((row.created_by||row.createdBy)===profile.id&&profile.permissions?.installations===true));}
