import {normalizeSearch} from './party-search-utils.mjs';
import {escapeHtml,money} from './supplier-utils.mjs';

export const baghdadToday=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export const balanceDate=value=>value?new Date(value).toLocaleDateString('en-GB',{timeZone:'Asia/Baghdad'}):'—';
export const partyType=value=>value==='wholesale'?'جملة':'منظومات';
export function filterBalances(rows,{query='',wholesale=true,systems=true,dueOnly=true,mode='customers'}={}){
 const q=normalizeSearch(query);
 return rows.filter(r=>(mode!=='customers'||(r.customer_type==='wholesale'?wholesale:systems))&&(!dueOnly||Number(r.balance)>0)&&(!q||normalizeSearch([r.name,r.phone].join(' ')).includes(q)))
  .sort((a,b)=>Number(b.balance)-Number(a.balance)||a.name.localeCompare(b.name,'ar'));
}
export const balancesTotal=rows=>Math.round(rows.reduce((s,r)=>s+Number(r.balance),0)*100)/100;
export function balancesDocument(rows,{mode='customers',asOf,scope,wholesale=true,systems=true,dueOnly=true,showPhone=false,showType=false,query=''}={}){
 const customer=mode==='customers',e=escapeHtml;
 const filter=customer?[wholesale&&'جملة',systems&&'منظومات'].filter(Boolean).join(' + ')||'بدون تصنيف':dueOnly?'المبالغ المستحقة للموردين':'جميع الأرصدة';
 const heads=['#',customer?'اسم العميل':'اسم المورد',...(showPhone?['الهاتف']:[]),...(customer&&showType?['النوع']:[]),customer?'الرصيد المدين د.ع':'الرصيد للمورد د.ع','آخر تسديد د.ع','تاريخ آخر تسديد'];
 const body=rows.map((r,i)=>'<tr>'+[i+1,e(r.name),...(showPhone?[e(r.phone||'—')]:[]),...(customer&&showType?[partyType(r.customer_type)]:[]),money(r.balance),r.last_payment==null?'—':money(r.last_payment),balanceDate(r.last_payment_at)].map(x=>'<td>'+x+'</td>').join('')+'</tr>').join('');
 return '<style>.balancePrint{font-size:11px}.balancePrint th,.balancePrint td{padding:7px 4px;font-size:11px}.balancePrint th:first-child{width:5%}.balancePrint thead{display:table-header-group}.balancePrint tr{break-inside:avoid}.balanceCaption{line-height:1.8;margin:8px 0;color:#506878}</style><div class="balanceCaption">الرصيد لغاية: '+e(asOf)+' • '+e(filter)+'<br>'+e(scope)+(query?'<br>البحث: '+e(query):'')+' • العدد: '+rows.length+'</div><table class="balancePrint" data-pdf-paginate="true"><thead><tr>'+heads.map(h=>'<th>'+h+'</th>').join('')+'</tr></thead><tbody>'+body+'</tbody></table>'+(customer?'':'<p class="balanceCaption">الرصيد الموجب مستحق للمورد، والسالب دفعة مقدمة لنا عنده.</p>');
}
