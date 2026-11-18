import {canOpenPage,isAdministrator,isEngineer,isWarehouse} from './access-utils.mjs';

export function cloudSnapshotAccess(profile){
 const office=!!profile?.id&&profile.active===true&&!isEngineer(profile)&&!isWarehouse(profile);
 const can=page=>office&&canOpenPage(profile,page);
 const admin=office&&isAdministrator(profile);
 const purchases=can('purchase');
 const kinds=[];
 if(can('sale'))kinds.push('sale');
 if(can('system'))kinds.push('system');
 if(purchases)kinds.push('purchase');
 // Payment editors use the original cashbox owner to verify that an editable row belongs to the caller.
 if(can('customerPayment'))kinds.push('customer_payment');
 if(can('systemPayment'))kinds.push('system_payment');
 if(can('supplierPayment'))kinds.push('supplier_payment');
 const invoiceKinds=kinds.filter(kind=>['sale','system','purchase'].includes(kind));
 // The account, history, stock-movement and cash workspaces have their own protected reads.
 const inventory=['products','stock','sale','purchase','system'].some(can);
 return {
  catalog:inventory?'inventory':can('tahseel')?'quote':null,
  brands:can('products')||can('brands'),
  customers:can('sale')||can('system')||can('customers')||can('customerDebts'),
  suppliers:purchases||can('suppliers')||can('supplierPayment')||can('supplierStatement'),
  staff:admin||can('system'),
  transactions:admin||kinds.length>0,transactionKinds:admin?null:kinds,
  items:admin||invoiceKinds.length>0,itemKinds:admin?null:invoiceKinds,
  receiptContacts:admin||invoiceKinds.length>0,
  cashBalances:can('cash'),cashEntries:admin,fxHistory:admin
 };
}
