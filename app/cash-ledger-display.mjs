export function cashRowBalance(row,ownerId){
 const value=row.ownerBalance??(ownerId?row.balance:null);
 return value==null||String(value).trim()===''||!Number.isFinite(Number(value))?null:Number(value);
}

export function cashTransferDecisionLabel(kind,status){
 if(kind==='admin_transfer_in'||kind==='admin_transfer_out')return 'نفّذ التحويل';
 return {accepted:'اعتمد الاستلام',rejected:'رفض الاستلام',cancelled:'ألغى التحويل'}[status]||'سجّل القرار';
}

export function cashTransferFacts(kind,transfer,full=false){
 const incoming=kind==='transfer_in'||kind==='admin_transfer_in';
 const outgoing=kind==='transfer_out'||kind==='admin_transfer_out';
 if(!incoming&&!outgoing&&!transfer&&!['transfer_refund','transfer_transit','handover_expense'].includes(kind))return [];
 const facts=[];
 const refund=kind==='transfer_refund';
 const held=kind==='transfer_transit'||kind==='handover_expense';
 if(full||!outgoing)facts.push({label:refund?'عادت إلى قاصة':held?'المرسل':'من',value:transfer?.sender||'غير مسجّل'});
 if(full||!incoming)facts.push({label:refund||held?'المستلم المحدد':'إلى',value:transfer?.recipient||'غير مسجّل'});
 if(transfer?.decidedBy)facts.push({label:cashTransferDecisionLabel(kind,transfer.status),value:transfer.decidedBy});
 return facts;
}

export const cashBalanceLabel=row=>row.owner_id===null&&!row.receiptRestricted?'رصيد قيد التسليم بعد الحركة':'رصيد القاصة بعد الحركة';
