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
export function customerStatementBody(name,period,from,to,{view='all',phone='',ownerName=''}={}){
 const e=escapeHtml,viewLabel={all:'الكشف الكامل',invoices:'المبيعات',payments:'التسديدات والحركات'}[view]||'الكشف الكامل';
 return '<style>.statementPrint{font-size:11px;table-layout:fixed}.statementPrint th,.statementPrint td{padding:8px 5px;font-size:11px;line-height:1.8}.statementPrint th:first-child{width:5%}.statementPrint th:nth-child(2){width:14%}.statementPrint th:nth-child(3){width:21%}.statementPrint th:nth-child(4),.statementPrint th:nth-child(5){width:16%}.statementPrint td:last-child{font-size:10px;overflow-wrap:anywhere}.statementPrint td:nth-child(4),.statementPrint td:nth-child(5){direction:ltr;unicode-bidi:embed}.statementPrint tr{break-inside:avoid}.statementCaption{font-size:11px;line-height:1.9;margin:12px 0;color:#34445e}</style><div class="meta"><div><b>العميل: '+e(name)+'</b><br>الهاتف: '+e(phone||'غير مسجل')+'<br>المستخدم المسؤول: '+e(ownerName||'غير مخصص')+'</div><div>الفترة: '+e(from||'بداية التعامل')+' — '+e(to||'اليوم')+'<br>العرض: '+e(viewLabel)+'<br>عدد الحركات المعروضة: '+period.rows.length+'</div></div><table class="statementPrint" data-pdf-paginate="true"><thead><tr><th>ت</th><th>التاريخ</th><th>البيان</th><th>الحركة د.ع</th><th>الرصيد د.ع</th><th>الملاحظات</th></tr></thead><tbody>'+(from?'<tr><td>—</td><td>'+e(from)+'</td><td>رصيد أول المدة</td><td>—</td><td>'+money(period.opening)+'</td><td>من الحركات السابقة</td></tr>':'')+period.rows.map((t,i)=>'<tr><td>'+(i+1)+'</td><td>'+e(warehouseDate(t.date))+'</td><td>'+e(accountLabel(t))+(t.receiptNo?' #'+e(t.receiptNo):'')+'</td><td>'+money(accountEffect(t))+'</td><td>'+money(t.balance)+'</td><td>'+e(t.notes||'')+'</td></tr>').join('')+'</tbody></table><p class="statementCaption">الرصيد الموجب: لنا على العميل • الرصيد السالب: للعميل عندنا. الأرصدة الافتتاحية والمطابقات لا تعد قبضًا نقديًا.'+(view!=='all'?' الرصيد الجاري يشمل كامل الحركات، بما فيها الحركات المخفية في هذا التبويب.':'')+'</p>';
}
