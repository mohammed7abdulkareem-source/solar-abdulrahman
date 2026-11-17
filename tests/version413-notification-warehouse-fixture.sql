-- Synthetic local fixture only; apply before the V4.1.3 notification migration.
\set ON_ERROR_STOP on
begin;
do $$begin
 if current_database()<>'solar_v413_browser' then raise exception 'Use solar_v413_browser only';end if;
 if exists(select 1 from profiles where id='00000000-0000-0000-0000-000000413101') then raise exception 'Fixture already exists';end if;
end$$;
insert into profiles(id,username,display_name,is_admin,user_type,active,phone,permissions) values
('00000000-0000-0000-0000-000000413101','v413_admin','مدير اختبار وصول المواد',true,'admin_staff',true,'07700413101','{}'),
('00000000-0000-0000-0000-000000413102','v413_buyer','مسؤول شراء اختبار المخزن',false,'admin_staff',true,'07700413102','{"purchase":true,"stock":true}'),
('00000000-0000-0000-0000-000000413103','v413_seller','بائع المخزن المستقبل',false,'admin_staff',true,'07700413103','{"sale":true,"stock":true}'),
('00000000-0000-0000-0000-000000413104','v413_warehouse','مسؤول المخزن المستقبل',false,'warehouse',true,'07700413104','{}'),
('00000000-0000-0000-0000-000000413105','v413_foreign','بائع مخزن مستقل',false,'admin_staff',true,'07700413105','{"sale":true,"stock":true}'),
('00000000-0000-0000-0000-000000413106','v413_installer','مهندس بلا وصول مالي',true,'installer',true,'07700413106','{}'),
('00000000-0000-0000-0000-000000413107','v413_inactive','حساب موقوف',false,'admin_staff',false,'07700413107','{"sale":true,"stock":true}');
insert into solar_private.warehouses(id,name,code) overriding system value values
(413001,'المخزن الرئيسي لاستلام الألواح والبطاريات والانفيرترات في فرع الشركة الجديد — V413','V413-RECEIVING'),
(413002,'مخزن منفصل لا يستلم هذه المواد V413','V413-OTHER');
insert into solar_private.warehouse_access(user_id,warehouse_ids)
select id,case when id='00000000-0000-0000-0000-000000413105' then array[413002]::bigint[] else array[413001]::bigint[] end
from profiles where id::text between '00000000-0000-0000-0000-000000413102' and '00000000-0000-0000-0000-000000413107';
insert into brands(id,name) values(-413101,'FULLMAX براند المواد الطويل V413');
insert into products(id,code,name,brand_id,category,qty,cost) values
(-413101,'PRIVATE-CODE-V413-PANEL','لوح شمسي طويل الاسم للاختبار 600W/IP66 FULLMAX <img src=x onerror=alert(1)>',-413101,'ألواح',0,810101),
(-413102,'PRIVATE-CODE-V413-BATTERY','بطارية منظومة الطاقة الشمسية 25KW طويلة الاسم لاختبار العرض',-413101,'بطارية',0,810102),
(-413103,'PRIVATE-CODE-V413-INVERTER','انفيرتر منظومة الطاقة الشمسية 16KW/3PHASE طويل الاسم',-413101,'انفيرتر',0,810103);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty,reserved_qty)
select 413001,id,0,0 from products where id between -413103 and -413101;
insert into suppliers(id,name,phone,account_currency) values
(-413101,'PRIVATE-SUPPLIER-V413 لا يظهر في إشعار المواد','07700413999','IQD');
commit;
