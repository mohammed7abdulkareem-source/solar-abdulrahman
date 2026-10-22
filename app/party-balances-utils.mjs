import {phoneContactDocument} from './phone-contact-utils.mjs';
import {normalizeSearch} from './party-search-utils.mjs';
import {escapeHtml,money} from './supplier-utils.mjs';
import {customerNameKey,customerPhoneKey} from './customer-utils.mjs';

export const baghdadToday=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Baghdad',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export const balanceDate=value=>value?new Date(value).toLocaleDateString('en-GB',{timeZone:'Asia/Baghdad'}):'—';
export const partyType=value=>value==='wholesale'?'جملة':'منظومات';
export const ownerKey=value=>value==null||value===''?'unassigned':String(value);
export function matchesAccount(row,query=''){
 const words=normalizeSearch(query).split(/\s+/).filter(Boolean),text=normalizeSearch([row.name,row.phone].join(' ')),phone=customerPhoneKey(query),name=customerNameKey(query);
 return !words.length||words.every(w=>text.includes(w))||(phone&&customerPhoneKey(row.phone)===phone)||(name&&customerNameKey(row.name).includes(name));
}
export const filterAccountCustomers=(rows,query='')=>rows.filter(r=>matchesAccount(r,query));
export function filterBalances(rows,{query='',wholesale=true,systems=true,dueOnly=true,mode='customers',ownerId='all'}={}){
 return rows.filter(r=>(mode!=='customers'||((r.customer_type==='wholesale'?wholesale:systems)&&(ownerId==='all'||ownerKey(r.owner_id)===ownerId)))&&(!dueOnly||Number(r.balance)>0)&&matchesAccount(r,query))
  .sort((a,b)=>Number(b.balance)-Number(a.balance)||a.name.localeCompare(b.name,'ar'));
}
export function filterUnresolved(rows,options={}){
 const {mode='customers',query='',ownerId='all',wholesale=true,systems=true}=options;
 return rows.filter(r=>(mode!=='customers'||((r.customer_type==='wholesale'?wholesale:systems)&&(ownerId==='all'||ownerKey(r.owner_id)===ownerId)))&&matchesAccount(r,query));
}
export function groupBalances(rows){
 const groups=new Map();for(const row of rows){const key=ownerKey(row.owner_id);if(!groups.has(key))groups.set(key,{id:key,name:row.owner_name||'غير مخصص',rows:[]});groups.get(key).rows.push(row);}
 return [...groups.values()].map(g=>({...g,total:balancesTotal(g.rows)})).sort((a,b)=>b.total-a.total||a.name.localeCompare(b.name,'ar'));
}
export const legacyReason=row=>row.reason==='deleted_opening'?'افتتاحي لزبون غير موجود':row.reason==='ambiguous_name'?'اسم قديم يطابق أكثر من حساب':'حركة غير مرتبطة بحساب مسجّل';
export const balancesTotal=rows=>Math.round(rows.reduce((s,r)=>s+Number(r.balance),0)*100)/100;
export function balancesDocument(rows,{mode='customers',asOf,scope,wholesale=true,systems=true,dueOnly=true,showPhone=false,showType=false,query='',ownerName='',groupByOwner=true,unresolved=[]}={}){
 const customer=mode==='customers',e=escapeHtml;
 const filter=customer?[wholesale&&'جملة',systems&&'منظومات'].filter(Boolean).join(' + ')||'بدون تصنيف':dueOnly?'المبالغ المستحقة للموردين':'جميع الأرصدة';
 const heads=['#',customer?'اسم العميل':'اسم المورد',...(showPhone?['الهاتف']:[]),...(customer&&showType?['النوع']:[]),customer?'الرصيد المدين د.ع':'الرصيد للمورد د.ع','آخر تسديد د.ع','تاريخ آخر تسديد'];
 let index=0;
 const renderRow=r=>'<tr>'+[++index,e(r.name),...(showPhone?[phoneContactDocument(r.phone)]:[]),...(customer&&showType?[partyType(r.customer_type)]:[]),money(r.balance),r.last_payment==null?'—':money(r.last_payment),balanceDate(r.last_payment_at)].map(x=>'<td>'+x+'</td>').join('')+'</tr>';
 const body=customer&&groupByOwner?groupBalances(rows).map(g=>'<tr class="printOwner"><td colspan="'+heads.length+'">'+e(g.name)+' · '+g.rows.length+' عميل · '+money(g.total)+' د.ع</td></tr>'+g.rows.map(renderRow).join('')).join(''):rows.map(renderRow).join('');
 const appendix=unresolved.length?'<div class="balanceCaption"><b>ملحق الحركات القديمة للمراجعة</b><br>هذه الحركات محفوظة وغير مضافة إلى مجموع أرصدة الحسابات المسجلة أعلاه.</div><table class="balancePrint balanceLegacyPrint"><thead><tr><th>الاسم المسجل</th><th>مسؤول الحركة</th><th>التاريخ</th><th>الأثر د.ع</th><th>التوضيح</th></tr></thead><tbody>'+unresolved.map(r=>'<tr><td>'+e(r.name||'بدون اسم')+'</td><td>'+e(r.owner_name||'غير مخصص')+'</td><td>'+balanceDate(r.date)+'</td><td>'+money(r.effect)+'</td><td>'+e(legacyReason(r))+'</td></tr>').join('')+'</tbody></table>':'';
 return '<style>.balancePrint{font-size:11px}.balancePrint th,.balancePrint td{padding:7px 4px;font-size:11px}.balancePrint th:first-child{width:5%}.balancePrint td:nth-last-child(3),.balancePrint td:nth-last-child(2){direction:ltr;unicode-bidi:embed}.balanceLegacyPrint th:first-child{width:25%!important}.balanceLegacyPrint th:nth-child(2){width:20%}.balanceLegacyPrint th:nth-child(3),.balanceLegacyPrint th:nth-child(4){width:15%}.balancePrint thead{display:table-header-group}.balancePrint tr{break-inside:avoid}.balancePrint .printOwner td{background:#e7efff!important;color:#243c6d!important;text-align:right;font-weight:bold}.balanceCaption{line-height:1.8;margin:12px 0;color:#34445e}</style><div class="balanceCaption">الرصيد لغاية: '+e(asOf)+' • '+e(filter)+'<br>'+e(ownerName||scope)+(query?'<br>البحث: '+e(query):'')+' • العدد: '+rows.length+'</div><table class="balancePrint" data-pdf-paginate="true"><thead><tr>'+heads.map(h=>'<th>'+h+'</th>').join('')+'</tr></thead><tbody>'+body+'</tbody></table><p class="balanceCaption">مجموع أرصدة الحسابات المسجلة: <b>'+money(balancesTotal(rows))+' د.ع</b></p>'+appendix+(customer?'':'<p class="balanceCaption">الرصيد الموجب مستحق للمورد، والسالب دفعة مقدمة لنا عنده.</p>');
}
