import {canOpenPage} from './access-utils.mjs';
import {cashPermissionOptions} from './cash-permissions.mjs';
import {ownUserPermissions} from './user-scope.mjs';

export const roleLabels={user:'إداري بصلاحيات محددة',warehouse:'مسؤول مخزن',installer:'مهندس تنصيب',admin:'مدير البرنامج'};
export function accountRole(user){
 if(user?.user_type==='warehouse'||user?.user_type==='installer')return user.user_type;
 return user?.is_admin?'admin':'user';
}
export const permissionGroups=[
 {title:'المبيعات والعملاء',icon:'receipt',options:[
  ['sale','بيع جملة'],['system','بيع منظومات'],['salesHistory','المبيعات السابقة الخاصة به'],['deletionRequests','طلبات حذف الوصولات الخاصة به'],
  ['customerCreate','إضافة زبون جملة أو مفرد · لزبائنه فقط'],['customers','إدارة زبائنه · إضافة وتعديل وحذف'],
  ['customerPayment','تسديد جملة'],['systemPayment','تسديد منظومات'],['customerDebts','مدينون العملاء'],['customerStatement','كشف حساب عميل'],['customerReconcile','مطابقة حساب العميل'],
  ['wholesalePricingManage','إدارة أسعار بيع الجملة وتشغيلها'],['wholesaleFreePricing','بيع الجملة بأي سعر ضمن نطاق الأسعار المسموح']]},
 {title:'المشتريات والموردون',icon:'truck',options:[
  ['purchase','فاتورة شراء'],['suppliers','إضافة الموردين'],['supplierPayment','تسديد مورد'],['supplierStatement','كشف حساب مورد'],['supplierBalances','أرصدة الموردين']]},
 {title:'المخزون والتجهيز',icon:'warehouse',options:[
  ['stock','المخزون'],['warehouse','تجهيز فواتيره فقط'],['stockMovement','حركات وصولاته بدون أسعار'],['stockAdjust','تسوية رصيد المخزون'],
  ['products','تعريف المواد'],['brands','إضافة البراندات'],['installations','غلق منظوماته فقط']]},
 {title:'التحصيل والضمان',icon:'sun',options:[
  ['tahseel','التحصيل بمصاريف العرض وربح ثابت ١٥٪'],['tahseelFull','التحصيل الكامل وتعديل نسبة الربح'],['tahseelDefaults','حفظ مصاريف التحصيل العامة'],['warranty','فحص ضمان فاتورة']]},
 {title:'الصندوق والأرباح',icon:'wallet',options:[
  ['cash','مشاهدة قاصته'],...cashPermissionOptions,['profit','مشاهدة أرباحه فقط حسب الفترة'],['profitSettlement','طلب تسوية وصرف أرباحه'],['capital','رأس المال']]},
 {title:'سعر الصرف والتخصيص',icon:'settings',options:[
  ['exchangeRate','مشاهدة سعر الصرف'],['exchangeRateEdit','تعديل سعر الصرف'],['layoutCustomize','تخصيص ترتيب وحجم أقسامه']]}
];
export const warehouseDirections=[['fromPrimary','من المخزن الرئيسي إلى المخازن الأخرى'],['toPrimary','من المخازن الأخرى إلى المخزن الرئيسي'],['other','بين المخازن الأخرى']];
export const fieldRoleActions={installer:['التنصيبات المسندة إليه'],warehouse:['تجهيز الفواتير','أرصدة المخازن المخصصة له','حركة المواد ضمن مخازنه'],admin:['جميع أقسام البرنامج','إدارة المستخدمين والصلاحيات']};
const keys=permissionGroups.flatMap(group=>group.options.map(([key])=>key));
const cashKeys=cashPermissionOptions.map(([key])=>key);
export function accountPermissions(values={}){
 const next=ownUserPermissions(values||{});
 const profile={active:true,user_type:'admin_staff',permissions:next};
 // Capture the effective legacy grants before any related checkbox changes.
 for(const key of ['tahseel','salesHistory','warranty','exchangeRate']){
  next[key]=canOpenPage(profile,key);
 }
 for(const key of keys)if(!Object.hasOwn(next,key))next[key]=false;
 return next;
}
export function resetAccountPermissions(values={}){
 const next={...values};
 // Unrecognized metadata survives an edit. An explicit reset also turns off
 // legacy boolean grants while retaining the mandatory own-account isolation.
 for(const key of Object.keys(next))if(typeof next[key]==='boolean')next[key]=false;
 for(const key of keys)next[key]=false;
 return ownUserPermissions(next);
}
export function changeAccountPermission(values,key,enabled){
 const next={...values,[key]:enabled};
 if(enabled){
  if(cashKeys.includes(key))next.cash=true;
  if(key==='exchangeRateEdit')next.exchangeRate=true;
  if(key==='profitSettlement')next.profit=true;
  if(key==='stockAdjust'){next.stock=true;next.stockMovement=true;}
  if(key==='customerReconcile')next.customerStatement=true;
  if(key==='tahseelFull'||key==='tahseelDefaults')next.tahseel=true;
  if(key==='tahseelDefaults')next.tahseelFull=true;
 }else{
  if(key==='cash'){for(const cashKey of cashKeys)next[cashKey]=false;next.cashAdminTools=false;}
  if(key==='exchangeRate')next.exchangeRateEdit=false;
  if(key==='profit')next.profitSettlement=false;
  if(key==='stock'||key==='stockMovement')next.stockAdjust=false;
  if(key==='customerStatement')next.customerReconcile=false;
  if(key==='tahseel'){next.tahseelFull=false;next.tahseelDefaults=false;}
  if(key==='tahseelFull')next.tahseelDefaults=false;
 }
 return next;
}
export function selectedPermissionLabels(role,perms){
 if(role!=='user')return [...fieldRoleActions[role],...(['installer','warehouse'].includes(role)&&perms.layoutCustomize?['تخصيص ترتيب وحجم أقسامه']:[])];
 return permissionGroups.flatMap(group=>group.options.filter(([key])=>perms[key]===true).map(([,label])=>label));
}
