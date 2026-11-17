-- Synthetic read-isolation fixture. No production endpoint is involved.
\set ON_ERROR_STOP on
begin;
do $$begin if current_database()<>'solar_seller_scope_browser' then raise exception 'Use isolated seller scope browser DB only';end if;end$$;
insert into profiles(id,username,display_name,is_admin,user_type,active,phone,permissions)values
('00000000-0000-0000-0000-000000412101','v412_admin','مدير اختبار V412',true,'admin_staff',true,'07700412101','{}'),
('00000000-0000-0000-0000-000000412102','v412_sufyan','سفيان اختبار V412',false,'admin_staff',true,'07700412102','{"sale":true,"system":true,"salesHistory":true,"customers":true,"customerStatement":true,"cash":true,"profit":true,"stock":true,"warehouse":true}'),
('00000000-0000-0000-0000-000000412103','v412_abdul','عبدالرحمن اختبار V412',false,'admin_staff',true,'07700412103','{"sale":true,"system":true,"salesHistory":true,"customers":true,"customerStatement":true,"cash":true,"profit":true,"stock":true,"warehouse":true}'),
('00000000-0000-0000-0000-000000412104','v412_warehouse','مخزن اختبار V412',false,'warehouse',true,'07700412104','{}'),
('00000000-0000-0000-0000-000000412105','v412_installer','مهندس اختبار V412',true,'installer',true,'07700412105','{"salesHistory":true}'),
('00000000-0000-0000-0000-000000412106','v412_inactive','موقوف اختبار V412',false,'admin_staff',false,'07700412106','{"salesHistory":true,"customerStatement":true}');
insert into solar_private.warehouse_access(user_id,warehouse_ids)select id,array[410001]::bigint[]from profiles where username like 'v412_%';
insert into customers(id,name,phone,customer_type,owner_id)values
(-412101,'عميل مشترك V412_SCOPE','07700412901','wholesale','00000000-0000-0000-0000-000000412102'),
(-412102,'عميل عبدالرحمن V412_SCOPE','07700412902','wholesale','00000000-0000-0000-0000-000000412103'),
(-412103,'عميل منظومة سفيان V412_SCOPE','07700412903','system','00000000-0000-0000-0000-000000412102'),
(-412104,'عميل منظومة عبدالرحمن V412_SCOPE','07700412904','system','00000000-0000-0000-0000-000000412103');
insert into products(id,code,name,category,qty,cost)values
(-412101,'OWN-PRODUCT-V412','مادة سفيان الخاصة V412','انفيرتر',100,1000),
(-412102,'FOREIGN-PRODUCT-V412','مادة عبدالرحمن الخاصة V412','بطارية',100,2000);
update solar_private.warehouse_stocks set qty=0 where product_id in(-412101,-412102);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)values(410001,-412101,100),(410001,-412102,100);
insert into transactions(id,receipt_no,kind,party_id,party_name,total,subtotal,cost,profit,cash,payment_mode,created_by,cashbox_user_id,warehouse_id,notes,created_at,installation_status)values
(-412101,412101,'sale',-412101,'عميل مشترك V412_SCOPE',111111,111111,1000,110111,false,'credit','00000000-0000-0000-0000-000000412102','00000000-0000-0000-0000-000000412102',410001,'PRIVATE_OWNER_V412','2026-11-17T08:00:00Z','none'),
(-412102,412102,'sale',-412101,'عميل مشترك V412_SCOPE',9876543,9876543,4000,9872543,false,'credit','00000000-0000-0000-0000-000000412103','00000000-0000-0000-0000-000000412103',410001,'PRIVATE_FOREIGN_V412_SHARED','2026-11-17T08:01:00Z','none'),
(-412103,412103,'sale',-412102,'عميل عبدالرحمن V412_SCOPE',8765432,8765432,6000,8759432,false,'credit','00000000-0000-0000-0000-000000412103','00000000-0000-0000-0000-000000412103',410001,'PRIVATE_FOREIGN_V412_OTHER','2026-11-17T08:02:00Z','none'),
(-412104,412104,'sale',-412101,'عميل مشترك V412_SCOPE',7654321,7654321,8000,7646321,false,'credit','00000000-0000-0000-0000-000000412103','00000000-0000-0000-0000-000000412102',410001,'PRIVATE_FOREIGN_V412_CASHBOX','2026-11-17T08:03:00Z','none'),
(-412105,412105,'system',-412103,'عميل منظومة سفيان V412_SCOPE',222222,222222,2000,220222,false,'credit','00000000-0000-0000-0000-000000412102','00000000-0000-0000-0000-000000412102',410001,'PRIVATE_OWNER_SYSTEM_V412','2026-11-17T08:04:00Z','pending'),
(-412106,412106,'system',-412104,'عميل منظومة عبدالرحمن V412_SCOPE',6543210,6543210,10000,6533210,false,'credit','00000000-0000-0000-0000-000000412103','00000000-0000-0000-0000-000000412103',410001,'PRIVATE_FOREIGN_V412_SYSTEM','2026-11-17T08:05:00Z','pending'),
(-412107,412107,'customer_payment',-412101,'عميل مشترك V412_SCOPE',10000,0,0,0,true,'payment','00000000-0000-0000-0000-000000412102','00000000-0000-0000-0000-000000412102',null,'PRIVATE_OWNER_PAYMENT_V412','2026-11-17T08:06:00Z','none'),
(-412108,412108,'customer_payment',-412101,'عميل مشترك V412_SCOPE',777777,0,0,0,true,'payment','00000000-0000-0000-0000-000000412103','00000000-0000-0000-0000-000000412103',null,'PRIVATE_FOREIGN_V412_PAYMENT','2026-11-17T08:07:00Z','none');
insert into transaction_items(id,transaction_id,product_id,product_name,qty,price,cost,category)values
(-412101,-412101,-412101,'مادة سفيان الخاصة V412',1,111111,1000,'انفيرتر'),
(-412102,-412102,-412102,'مادة عبدالرحمن الخاصة V412',2,4938271.5,2000,'بطارية'),
(-412103,-412103,-412102,'مادة عبدالرحمن الخاصة V412',3,2921810.6666666667,2000,'بطارية'),
(-412104,-412104,-412102,'مادة عبدالرحمن الخاصة V412',4,1913580.25,2000,'بطارية'),
(-412105,-412105,-412101,'مادة سفيان الخاصة V412',2,111111,1000,'انفيرتر'),
(-412106,-412106,-412102,'مادة عبدالرحمن الخاصة V412',5,1308642,2000,'بطارية');
-- Legacy item triggers update product quantities; mirror only these synthetic
-- products in their assigned warehouse before the deferred consistency check.
update solar_private.warehouse_stocks w set qty=p.qty from products p where w.product_id=p.id and w.warehouse_id=410001 and p.id in(-412101,-412102);
commit;
