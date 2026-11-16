-- Disposable local integration fixture. Never apply to a live database.
\set ON_ERROR_STOP on
begin;
do $$begin if current_database()<>'solar_v410_browser' then raise exception 'Use solar_v410_browser only';end if;end$$;
insert into profiles(id,username,display_name,is_admin,user_type,active,phone,permissions) values
('00000000-0000-0000-0000-000000410101','v410_admin','مدير اختبار 4.1',true,'admin_staff',true,'07700410101','{}'),
('00000000-0000-0000-0000-000000410102','v410_owner','مسؤول مشتريات 4.1',false,'admin_staff',true,'07700410102','{"purchase":true,"sale":true,"stock":true,"salesHistory":true}'),
('00000000-0000-0000-0000-000000410103','v410_seller','بائع المخزن المسموح 4.1',false,'admin_staff',true,'07700410103','{"sale":true,"stock":true}'),
('00000000-0000-0000-0000-000000410104','v410_warehouse','مسؤول المخزن المسموح 4.1',false,'warehouse',true,'07700410104','{}'),
('00000000-0000-0000-0000-000000410105','v410_installer','مهندس اختبار 4.1',true,'installer',true,'07700410105','{}'),
('00000000-0000-0000-0000-000000410106','v410_manager','مسؤول أسعار المخزن 4.1',false,'admin_staff',true,'07700410106','{"wholesalePricingManage":true,"sale":true}'),
('00000000-0000-0000-0000-000000410107','v410_foreign','بائع مخزن آخر 4.1',false,'admin_staff',true,'07700410107','{"sale":true,"stock":true}'),
('00000000-0000-0000-0000-000000410108','v410_inactive','مستخدم موقوف 4.1',false,'admin_staff',false,'07700410108','{"sale":true,"purchase":true}'),
('00000000-0000-0000-0000-000000410109','v410_foreignwarehouse','مسؤول مخزن آخر 4.1',true,'warehouse',true,'07700410109','{}'),
('00000000-0000-0000-0000-000000410110','v410_office','موظف بلا صلاحية مواد 4.1',false,'admin_staff',true,'07700410110','{"cash":true}');
insert into solar_private.warehouses(id,name,code) overriding system value values (410001,'مخزن وصول المواد 4.1','V410-LOCAL'),(410002,'مخزن مستقل 4.1','V410-FOREIGN');
insert into solar_private.warehouse_access(user_id,warehouse_ids) values
('00000000-0000-0000-0000-000000410102',array[410001]::bigint[]),
('00000000-0000-0000-0000-000000410103',array[410001]::bigint[]),
('00000000-0000-0000-0000-000000410104',array[410001]::bigint[]),
('00000000-0000-0000-0000-000000410105',array[410001]::bigint[]),
('00000000-0000-0000-0000-000000410106',array[410001]::bigint[]),
('00000000-0000-0000-0000-000000410107',array[410002]::bigint[]),
('00000000-0000-0000-0000-000000410108',array[410001]::bigint[]),
('00000000-0000-0000-0000-000000410109',array[410002]::bigint[]),
('00000000-0000-0000-0000-000000410110',array[410001]::bigint[]);
insert into brands(id,name) values(-410101,'FULLMAX - براند الإشعارات الطويل 4.1');
insert into products(id,code,name,brand_id,category,qty,cost)
select -410100-n,'V410-'||lpad(n::text,2,'0'),'لوح شمسي احترافي طويل الاسم للاختبار العربي والإنجليزي FULLMAX 600W/IP66/HYBRID - '||n||case when n=1 then ' <img src=x onerror=alert(1)>' else '' end,-410101,'ألواح',2,11000+n
from generate_series(1,12)n;
insert into products(id,code,name,brand_id,category,qty,cost) values
(-410190,'V410-ZERO','مادة نفدت بعد بيعها 4.1',-410101,'بطاريات',1,12000),
(-410191,'V410-EMPTY','مادة غير متوفرة 4.1',-410101,'ألواح',0,13000),
(-410192,'V410-FOREIGN','مادة المخزن الآخر 4.1',-410101,'ألواح',7,14000);
update solar_private.warehouse_stocks set qty=0 where product_id between -410192 and -410101;
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty,reserved_qty)
select 410001,id,case when id=-410192 then 0 else qty end,0 from products where id between -410192 and -410101;
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(410002,-410192,7);
insert into suppliers(id,name,phone,account_currency) values(-410101,'مورد خاص لا يظهر في الإشعار 4.1','07700419999','IQD');
insert into customers(id,name,phone,customer_type,owner_id) values(-410101,'عميل الفاتورة المؤرشفة 4.1','07700418888','wholesale','00000000-0000-0000-0000-000000410102');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410102',true);
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","warehouseId":410001,"partyId":-410101,"party":"عميل الفاتورة المؤرشفة 4.1","notes":"v410-archived-zero-stock","items":[{"id":-410190,"qty":1,"price":20000}]}');
commit;
