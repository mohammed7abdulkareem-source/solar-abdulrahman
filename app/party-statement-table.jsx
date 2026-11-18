import AppIcon from './app-icons';
import {formatMoney, currencyUnit} from './money-format.mjs';
import {balanceDate} from './party-balances-utils.mjs';
import './customer-statement-table.css';

const columns = ['التاريخ', 'البيان', 'مبلغ الوصل', 'زيادة الحساب', 'تسديد / تخفيض', 'الرصيد بعد الحركة'];

function AmountCell({label, amount, currency, hiddenOnMobile, className}) {
 return <td role="cell" className={className} data-inactive={hiddenOnMobile || undefined}>
  <span className="statementMobileLabel" aria-hidden="true">{label}</span>
  <bdi>{formatMoney(amount, currency)}</bdi>
 </td>;
}

export default function PartyStatementTable({period, currency, onOpen, customer}) {
 return <div className={'miniTableWrap' + (customer ? ' customerStatementLedger' : '')}>
  <table className="miniStatementTable" role="table" aria-label={'حركات كشف الحساب · ' + currencyUnit(currency)}>
   <thead role="rowgroup"><tr role="row">
    {columns.map(label => <th key={label} role="columnheader" scope="col">{label}</th>)}
   </tr></thead>
   <tbody role="rowgroup">{period.rows.map(row => <tr role="row" key={row.id}>
    <td role="cell" className="statementDate"><time dateTime={row.date}>{balanceDate(row.date)}</time></td>
    <td role="cell" className="statementDescription">
     <button type="button" className="miniStatementOpen" disabled={row.receiptRestricted}
      aria-label={row.receiptRestricted ? row.label : 'فتح ' + row.label + (row.receiptNo ? ' #' + row.receiptNo : '')}
      onClick={() => onOpen(row)}>
      <span>{row.label}{row.receiptNo ? ' #' + row.receiptNo : ''}</span>
      {!row.receiptRestricted && <small>فتح الوصل <AppIcon name="chevron" size={13}/></small>}
     </button>
     {row.notes && <small className="partyStatementNote">{row.notes}</small>}
    </td>
    <AmountCell label={row.receiptRestricted ? 'مبلغ الحركة' : columns[2]} amount={row.amount} currency={currency}/>
    <AmountCell label={row.effect === 0 ? 'أثر الحركة' : columns[3]} amount={Math.max(0,row.effect)} currency={currency} hiddenOnMobile={row.effect < 0}/>
    <AmountCell label={columns[4]} amount={Math.max(0,-row.effect)} currency={currency} hiddenOnMobile={row.effect >= 0}/>
    <AmountCell label={columns[5]} className="statementRunningBalance" amount={row.balance} currency={currency}/>
   </tr>)}</tbody>
   <tfoot role="rowgroup"><tr role="row"><td role="cell" colSpan="5">رصيد نهاية الفترة · {currencyUnit(currency)}</td><td role="cell"><bdi>{formatMoney(period.balance,currency)}</bdi></td></tr></tfoot>
  </table>
  {!period.rows.length && <p className="miniEmpty">لا توجد حركات.</p>}
 </div>;
}
