export const sections=[
 ['مساحة العمل',[['home','الرئيسية'],['sale','بيع جملة'],['system','بيع منظومات'],['salesHistory','المبيعات السابقة'],['deletionRequests','طلبات حذف الوصولات'],['stock','المخزون'],['purchasesHub','المشتريات'],['purchase','فاتورة شراء'],['tahseel','التحصيل']]],
 ['الحسابات',[['cash','الصندوق'],['profit','التقارير والأرباح'],['paymentHistory','التسديدات السابقة'],['warranty','فحص ضمان فاتورة'],['capital','رأس المال'],['customerPayment','تسديد جملة'],['systemPayment','تسديد منظومات'],['supplierPayment','تسديد مورد'],['customerDebts','مدينون العملاء'],['supplierBalances','أرصدة الموردين'],['customerStatement','كشف حساب عميل'],['supplierStatement','كشف حساب مورد'],['cashTransfers','استلام وتسليم القاصة'],['exchangeRate','سعر الصرف']]],
 ['العمليات',[['installations','التنصيبات'],['warehouse','تجهيز المخزن'],['stockMovement','حركة المواد']]],
 ['الإدارة',[['customers','العملاء'],['customerCreate','إضافة زبون'],['suppliers','الموردون'],['products','تعريف المواد'],['brands','إضافة البراندات'],['operationControl','إيقاف البيع والشراء'],['wholesalePricing','أسعار بيع الجملة'],['users','المستخدمون والصلاحيات'],['userActivity','نشاط المستخدمين'],['updates','تحديثات البرنامج']]]
];

export const sectionGroups=[
 {id:'sales',title:'المبيعات والعملاء',description:'عمليات البيع وإدارة العملاء',icon:'receipt',color:'green',fixedOrder:true,ids:['sale','system','salesHistory','deletionRequests','customerCreate','customerPayment','systemPayment','customerDebts','customerStatement','paymentHistory','customers']},
 {id:'purchases',title:'المشتريات والموردون',description:'المشتريات وحسابات الموردين',icon:'truck',color:'blue',fixedOrder:true,ids:['purchase','purchasesHub','supplierPayment','suppliers','supplierStatement','supplierBalances']},
 {id:'inventory',title:'المخزون والمواد',description:'المواد والمخازن والحركة والتنصيبات',icon:'warehouse',color:'orange',ids:['products','stock','stockMovement','warehouse','installations','brands']},
 {id:'finance',title:'المالية والحسابات',description:'الصندوق والقاصات والتقارير المالية',icon:'coins',color:'violet',ids:['cash','capital','cashTransfers','profit','exchangeRate']},
 {id:'reports',title:'التقارير والإدارة',description:'التحصيل والضمان',icon:'chart',color:'rose',ids:['tahseel','warranty']},
 {id:'settings',title:'الإعدادات والنظام',description:'المستخدمون والتحديثات',icon:'settings',color:'slate',ids:['users','userActivity','operationControl','wholesalePricing','updates']}
];
