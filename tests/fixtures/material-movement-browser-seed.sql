-- Isolated local test data. Never execute on production.
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions)values
('00000000-0000-0000-0000-000000003920','مدير كشف المواد',true,'admin_staff','07700003920','{}'),
('00000000-0000-0000-0000-000000003921','بائع كشف المواد',false,'admin_staff','07700003921','{"sale":true,"system":true,"purchase":true,"stock":true,"stockMovement":true,"warehouse":true,"exchangeRateEdit":true}'),
('00000000-0000-0000-0000-000000003922','مجهز كشف المواد',false,'warehouse','07700003922','{}'),
('00000000-0000-0000-0000-000000003923','بائع آخر للمواد',false,'admin_staff','07700003923','{"sale":true,"stockMovement":true}'),
('00000000-0000-0000-0000-000000003924','مشاهد كميات فقط',false,'admin_staff','07700003924','{"stockMovement":true}'),
('00000000-0000-0000-0000-000000003925','مهندس المواد',true,'installer','07700003925','{}');
insert into brands(id,name)values(-392001,'براند الاختبار');
insert into products(id,code,name,qty,cost,brand_id,category)values(-392001,'39201','لوح كشف الحركة',10,1000,-392001,'ألواح'),(-392002,'39202','بطارية أخرى',2,500,-392001,'بطارية');
insert into suppliers(id,name,account_currency)values(-392001,'مورد كشف المواد','IQD'),(-392002,'مورد كشف دولار','USD');
insert into customers(id,name,customer_type,owner_id)values(-392001,'زبون بيع الألواح','wholesale','00000000-0000-0000-0000-000000003921'),(-392002,'زبون منظومة الألواح','system','00000000-0000-0000-0000-000000003921');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003920',true);
select public.solar_inventory('access_save',gen_random_uuid(),'{"userId":"00000000-0000-0000-0000-000000003921","all":true,"ids":[],"revision":0}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003921',true);
do $$declare r jsonb;main bigint:=solar_private.primary_warehouse();begin
 perform public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','purchase','warehouseId',main,'party','مورد كشف المواد','partyId',-392001,'mode','credit','sourceCurrency','IQD','exchangeRate',1,'marketRate',1660,'accountRevision',0,'items','[{"id":-392001,"qty":5,"price":2000}]'::jsonb));
 perform public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','purchase','warehouseId',main,'party','مورد كشف دولار','partyId',-392002,'mode','credit','sourceCurrency','USD','exchangeRate',1660,'marketRate',1660,'accountRevision',0,'items','[{"id":-392001,"qty":2,"price":1.25}]'::jsonb));
 r:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','sale','warehouseId',main,'party','زبون بيع الألواح','partyId',-392001,'mode','credit','items','[{"id":-392001,"qty":3,"price":3000}]'::jsonb));
 perform set_config('test.material.sale',r->>'id',true);
 perform public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','system','warehouseId',main,'party','زبون منظومة الألواح','partyId',-392002,'mode','credit','total',500000,'customerAddress','عنوان الاختبار','installerId','00000000-0000-0000-0000-000000003925','items','[{"id":-392001,"qty":1,"price":0}]'::jsonb));
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003922',true);
do $$declare r jsonb;begin r:=public.solar_warehouse_orders('','pending',0);select value into r from jsonb_array_elements(r->'rows')where(value->>'id')::bigint=current_setting('test.material.sale')::bigint;perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','ready');end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003920',true);
do $$declare r jsonb;request uuid:=gen_random_uuid();main bigint:=solar_private.primary_warehouse();destination bigint;begin
 select id into destination from solar_private.warehouses where code='SAYADA';
 r:=public.solar_inventory('transfer',request,jsonb_build_object('fromId',main,'toId',destination,'items',jsonb_build_array(jsonb_build_object('productId',-392001,'qty',2,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=main and product_id=-392001))),'note','نقل مجهز للكشف'));
 perform public.solar_inventory('prepare_transfer',gen_random_uuid(),jsonb_build_object('id',request,'expectedRevision',0));
 request:=gen_random_uuid();
 perform public.solar_inventory('transfer',request,jsonb_build_object('fromId',main,'toId',destination,'items',jsonb_build_array(jsonb_build_object('productId',-392001,'qty',1,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=main and product_id=-392001))),'note','نقل ملغى للكشف'));
 perform public.solar_inventory('cancel_transfer',gen_random_uuid(),jsonb_build_object('id',request,'expectedRevision',0,'note','ألغي قبل التجهيز'));
 request:=gen_random_uuid();
 perform public.solar_inventory('transfer',request,jsonb_build_object('fromId',main,'toId',destination,'items',jsonb_build_array(jsonb_build_object('productId',-392001,'qty',1,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=main and product_id=-392001))),'note','نقل معكوس للكشف'));
 perform public.solar_inventory('prepare_transfer',gen_random_uuid(),jsonb_build_object('id',request,'expectedRevision',0));
 perform public.solar_inventory('reverse_transfer',gen_random_uuid(),jsonb_build_object('id',request,'expectedRevision',1));
 perform public.solar_reconcile('stock_balance',gen_random_uuid(),jsonb_build_object('warehouseId',main,'productId',-392001,'expected',(select qty from solar_private.warehouse_stocks where warehouse_id=main and product_id=-392001),'actual',10,'note','مطابقة كمية الاختبار'));
end$$;
commit;
