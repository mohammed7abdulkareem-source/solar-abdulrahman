-- Disposable local browser fixture only. No production rows or credentials.
\set ON_ERROR_STOP on
begin;
do $$begin
 if current_database()<>'solar_v4_browser' then raise exception 'Use solar_v4_browser only';end if;
end$$;
insert into profiles(id,username,display_name,is_admin,user_type,phone,permissions)values
('00000000-0000-0000-0000-000000400101','v4_admin','مدير الإصدار الرابع',true,'admin_staff','07700400101','{}'),
('00000000-0000-0000-0000-000000400102','v4_owner','بائع الإصدار الرابع',false,'admin_staff','07700400102','{"sale":true,"purchase":true,"system":true,"installations":true,"stockMovement":true,"salesHistory":true,"customerStatement":true,"cash":true,"cashExpense":true,"systemPayment":true}'),
('00000000-0000-0000-0000-000000400103','v4_free','بائع حر الإصدار الرابع',false,'admin_staff','07700400103','{"sale":true,"system":true,"cash":true,"wholesaleFreePricing":true}'),
('00000000-0000-0000-0000-000000400104','v4_warehouse','مخزن الإصدار الرابع',false,'warehouse','07700400104','{}'),
('00000000-0000-0000-0000-000000400105','v4_installer','مهندس الإصدار الرابع',false,'installer','07700400105','{}'),
('00000000-0000-0000-0000-000000400106','v4_manager','مسؤول أسعار دون بيع حر',false,'admin_staff','07700400106','{"sale":true,"wholesalePricingManage":true}');
insert into products(id,code,name,category,qty,cost)values
(-400101,'V4-PRICE-01','مادة الجملة V4','ألواح',100,12345),
(-400102,'V4-PRICE-02','مادة حرة V4','بطاريات',80,54321),
(-400103,'V4-PURCHASE-01','مادة الشراء V4','ألواح',0,0),
(-400104,'V4-SHORT-01','مادة النقص V4','ألواح',0,0),
(-400105,'V4-DELETE-01','مادة حذف الوصل V4','انفيرتر',100,100000);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)
select 1,id,qty from products where id between -400105 and -400101
on conflict(warehouse_id,product_id)do update set qty=excluded.qty;
insert into customers(id,name,phone,customer_type,owner_id)values
(-400101,'عميل جملة الإصدار الرابع','07700410101','wholesale','00000000-0000-0000-0000-000000400102'),
(-400102,'عميل منظومة الإصدار الرابع','07700410102','system','00000000-0000-0000-0000-000000400102'),
(-400103,'عميل البائع الحر V4','07700410103','wholesale','00000000-0000-0000-0000-000000400103');
insert into suppliers(id,name,phone,account_currency)values(-400101,'مورد اختبار V4','07700420101','IQD');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000400101',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000400102","mode":"deposit","currency":"IQD","amount":10000000,"note":"V4 isolated browser opening deposit"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000400101","mode":"deposit","currency":"IQD","amount":10000000,"note":"V4 isolated admin opening deposit"}');
commit;
