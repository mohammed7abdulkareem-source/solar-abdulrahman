-- LOCAL TEST DATABASE ONLY. Apply multi-warehouse-browser-seed.sql first.
update profiles set phone='07700000001';
update profiles set phone=null,permissions=permissions||'{"profit":true,"profitSettlement":true,"customerPayment":true,"systemPayment":true}' where id='00000000-0000-0000-0000-000000003501';
insert into profiles(id,display_name,username,is_admin,user_type,phone,permissions) values('00000000-0000-0000-0000-000000003504','مستفيد الربح','profit_recipient',false,'admin_staff','07700000004','{"profit":true,"profitSettlement":true}');
update customers set owner_id='00000000-0000-0000-0000-000000003501';
insert into products(id,code,name,qty,cost) values(-352003,'352003','مادة صفرية',0,1000);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003501',false);
select solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","party":"زبون تجريبي جملة","sourceCurrency":"IQD","expenses":0,"items":[{"id":-350001,"qty":1,"price":150000}],"warranty":{"enabled":true,"items":[{"id":-350001,"duration":2,"unit":"years"}],"maintenance":{"duration":6,"unit":"months"}}}');
select solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","party":"زبون تجريبي جملة","sourceCurrency":"IQD","expenses":0,"items":[{"id":-350001,"qty":1,"price":150000}]}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003500',false);
select solar_inventory('transfer',gen_random_uuid(),jsonb_build_object('fromId',(select id from solar_private.warehouses where is_primary),'toId',(select id from solar_private.warehouses where code='SAYADA'),'items',jsonb_build_array(jsonb_build_object('productId',-350002,'qty',8,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=(select id from solar_private.warehouses where is_primary) and product_id=-350002)))));
