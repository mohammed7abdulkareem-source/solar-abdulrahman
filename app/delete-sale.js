import {requestReceiptDeletion} from './receipt-deletion.mjs';
export async function deleteSale(id){const request=await requestReceiptDeletion(id);return request?{...request,pending:true}:false;}
