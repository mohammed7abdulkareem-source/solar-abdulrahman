-- V4.1.5 exact material picker fixture. Local disposable database only.
-- Isolated local test data. Never execute on production.
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions)values
('00000000-0000-0000-0000-000000415501','مدير كشف المواد',true,'admin_staff','07700003920','{}'),
('00000000-0000-0000-0000-000000415502','بائع كشف المواد',false,'admin_staff','07700003921','{"sale":true,"system":true,"purchase":true,"stock":true,"stockMovement":true,"warehouse":true,"exchangeRateEdit":true}'),
('00000000-0000-0000-0000-000000415503','مجهز كشف المواد',false,'warehouse','07700003922','{}'),
('00000000-0000-0000-0000-000000415504','بائع آخر للمواد',false,'admin_staff','07700003923','{"sale":true,"stockMovement":true}'),
('00000000-0000-0000-0000-000000415505','مشاهد كميات فقط',false,'admin_staff','07700003924','{"stockMovement":true}'),
('00000000-0000-0000-0000-000000415506','مهندس المواد',true,'installer','07700003925','{}');
insert into brands(id,name)values(-415501,'FULLMAX QA415');
insert into products(id,code,name,qty,cost,brand_id,category)values(-415501,'V415-A-15','انفيرتر 15KW فحص دقيق',10,1000,-415501,'ألواح'),(-415502,'V415-B-15','انفيرتر 15KW بديل',2,500,-415501,'بطارية');
insert into suppliers(id,name,account_currency)values(-415501,'مورد كشف المواد','IQD'),(-415502,'مورد كشف دولار','USD');
insert into customers(id,name,customer_type,owner_id)values(-415501,'زبون بيع الألواح','wholesale','00000000-0000-0000-0000-000000415502'),(-415502,'زبون منظومة الألواح','system','00000000-0000-0000-0000-000000415502');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000415501',true);
select public.solar_inventory('access_save',gen_random_uuid(),'{"userId":"00000000-0000-0000-0000-000000415502","all":true,"ids":[],"revision":0}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000415502',true);
do $$declare r jsonb;main bigint:=solar_private.primary_warehouse();begin
 perform public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','purchase','warehouseId',main,'party','مورد كشف المواد','partyId',-415501,'mode','credit','sourceCurrency','IQD','exchangeRate',1,'marketRate',1660,'accountRevision',0,'items','[{"id":-415501,"qty":5,"price":2000}]'::jsonb));
 perform public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','purchase','warehouseId',main,'party','مورد كشف دولار','partyId',-415502,'mode','credit','sourceCurrency','USD','exchangeRate',1660,'marketRate',1660,'accountRevision',0,'items','[{"id":-415501,"qty":2,"price":1.25}]'::jsonb));
 r:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','sale','warehouseId',main,'party','زبون بيع الألواح','partyId',-415501,'mode','credit','items','[{"id":-415501,"qty":3,"price":3000}]'::jsonb));
 perform set_config('test.material.sale',r->>'id',true);
 perform public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','system','warehouseId',main,'party','زبون منظومة الألواح','partyId',-415502,'mode','credit','total',500000,'customerAddress','عنوان الاختبار','installerId','00000000-0000-0000-0000-000000415506','items','[{"id":-415501,"qty":1,"price":0}]'::jsonb));
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000415503',true);
do $$declare r jsonb;begin r:=public.solar_warehouse_orders('','pending',0);select value into r from jsonb_array_elements(r->'rows')where(value->>'id')::bigint=current_setting('test.material.sale')::bigint;perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','ready');end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000415501',true);
do $$declare r jsonb;request uuid:=gen_random_uuid();main bigint:=solar_private.primary_warehouse();destination bigint;begin
 select id into destination from solar_private.warehouses where code='SAYADA';
 r:=public.solar_inventory('transfer',request,jsonb_build_object('fromId',main,'toId',destination,'items',jsonb_build_array(jsonb_build_object('productId',-415501,'qty',2,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=main and product_id=-415501))),'note','نقل مجهز للكشف'));
 perform public.solar_inventory('prepare_transfer',gen_random_uuid(),jsonb_build_object('id',request,'expectedRevision',0));
 request:=gen_random_uuid();
 perform public.solar_inventory('transfer',request,jsonb_build_object('fromId',main,'toId',destination,'items',jsonb_build_array(jsonb_build_object('productId',-415501,'qty',1,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=main and product_id=-415501))),'note','نقل ملغى للكشف'));
 perform public.solar_inventory('cancel_transfer',gen_random_uuid(),jsonb_build_object('id',request,'expectedRevision',0,'note','ألغي قبل التجهيز'));
 request:=gen_random_uuid();
 perform public.solar_inventory('transfer',request,jsonb_build_object('fromId',main,'toId',destination,'items',jsonb_build_array(jsonb_build_object('productId',-415501,'qty',1,'revision',(select revision from solar_private.warehouse_stocks where warehouse_id=main and product_id=-415501))),'note','نقل معكوس للكشف'));
 perform public.solar_inventory('prepare_transfer',gen_random_uuid(),jsonb_build_object('id',request,'expectedRevision',0));
 perform public.solar_inventory('reverse_transfer',gen_random_uuid(),jsonb_build_object('id',request,'expectedRevision',1));
 perform public.solar_reconcile('stock_balance',gen_random_uuid(),jsonb_build_object('warehouseId',main,'productId',-415501,'expected',(select qty from solar_private.warehouse_stocks where warehouse_id=main and product_id=-415501),'actual',10,'note','مطابقة كمية الاختبار'));
end$$;
-- Separate matching identity and zero-stock historic material: chosen by ID, never by broad text.
insert into brands(id,name) values(-415502,'GROWATT QA415');
update products set brand_id=-415502,category='انفيرتر' where id=-415502;
update products set category='انفيرتر' where id=-415501;
insert into products(id,code,name,qty,cost,brand_id,category) values
(-415503,'V415-ZERO-15','انفيرتر 15KW نفد من المخزن',2,500,-415502,'انفيرتر');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000415502',true);
select public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','sale','warehouseId',solar_private.primary_warehouse(),'party','زبون بيع الألواح','partyId',-415501,'mode','credit','items','[{"id":-415502,"qty":1,"price":3000}]'::jsonb));
select public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','sale','warehouseId',solar_private.primary_warehouse(),'party','زبون بيع الألواح','partyId',-415501,'mode','credit','items','[{"id":-415503,"qty":2,"price":3000}]'::jsonb));
-- Synthetic dates only: create an opening movement outside today's filter.
update solar_private.stock_adjustments set created_at=now()-interval '2 days' where product_id=-415501;
commit;
