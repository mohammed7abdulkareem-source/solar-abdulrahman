\set ON_ERROR_STOP on
begin;
do $$ begin
 if current_database()<>'solar_v4113_warehouse_browser' then raise exception 'Use the isolated warehouse browser fixture';end if;
end $$;
insert into public.profiles(id,display_name,user_type,active,is_admin,permissions,phone) values
 ('00000000-0000-0000-0000-000000411351','أمين تجهيز الاختبار','warehouse',true,false,'{}','07704113510');
insert into public.products(id,code,name,qty,cost) values
 (-411351,'PREP-A','لوح فحص التجهيز',45,17000),
 (-411352,'PREP-B','بطارية فحص التجهيز',35,32000);
insert into public.customers(id,name,customer_type,owner_id) values
 (-411351,'فحص تجهيز الوصل المتاح','wholesale','00000000-0000-0000-0000-000000400101'),
 (-411352,'فحص تجهيز بانتظار التسعير','wholesale','00000000-0000-0000-0000-000000400101');
insert into public.transactions(id,kind,warehouse_id,warehouse_name,party_name,created_by,total) values
 (-411353,'sale',2,'مخزن صيادة','فحص تجهيز خارج الصلاحية','00000000-0000-0000-0000-000000400101',0);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000400101',true);
do $$ declare result jsonb;begin
 perform public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","warehouseId":1,"mode":"credit","partyId":-411351,"party":"فحص تجهيز الوصل المتاح","items":[{"id":-411351,"qty":3,"price":22000}]}');
 result:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","warehouseId":1,"mode":"credit","partyId":-411352,"party":"فحص تجهيز بانتظار التسعير","items":[{"id":-411351,"qty":2,"price":22000}]}');
 perform set_config('test.warehouse.pricing',result->>'id',true);
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411351',true);
do $$ declare receipt jsonb; lines jsonb;begin
 receipt:=public.solar_warehouse_orders('@id:'||current_setting('test.warehouse.pricing'),'')->'rows'->0;
 select jsonb_agg(jsonb_build_object('lineId',r->'lineId','productId',r->'productId','qty',r->'qty')) into lines from jsonb_array_elements(receipt->'items') r;
 lines:=lines||jsonb_build_array(jsonb_build_object('productId',-411352,'qty',1));
 perform public.solar_warehouse_action((receipt->>'id')::bigint,receipt->>'token','save',lines,'إضافة بطارية للتسعير');
end$$;
commit;
