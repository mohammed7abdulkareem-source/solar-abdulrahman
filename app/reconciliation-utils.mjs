import {escapeHtml,warehouseDate} from './warehouse-utils.mjs';
export const accountLabel=t=>({opening_balance:'رصيد افتتاحي',account_reconciliation:'مطابقة حساب',charge_extra_expense:'مصروف إضافي',charge_old_balance:'حساب قديم',charge_other:'إضافة أخرى'}[t.mode]||(['customer_payment','system_payment'].includes(t.kind)?(Number(t.total)<0?'إضافة على الحساب':'تسديد'):t.kind==='system'?'بيع منظومة':t.cash?'فاتورة بيع نقدية':'فاتورة بيع'));
export const accountEffect=t=>t.effect!==undefined?Number(t.effect):['customer_payment','system_payment'].includes(t.kind)?-Number(t.total||0):t.kind==='sale'&&t.cash?0:Number(t.total||0);
export const money=n=>Number(n||0).toLocaleString('en-US',{maximumFractionDigits:2});
const baghdadDay=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'});
export function statementPeriod(rows,from='',to='',view='all'){
 let balance=0,opening=0;const period=[];
 for(const t of [...rows].sort((a,b)=>new Date(a.date)-new Date(b.date)||Number(a.id)-Number(b.id))){
  const day=baghdadDay.format(new Date(t.date));
  if(to&&day>to)continue;
  balance+=accountEffect(t);
  if(from&&day<from){opening=balance;continue;}
  period.push({...t,balance});
 }
 return {opening,balance,rows:period.filter(t=>view==='all'||(view==='invoices'?['sale','system'].includes(t.kind):!['sale','system'].includes(t.kind)))};
}
export function customerStatementBody(name,period,from,to){
 return '<div class="meta"><div>العميل: '+escapeHtml(name)+'</div><div>الفترة: '+escapeHtml(from||'البداية')+' — '+escapeHtml(to||'اليوم')+'</div></div><table><thead><tr><th>ت</th><th>التاريخ</th><th>البيان</th><th>الحركة د.ع</th><th>الرصيد د.ع</th><th>الملاحظات</th></tr></thead><tbody>'+(from?'<tr><td>—</td><td>'+escapeHtml(from)+'</td><td>رصيد أول المدة</td><td>—</td><td>'+money(period.opening)+'</td><td>من الحركات السابقة</td></tr>':'')+period.rows.map((t,i)=>'<tr><td>'+(i+1)+'</td><td>'+escapeHtml(warehouseDate(t.date))+'</td><td>'+escapeHtml(accountLabel(t))+' #'+escapeHtml(t.receiptNo||t.id)+'</td><td>'+money(accountEffect(t))+'</td><td>'+money(t.balance)+'</td><td>'+escapeHtml(t.notes||'')+'</td></tr>').join('')+'</tbody></table><p>الرصيد الموجب: لنا على العميل • الرصيد السالب: للعميل عندنا</p>';
}
