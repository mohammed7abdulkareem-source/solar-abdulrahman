-- Disposable V4.1.3 baseline. Never apply to production.
\set ON_ERROR_STOP on
begin;
do $$begin
 if current_database()<>'solar_expense_charge_browser' then raise exception 'Wrong fixture database';end if;
 if exists(select 1 from profiles where id='00000000-0000-0000-0000-000000415101') then raise exception 'Fixture already seeded';end if;
end$$;
insert into profiles(id,username,display_name,is_admin,user_type,active,phone,permissions) values
('00000000-0000-0000-0000-000000415101','expense_admin','مدير اختبار مصاريف البيع',true,'admin_staff',true,'07700415101','{}'),
('00000000-0000-0000-0000-000000415102','expense_owner','صاحب اختبار مصاريف البيع',false,'admin_staff',true,'07700415102','{"sale":true,"system":true,"purchase":true,"customers":true,"customerStatement":true,"stock":true,"warehouse":true,"cash":true,"profit":true,"profitSettlement":true,"installations":true}'),
('00000000-0000-0000-0000-000000415103','expense_warehouse','مسؤول مخزن اختبار المصاريف',false,'warehouse',true,'07700415103','{}'),
('00000000-0000-0000-0000-000000415104','expense_other','بائع آخر لا يرى المصاريف',false,'admin_staff',true,'07700415104','{"sale":true}'),
('00000000-0000-0000-0000-000000415105','expense_installer','مهندس اختبار المصاريف',false,'installer',true,'07700415105','{}');
insert into solar_private.warehouses(id,name,code) overriding system value values(415001,'مخزن اختبار مصاريف البيع','EXPENSE-415');
insert into solar_private.warehouse_access(user_id,warehouse_ids)
select id,array[415001]::bigint[] from profiles where id::text between '00000000-0000-0000-0000-000000415102' and '00000000-0000-0000-0000-000000415105';
insert into products(id,code,name,category,qty,cost) values
(-415101,'EXPENSE-415-MAIN','مادة اختبار مصاريف الجملة','بطارية',100,125000),
(-415102,'EXPENSE-415-ADDED','مادة جديدة لتسعير المخزن','ألواح',100,50000),
(-415103,'EXPENSE-415-PURCHASE','مادة شراء مستقلة للمقارنة','انفيرتر',100,90000);
update solar_private.warehouse_stocks set qty=0 where product_id between -415103 and -415101;
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty,reserved_qty)
select 415001,id,100,0 from products where id between -415103 and -415101;
insert into customers(id,name,phone,customer_type,owner_id) values
(-415101,'عميل اختبار مصاريف الجملة','07700415901','wholesale','00000000-0000-0000-0000-000000415102'),
(-415102,'عميل منظومة المقارنة','07700415902','system','00000000-0000-0000-0000-000000415102');
insert into suppliers(id,name,phone,account_currency) values(-415101,'مورد مقارنة المصاريف','07700415903','IQD');
commit;
