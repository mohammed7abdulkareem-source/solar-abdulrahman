-- Disposable browser database based on the V415 material-picker fixture.
begin;
do $$ begin
 if current_database() !~ '^solar_.*_browser$' then raise exception 'Local browser database required'; end if;
end $$;
insert into public.products(id,code,name,qty,cost,brand_id,category) values
 (-411670,'V4116-STOCK-A','ألواح فحص المخازن',9.125,87654,-415501,'ألواح'),
 (-411671,'V4116-STOCK-B','مادة محجوزة بالكامل',4,12345,-415501,'بطارية'),
 (-411672,'V4116-STOCK-Z','مادة بدون كمية',0,77777,-415501,'انفيرتر');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000415501',true);
do $$
declare
 primary_id bigint:=solar_private.primary_warehouse();
 destination bigint:=(select id from solar_private.warehouses where code='SAYADA');
 transfer_id uuid:=gen_random_uuid();
begin
 perform public.solar_inventory('transfer',transfer_id,jsonb_build_object('fromId',primary_id,'toId',destination,'items',
   jsonb_build_array(jsonb_build_object('productId',-411670,'qty',4,'revision',
   (select revision from solar_private.warehouse_stocks where warehouse_id=primary_id and product_id=-411670)))));
 perform public.solar_inventory('prepare_transfer',gen_random_uuid(),jsonb_build_object('id',transfer_id,'expectedRevision',0));
 perform public.solar_inventory('transfer',gen_random_uuid(),jsonb_build_object('fromId',primary_id,'toId',destination,'items',
   jsonb_build_array(jsonb_build_object('productId',-411670,'qty',2,'revision',
   (select revision from solar_private.warehouse_stocks where warehouse_id=primary_id and product_id=-411670)),
   jsonb_build_object('productId',-411671,'qty',4,'revision',
   (select revision from solar_private.warehouse_stocks where warehouse_id=primary_id and product_id=-411671)))));
end $$;
commit;
