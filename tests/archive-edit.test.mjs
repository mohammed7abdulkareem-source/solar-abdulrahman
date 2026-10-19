import test from 'node:test';
import assert from 'node:assert/strict';
import {canEditArchivedInvoice,archiveInvoiceDraft} from '../app/invoice-edit-utils.mjs';
test('archive editing belongs to an active authorized invoice creator or business administrator',()=>{
 const owner={id:'owner',active:true,user_type:'admin_staff',permissions:{sale:true,system:true}},row={kind:'sale',created_by:'owner'};
 assert.ok(canEditArchivedInvoice(owner,row));assert.ok(canEditArchivedInvoice({...owner,id:'admin',is_admin:true},row));
 for(const p of [{...owner,id:'other'}, {...owner,active:false},{...owner,permissions:{salesHistory:true}}, {...owner,is_admin:true,user_type:'warehouse'}, {...owner,is_admin:true,user_type:'installer'}])assert.equal(canEditArchivedInvoice(p,row),false);
 assert.equal(canEditArchivedInvoice(owner,{...row,created_by:'other',cashbox_user_id:'owner'}),false);
 assert.equal(canEditArchivedInvoice(owner,{...row,kind:'supplier_payment'}),false);
});
test('archive editor uses product ids and preserves original revisions, owner and workflow state',()=>{
 const r=archiveInvoiceDraft({id:40,kind:'system',created_by:'owner',cashbox_user_id:'box',receipt_no:7,pricing_revision:4,installation_revision:3,warranty_revision:2,warehouse_id:9,created_at:'2026-10-19T10:00:00Z',installation_expenses:75000,items:[{id:1000,product_id:10,product_name:'بطارية',qty:2,price:0,cost:100000}]});
 assert.equal(r.items[0].id,10);assert.equal(r.pricingRevision,4);assert.equal(r.installationRevision,3);assert.equal(r.warrantyRevision,2);assert.equal(r.createdBy,'owner');assert.equal(r.cashboxUserId,'box');assert.equal(r.warehouseId,9);assert.equal(r.receiptNo,7);assert.equal(r.installationExpenses,75000);
});
