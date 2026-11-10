import {requestReceiptDeletion} from './receipt-deletion.mjs';
export async function deleteSale(id){const result=await requestReceiptDeletion(id);return result?{...result,pending:!result.direct&&result.status!=='deleted'}:false;}
