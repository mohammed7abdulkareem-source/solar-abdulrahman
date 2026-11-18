-- Synthetic LOCAL V4.1.9 browser database only; never run on a hosted project.
\set ON_ERROR_STOP on
begin;
do $$begin if current_database()<>'solar_v419_browser' then raise exception 'Use isolated solar_v419_browser';end if;end$$;
insert into profiles(id,username,display_name,is_admin,user_type,active,phone,permissions)values
('00000000-0000-0000-0000-000000419501','qa419admin','مدير تصحيح المشتريات V419',true,'admin_staff',true,'07704195001','{}'),
('00000000-0000-0000-0000-000000419502','qa419owner','صاحب المشتريات والمبيعات V419',false,'admin_staff',true,'07704195002','{"purchase":true,"sale":true,"system":true,"salesHistory":true,"cash":true,"stock":true,"stockMovement":true,"warehouse":true,"supplierStatement":true,"supplierBalances":true,"supplierPayment":true,"customerStatement":true,"installations":true,"exchangeRateEdit":true,"profit":true}'),
('00000000-0000-0000-0000-000000419503','qa419other','مستخدم آخر V419',false,'admin_staff',true,'07704195003','{"purchase":true,"sale":true,"cash":true,"stock":true}'),
('00000000-0000-0000-0000-000000419504','qa419warehouse','مسؤول المخزن V419',false,'warehouse',true,'07704195004','{}'),
('00000000-0000-0000-0000-000000419505','qa419installer','مهندس المنظومة V419',false,'installer',true,'07704195005','{}');
insert into suppliers(id,name,account_currency)values
(-419501,'مورد المتوسط المختلط V419','IQD'),(-419502,'مورد المادة المستهلكة V419','IQD'),
(-419503,'مورد الشراء النقدي V419','IQD'),(-419504,'مورد الشراء الدولاري V419','USD'),
(-419505,'مورد نقص المخزون V419','IQD'),(-419506,'مورد المخزون المحجوز V419','IQD'),(-419507,'مورد منظومة مجهزة V419','IQD'),
(-419508,'مورد مثال الخمسمئة V419','IQD'),(-419509,'مورد مثال الخمسمئة المباع V419','IQD'),(-419510,'مورد دولار بتسديد لاحق V419','USD');
insert into customers(id,name,customer_type,owner_id)values
(-419501,'عميل الجملة V419','wholesale','00000000-0000-0000-0000-000000419502'),
(-419502,'عميل المنظومة V419','system','00000000-0000-0000-0000-000000419502');
insert into products(id,code,name,category,qty,cost)values
(-419501,'V419-WEIGHTED','انفيرتر المتوسط المختلط V419','انفيرتر',10,1000),
(-419502,'V419-CONSUMED','بطارية مستهلكة بالكامل V419','بطارية',0,0),
(-419503,'V419-CASH-IQD','لوح شراء نقدي V419','لوح',10,1000),
(-419504,'V419-CASH-USD','انفيرتر شراء دولاري V419','انفيرتر',10,1660),
(-419505,'V419-SHORT','بطارية نقص التصحيح V419','بطارية',0,0),
(-419506,'V419-RESERVED','لوح محجوز للنقل V419','لوح',0,0),
(-419507,'V419-SYSTEM','انفيرتر منظومة مجهزة V419','انفيرتر',6,1000),
(-419508,'V419-UNRELATED','مادة مستقلة لا تتغير V419','أخرى',7,900),
(-419509,'V419-500-600','مادة مثال خمسمئة وست مئة V419','لوح',500,100000),
(-419510,'V419-500-600-SOLD','مادة مثال خمسمئة مع بيع لاحق V419','لوح',500,100000),
(-419511,'V419-USD-PAID','بطارية دولار بتسديد لاحق V419','بطارية',4,1660);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)
select 1,id,qty from products where id between -419511 and -419501
on conflict(warehouse_id,product_id)do update set qty=excluded.qty;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419501',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000419502","mode":"deposit","currency":"IQD","amount":1000000,"note":"تمويل محلي V419"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000419502","mode":"deposit","currency":"USD","amount":1000,"rate":1660,"note":"تمويل دولار محلي V419"}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419502',true);
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد المتوسط المختلط V419","partyId":-419501,"warehouseId":1,"mode":"credit","sourceCurrency":"IQD","notes":"v419-mixed-purchase","items":[{"id":-419501,"qty":10,"price":2000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"عميل الجملة V419","partyId":-419501,"warehouseId":1,"mode":"cash","notes":"v419-mixed-sale-1","items":[{"id":-419501,"qty":8,"price":5000},{"id":-419508,"qty":1,"price":3000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد المتوسط المختلط V419","partyId":-419501,"warehouseId":1,"mode":"credit","sourceCurrency":"IQD","notes":"v419-mixed-later-purchase","items":[{"id":-419501,"qty":8,"price":3000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"عميل الجملة V419","partyId":-419501,"warehouseId":1,"mode":"credit","notes":"v419-mixed-sale-2","items":[{"id":-419501,"qty":4,"price":6000}]}');
select public.solar_fx('payment',gen_random_uuid(),'{"supplierId":-419501,"paymentId":-419591,"amount":5000,"currency":"IQD","rate":1660,"accountRevision":0,"mode":"cash","note":"v419-later-supplier-payment"}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد المادة المستهلكة V419","partyId":-419502,"warehouseId":1,"mode":"credit","sourceCurrency":"IQD","notes":"v419-consumed-purchase","items":[{"id":-419502,"qty":4,"price":1000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"عميل الجملة V419","partyId":-419501,"warehouseId":1,"mode":"credit","notes":"v419-consumed-sale","items":[{"id":-419502,"qty":4,"price":2000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد الشراء النقدي V419","partyId":-419503,"warehouseId":1,"mode":"cash","sourceCurrency":"IQD","notes":"v419-cash-iqd-purchase","items":[{"id":-419503,"qty":2,"price":2000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"عميل الجملة V419","partyId":-419501,"warehouseId":1,"mode":"credit","notes":"v419-cash-iqd-sale","items":[{"id":-419503,"qty":1,"price":5000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد الشراء الدولاري V419","partyId":-419504,"warehouseId":1,"mode":"cash","sourceCurrency":"USD","exchangeRate":1660,"marketRate":1660,"cashCurrency":"USD","accountRevision":0,"notes":"v419-cash-usd-purchase","items":[{"id":-419504,"qty":2,"price":2}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"عميل الجملة V419","partyId":-419501,"warehouseId":1,"mode":"credit","notes":"v419-cash-usd-sale","items":[{"id":-419504,"qty":1,"price":10000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد نقص المخزون V419","partyId":-419505,"warehouseId":1,"mode":"credit","sourceCurrency":"IQD","notes":"v419-short-purchase","items":[{"id":-419505,"qty":5,"price":1000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"عميل الجملة V419","partyId":-419501,"warehouseId":1,"mode":"credit","notes":"v419-short-sale","items":[{"id":-419505,"qty":4,"price":2000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد المخزون المحجوز V419","partyId":-419506,"warehouseId":1,"mode":"credit","sourceCurrency":"IQD","notes":"v419-reserved-purchase","items":[{"id":-419506,"qty":10,"price":1000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد منظومة مجهزة V419","partyId":-419507,"warehouseId":1,"mode":"credit","sourceCurrency":"IQD","notes":"v419-system-purchase","items":[{"id":-419507,"qty":6,"price":3000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","party":"عميل المنظومة V419","partyId":-419502,"warehouseId":1,"mode":"credit","total":10000,"customerAddress":"عنوان محلي V419","installerId":"00000000-0000-0000-0000-000000419505","notes":"v419-prepared-system","items":[{"id":-419507,"qty":2,"price":0}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"عميل الجملة V419","partyId":-419501,"warehouseId":1,"mode":"credit","notes":"v419-unrelated-sale","items":[{"id":-419508,"qty":1,"price":3000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد مثال الخمسمئة V419","partyId":-419508,"warehouseId":1,"mode":"credit","sourceCurrency":"IQD","notes":"v419-500-600-purchase","items":[{"id":-419509,"qty":600,"price":130000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد مثال الخمسمئة المباع V419","partyId":-419509,"warehouseId":1,"mode":"credit","sourceCurrency":"IQD","notes":"v419-500-600-sold-purchase","items":[{"id":-419510,"qty":600,"price":130000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"عميل الجملة V419","partyId":-419501,"warehouseId":1,"mode":"credit","notes":"v419-500-600-later-sale","items":[{"id":-419510,"qty":100,"price":200000}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","party":"مورد دولار بتسديد لاحق V419","partyId":-419510,"warehouseId":1,"mode":"credit","sourceCurrency":"USD","exchangeRate":1660,"marketRate":1660,"cashCurrency":"IQD","accountRevision":0,"notes":"v419-usd-paid-purchase","items":[{"id":-419511,"qty":6,"price":2}]}');
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"عميل الجملة V419","partyId":-419501,"warehouseId":1,"mode":"credit","notes":"v419-usd-paid-sale","items":[{"id":-419511,"qty":2,"price":10000}]}');
select public.solar_fx('payment',gen_random_uuid(),'{"supplierId":-419510,"paymentId":-419592,"amount":5,"currency":"USD","rate":1800,"accountRevision":0,"mode":"cash","note":"v419-later-usd-payment"}');
-- The fixture's approved installation amount is paid once, independently of a purchase correction.
update transactions set warehouse_status='ready',warehouse_prepared_at=now() where notes='v419-prepared-system';
select public.solar_installation_action(id,installation_revision,'close','{"amount":1000}')from transactions where notes='v419-prepared-system';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000419501',true);
insert into solar_private.warehouses(id,name,code,is_primary,active)overriding system value values(-419501,'مخزن وجهة الحجز V419','V419-DESTINATION',false,true);
select public.solar_inventory('transfer','00000000-0000-0000-0000-000000419601',jsonb_build_object('fromId',1,'toId',-419501,'items',jsonb_build_array(jsonb_build_object('productId',-419506,'qty',3,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=1 and product_id=-419506))),'note','حجز لا يلغيه تعديل الشراء V419'));
set constraints all immediate;
commit;
