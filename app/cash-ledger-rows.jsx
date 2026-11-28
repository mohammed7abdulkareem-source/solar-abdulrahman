import AppIcon from './app-icons';
import {cashIcon,cashTone} from './cash-finance-utils.mjs';
import {cashDate,resetTitle} from './cash-movement-utils.mjs';
import {cashKind} from './cash-utils.mjs';
import {currencyUnit,formatMoney} from './money-format.mjs';
import {cashBalanceLabel,cashRowBalance,cashTransferFacts} from './cash-ledger-display.mjs';

export function CashFigure({value,currency,signed=false}){
 if(value==null||String(value).trim()===''||!Number.isFinite(Number(value)))return <span className="cfUnknownAmount">غير متوفر</span>;
 const amount=Number(value);
 const prefix=amount<0?'−':signed&&amount>0?'+':'';
 return <span className="cfFigure"><bdi dir="ltr">{prefix}{formatMoney(Math.abs(amount),currency)}</bdi> <span className="cfCurrencyUnit">{currencyUnit(currency)}</span></span>;
}

const direction=delta=>delta>0?'داخل':delta<0?'خارج':'دون حركة نقدية';
export const cashMovementTitle=row=>row.receiptRestricted?'أثر حسابي':row.reconciliation?.mode==='zero'?resetTitle(row):cashKind(row.kind);

export function MovementParties({row}){
 if(row.receiptRestricted)return null;
 const facts=cashTransferFacts(row.kind,row.transfer);
 if(facts.length)return <span className="cfRowParties">{facts.map(({label,value})=><span key={label}><span>{label}</span>{' '}<strong>{value}</strong></span>)}</span>;
 if(row.party)return <span className="cfRowParty"><span>{['purchase','supplier_payment','supplier_payment_refund'].includes(row.kind)?'المورد': ['sale','system','customer_payment','system_payment'].includes(row.kind)?'الزبون':'الجهة'}</span>{' '}<strong>{row.party}</strong></span>;
 if(row.note)return <span className="cfRowNote">{row.note}</span>;
 return null;
}

function MovementStamp({row}){
 return <span className="cfMovementStamp"><time dateTime={row.created_at}><bdi dir="ltr">{cashDate(row.created_at)}</bdi></time>{row.receipt_no!=null&&<span>وصل <bdi dir="ltr">#{row.receipt_no}</bdi></span>}</span>;
}

function CashMovementAmount({row}){
 return <span className={'cfMovementMoney '+cashTone(row)}><span>{direction(row.delta)}</span><strong><CashFigure value={row.delta} currency={row.currency} signed/></strong></span>;
}

function MobileMovement({row,owner,onMovement}){
 const tone=cashTone(row);
 return <button type="button" className={'cfMovement '+tone} disabled={row.receiptRestricted} onClick={()=>onMovement(row.id)}>
  <span className="cfRowTop">
   <span className="cfRowIdentity"><span className="cfMovementIcon"><AppIcon name={row.receiptRestricted?'document':cashIcon(row.kind)} size={18}/></span><strong>{cashMovementTitle(row)}</strong></span>
   <CashMovementAmount row={row}/>
  </span>
  <MovementParties row={row}/>
  <span className="cfRowMeta">{!owner&&<span>{row.owner_id===null&&!row.receiptRestricted?'قيد التسليم':'القاصة · '+row.ownerName}</span>}<MovementStamp row={row}/></span>
  <span className="cfRowAfter"><span>{cashBalanceLabel(row)}</span><strong><CashFigure value={cashRowBalance(row,owner)} currency={row.currency}/></strong></span>
 </button>;
}

export default function CashLedgerRows({rows,owner,onMovement}){
 return <>
  <div className="cfMovementCards">{rows.map(row=><MobileMovement key={row.id} row={row} owner={owner} onMovement={onMovement}/>)}</div>
  <div className="cfDesktopLedger"><table className="cashTable"><thead><tr><th>الحركة وأطرافها</th><th>القاصة</th><th>التاريخ والوصل</th><th>مبلغ الحركة</th><th>الرصيد بعد الحركة</th><th aria-label="تفاصيل"/></tr></thead><tbody>{rows.map(row=>
   <tr key={row.id}>
    <td><b>{cashMovementTitle(row)}</b><MovementParties row={row}/></td><td>{row.owner_id===null&&!row.receiptRestricted?'قيد التسليم':row.ownerName}</td><td><MovementStamp row={row}/></td>
    <td><CashMovementAmount row={row}/></td><td className="cfTableAfter"><CashFigure value={cashRowBalance(row,owner)} currency={row.currency}/></td>
    <td>{!row.receiptRestricted&&<button type="button" onClick={()=>onMovement(row.id)}>تفاصيل الحركة</button>}</td>
   </tr>)}</tbody></table></div>
 </>;
}
