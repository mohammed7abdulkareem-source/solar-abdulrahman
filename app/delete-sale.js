import {requestReceiptDeletion} from './receipt-deletion.mjs';
export async function deleteSale(id,profile){const result=await requestReceiptDeletion(id,undefined,profile);return result?{...result,pending:!result.direct&&result.status!=='deleted'}:false;}
